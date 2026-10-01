-- 계급/진급 시스템
-- 실행 후 GitHub Pages의 수정된 index.html을 배포하세요.

create table if not exists public.ranks (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  rank_order integer not null unique,
  promotion_cost bigint not null default 0 check (promotion_cost >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists rank_id uuid references public.ranks(id) on delete set null;

create index if not exists profiles_rank_id_idx on public.profiles(rank_id);
create index if not exists ranks_rank_order_idx on public.ranks(rank_order);

insert into public.ranks(name, rank_order, promotion_cost)
values ('일반 회원', 1, 0)
on conflict (name) do nothing;

-- 기존 회원에게 기본 계급을 부여합니다.
update public.profiles p
set rank_id = r.id
from public.ranks r
where r.rank_order = 1
  and p.rank_id is null;

alter table public.ranks enable row level security;

drop policy if exists "Anyone authenticated can read ranks" on public.ranks;
create policy "Anyone authenticated can read ranks"
on public.ranks for select to authenticated using (true);

drop policy if exists "Admins can insert ranks" on public.ranks;
create policy "Admins can insert ranks"
on public.ranks for insert to authenticated
with check (public.is_admin());

drop policy if exists "Admins can update ranks" on public.ranks;
create policy "Admins can update ranks"
on public.ranks for update to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Admins can delete ranks" on public.ranks;
create policy "Admins can delete ranks"
on public.ranks for delete to authenticated
using (public.is_admin());

-- 기존 profiles 보호 트리거가 rank_id/coin_balance 변경을 막는 경우,
-- 진급 RPC 내부에서만 허용되도록 수정합니다.
create or replace function public.prevent_member_privilege_changes()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is not null and not public.is_admin() then
    if new.id <> old.id
      or new.email <> old.email
      or new.role <> old.role
      or new.status <> old.status then
      raise exception '권한이 없는 필드입니다';
    end if;

    if new.rank_id is distinct from old.rank_id
       and current_setting('dohongjonwi.rank_purchase', true) <> '1' then
      raise exception '계급 변경은 진급 요청을 통해서만 가능합니다';
    end if;
  end if;
  return new;
end;
$function$;

-- 한 단계만 진급합니다. 코인 차감과 계급 변경을 하나의 트랜잭션에서 처리합니다.
create or replace function public.purchase_next_rank()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_current_order integer;
  v_next_id uuid;
  v_next_name text;
  v_cost bigint;
  v_balance bigint;
  v_new_balance bigint;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;

  select coalesce(r.rank_order, 0), p.coin_balance
    into v_current_order, v_balance
  from public.profiles p
  left join public.ranks r on r.id = p.rank_id
  where p.id = v_uid
  for update;

  if v_balance is null then raise exception '회원 정보를 찾을 수 없습니다.'; end if;

  select id, name, promotion_cost
    into v_next_id, v_next_name, v_cost
  from public.ranks
  where rank_order = v_current_order + 1;

  if v_next_id is null then
    raise exception '더 이상 진급할 계급이 없습니다.';
  end if;

  if v_balance < v_cost then
    raise exception '코인이 부족합니다. 필요한 코인: %', v_cost;
  end if;

  perform set_config('dohongjonwi.rank_purchase', '1', true);

  v_new_balance := v_balance - v_cost;
  update public.profiles
  set rank_id = v_next_id,
      coin_balance = v_new_balance,
      updated_at = now()
  where id = v_uid;

  return jsonb_build_object(
    'rank_id', v_next_id,
    'rank_name', v_next_name,
    'cost', v_cost,
    'new_balance', v_new_balance
  );
end;
$function$;

grant execute on function public.purchase_next_rank() to authenticated;

-- 관리자용 계급 생성
create or replace function public.admin_create_rank(p_name text, p_order integer, p_cost bigint)
returns public.ranks
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_rank public.ranks;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if trim(p_name) = '' then raise exception '계급 이름을 입력해 주세요.'; end if;
  if p_order < 1 then raise exception '계급 순서는 1 이상이어야 합니다.'; end if;
  if p_cost < 0 then raise exception '진급 코인은 0 이상이어야 합니다.'; end if;
  insert into public.ranks(name, rank_order, promotion_cost)
  values(trim(p_name), p_order, p_cost)
  returning * into v_rank;
  return v_rank;
end;
$function$;

grant execute on function public.admin_create_rank(text, integer, bigint) to authenticated;

-- 관리자용 계급 수정
create or replace function public.admin_update_rank(p_id uuid, p_name text, p_order integer, p_cost bigint)
returns public.ranks
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_rank public.ranks;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if trim(p_name) = '' then raise exception '계급 이름을 입력해 주세요.'; end if;
  if p_order < 1 then raise exception '계급 순서는 1 이상이어야 합니다.'; end if;
  if p_cost < 0 then raise exception '진급 코인은 0 이상이어야 합니다.'; end if;
  update public.ranks
  set name=trim(p_name), rank_order=p_order, promotion_cost=p_cost, updated_at=now()
  where id=p_id
  returning * into v_rank;
  if v_rank.id is null then raise exception '계급을 찾을 수 없습니다.'; end if;
  return v_rank;
end;
$function$;

grant execute on function public.admin_update_rank(uuid, text, integer, bigint) to authenticated;

-- 관리자용 계급 삭제. 현재 회원이 사용하는 계급은 삭제하지 못하게 합니다.
create or replace function public.admin_delete_rank(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if exists (select 1 from public.profiles where rank_id=p_id) then
    raise exception '현재 회원이 사용 중인 계급은 삭제할 수 없습니다.';
  end if;
  delete from public.ranks where id=p_id;
  return found;
end;
$function$;

grant execute on function public.admin_delete_rank(uuid) to authenticated;

-- 계급 순서 위/아래 이동. 두 계급의 순서를 원자적으로 교환합니다.
create or replace function public.admin_move_rank(p_id uuid, p_direction integer)
returns public.ranks
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_rank public.ranks;
  v_other public.ranks;
  v_order integer;
  v_other_order integer;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if p_direction not in (-1,1) then raise exception '이동 방향이 올바르지 않습니다.'; end if;

  select * into v_rank from public.ranks where id=p_id for update;
  if v_rank.id is null then raise exception '계급을 찾을 수 없습니다.'; end if;

  select * into v_other
  from public.ranks
  where rank_order = v_rank.rank_order + p_direction
  for update;

  if v_other.id is null then return v_rank; end if;

  v_order := v_rank.rank_order;
  v_other_order := v_other.rank_order;
  update public.ranks set rank_order = 0 where id=v_rank.id;
  update public.ranks set rank_order = v_order where id=v_other.id;
  update public.ranks set rank_order = v_other_order where id=v_rank.id;

  select * into v_rank from public.ranks where id=p_id;
  return v_rank;
end;
$function$;

grant execute on function public.admin_move_rank(uuid, integer) to authenticated;
