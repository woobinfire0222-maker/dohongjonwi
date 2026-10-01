-- 돼홍존위: 30계급 + 고위계급 진급심사 + 부서 지원 시스템
-- Supabase SQL Editor에서 이 파일 전체를 1회 실행하세요.

create extension if not exists pgcrypto;

/* =========================================================
   1) 계급
   ========================================================= */
create table if not exists public.ranks (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  rank_order integer not null unique,
  promotion_cost bigint not null default 0 check (promotion_cost >= 0),
  is_high_rank boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.ranks
  add column if not exists is_high_rank boolean not null default false;

alter table public.profiles
  add column if not exists rank_id uuid references public.ranks(id) on delete set null;

create index if not exists profiles_rank_id_idx on public.profiles(rank_id);
create index if not exists ranks_rank_order_idx on public.ranks(rank_order);

-- 기존 설치에서 기본 1개 계급만 있는 경우 30개 기본 계급으로 확장합니다.
do $$
declare
  v_count integer;
  v_names text[] := array[
    '임시멤버','훈련인원','실습인원','배정인원','일반인원','선임인원','숙련인원','우수인원',
    '정예인원','특공인원','특수인원','전문인원','핵심인원','선도대원','정예대원','특공대원',
    '특수대원','지휘대원','책임대원','감독관','관리관','상급관리관','지휘관','상급지휘관',
    '총괄관','중앙지휘관','총괄지휘관','최고지휘관','총사령관','최고사령관'
  ];
  v_costs bigint[] := array[
    0,100,200,300,500,700,900,1200,1500,1800,2200,2600,3000,3500,4000,
    5000,6000,7000,8500,10000,12000,15000,18000,22000,26000,30000,35000,
    40000,50000,60000
  ];
  i integer;
  v_rank_id uuid;
begin
  select count(*) into v_count from public.ranks;

  if v_count <= 1 then
    -- 기존 '일반 회원'이 있으면 첫 계급 이름만 바꿉니다.
    update public.ranks
      set name='임시멤버', promotion_cost=0, updated_at=now()
    where rank_order=1
      and not exists (select 1 from public.ranks where name='임시멤버');

    for i in 1..30 loop
      select id into v_rank_id from public.ranks where rank_order=i;
      if v_rank_id is null then
        insert into public.ranks(name,rank_order,promotion_cost,is_high_rank)
        values(v_names[i],i,v_costs[i],false);
      else
        update public.ranks
          set name=v_names[i], promotion_cost=v_costs[i], updated_at=now()
        where id=v_rank_id;
      end if;
    end loop;
  end if;
end $$;

-- 기존 회원에게 1번 계급을 부여합니다.
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
on public.ranks for insert to authenticated with check (public.is_admin());
drop policy if exists "Admins can update ranks" on public.ranks;
create policy "Admins can update ranks"
on public.ranks for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "Admins can delete ranks" on public.ranks;
create policy "Admins can delete ranks"
on public.ranks for delete to authenticated using (public.is_admin());

/* =========================================================
   2) 부서
   ========================================================= */
create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null default '',
  application_cost bigint not null default 0 check (application_cost >= 0),
  is_open boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists service_department_id uuid references public.departments(id) on delete set null;

create index if not exists profiles_service_department_idx on public.profiles(service_department_id);

insert into public.departments(name,description,application_cost,is_open)
values
  ('통신부','통신, 전달, 상황 공유와 관련된 업무를 담당합니다.',0,true),
  ('교육사령부','신규 인원 교육과 실습 진행을 담당합니다.',0,true),
  ('탐색부','정보 탐색과 현황 확인 업무를 담당합니다.',0,true)
on conflict (name) do nothing;

alter table public.departments enable row level security;
drop policy if exists "Authenticated can read departments" on public.departments;
create policy "Authenticated can read departments"
on public.departments for select to authenticated using (true);
drop policy if exists "Admins can insert departments" on public.departments;
create policy "Admins can insert departments"
on public.departments for insert to authenticated with check (public.is_admin());
drop policy if exists "Admins can update departments" on public.departments;
create policy "Admins can update departments"
on public.departments for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "Admins can delete departments" on public.departments;
create policy "Admins can delete departments"
on public.departments for delete to authenticated using (public.is_admin());

/* =========================================================
   3) 고위계급 진급 요청
   - 관리자가 고위직으로 설정한 계급으로 진급할 때 필요
   - 신청 즉시 코인 차감
   - 반려 시 자동 환급
   ========================================================= */
create table if not exists public.rank_promotion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  from_rank_id uuid not null references public.ranks(id),
  to_rank_id uuid not null references public.ranks(id),
  cost bigint not null check (cost >= 0),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists rank_promotion_pending_user_idx
on public.rank_promotion_requests(user_id)
where status='pending';

alter table public.rank_promotion_requests enable row level security;
drop policy if exists "Members can read own rank requests" on public.rank_promotion_requests;
create policy "Members can read own rank requests"
on public.rank_promotion_requests for select to authenticated
using (user_id=auth.uid() or public.is_admin());
drop policy if exists "Admins can update rank requests" on public.rank_promotion_requests;
create policy "Admins can update rank requests"
on public.rank_promotion_requests for update to authenticated
using (public.is_admin()) with check (public.is_admin());

create or replace function public.submit_rank_promotion_request()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_current_id uuid;
  v_current_order integer;
  v_next_id uuid;
  v_next_name text;
  v_next_high boolean;
  v_cost bigint;
  v_balance bigint;
  v_request_id uuid;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;

  -- profiles 행만 잠근 뒤 rank 정보를 별도로 읽습니다.
  -- LEFT JOIN 결과에 FOR UPDATE를 걸면 PostgreSQL에서 nullable 측 때문에 오류가 날 수 있습니다.
  select p.rank_id, p.coin_balance
    into v_current_id, v_balance
  from public.profiles p
  where p.id=v_uid
  for update;

  if v_balance is null then raise exception '회원 정보를 찾을 수 없습니다.'; end if;

  select coalesce(r.rank_order,0)
    into v_current_order
  from public.ranks r
  where r.id=v_current_id;
  v_current_order := coalesce(v_current_order,0);
  if exists(select 1 from public.rank_promotion_requests where user_id=v_uid and status='pending') then
    raise exception '이미 심사 중인 진급 요청이 있습니다.';
  end if;

  -- 숫자가 작을수록 높은 계급이므로, 현재보다 번호가 작은 계급 중 가장 가까운 계급을 다음 계급으로 사용합니다.
  select id,name,is_high_rank,promotion_cost
    into v_next_id,v_next_name,v_next_high,v_cost
  from public.ranks
  where rank_order < v_current_order
  order by rank_order desc
  limit 1;

  if v_next_id is null then raise exception '더 이상 진급할 계급이 없습니다.'; end if;
  if not v_next_high then raise exception '다음 계급은 고위직으로 설정되어 있지 않아 즉시 진급할 수 있습니다.'; end if;
  if v_balance < v_cost then raise exception '코인이 부족합니다. 필요한 코인: %',v_cost; end if;

  v_balance := v_balance-v_cost;
  update public.profiles set coin_balance=v_balance,updated_at=now() where id=v_uid;

  insert into public.rank_promotion_requests(user_id,from_rank_id,to_rank_id,cost)
  values(v_uid,v_current_id,v_next_id,v_cost)
  returning id into v_request_id;

  return jsonb_build_object(
    'request_id',v_request_id,
    'from_rank_id',v_current_id,
    'to_rank_id',v_next_id,
    'rank_name',v_next_name,
    'cost',v_cost,
    'new_balance',v_balance,
    'status','pending'
  );
end;
$function$;

grant execute on function public.submit_rank_promotion_request() to authenticated;

create or replace function public.review_rank_promotion_request(
  p_request_id uuid,
  p_status text,
  p_admin_note text default null
)
returns public.rank_promotion_requests
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_request public.rank_promotion_requests;
  v_rank_id uuid;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if p_status not in ('approved','rejected') then raise exception '처리 상태가 올바르지 않습니다.'; end if;

  select * into v_request
  from public.rank_promotion_requests
  where id=p_request_id
  for update;

  if v_request.id is null then raise exception '진급 요청을 찾을 수 없습니다.'; end if;
  if v_request.status <> 'pending' then raise exception '이미 처리된 진급 요청입니다.'; end if;

  if p_status='approved' then
    select rank_id into v_rank_id from public.profiles where id=v_request.user_id for update;
    if v_rank_id is distinct from v_request.from_rank_id then
      raise exception '신청 당시 계급과 현재 계급이 달라 승인할 수 없습니다.';
    end if;

    update public.profiles
    set rank_id=v_request.to_rank_id, updated_at=now()
    where id=v_request.user_id;
  else
    update public.profiles
    set coin_balance=coin_balance+v_request.cost, updated_at=now()
    where id=v_request.user_id;
  end if;

  update public.rank_promotion_requests
  set status=p_status,admin_note=nullif(trim(coalesce(p_admin_note,'')),''),reviewed_by=auth.uid(),reviewed_at=now()
  where id=p_request_id
  returning * into v_request;

  return v_request;
end;
$function$;

grant execute on function public.review_rank_promotion_request(uuid,text,text) to authenticated;

/* =========================================================
   4) 부서 지원
   - 신청 시 지원비 차감
   - 반려 시 자동 환급
   - 한 사람은 승인된 부서 1개를 가집니다.
   ========================================================= */
create table if not exists public.department_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  aspiration text not null,
  cost bigint not null check (cost >= 0),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists department_application_pending_idx
on public.department_applications(user_id,department_id)
where status='pending';

alter table public.department_applications enable row level security;
drop policy if exists "Members can read own department applications" on public.department_applications;
create policy "Members can read own department applications"
on public.department_applications for select to authenticated
using (user_id=auth.uid() or public.is_admin());
drop policy if exists "Admins can update department applications" on public.department_applications;
create policy "Admins can update department applications"
on public.department_applications for update to authenticated
using (public.is_admin()) with check (public.is_admin());

create or replace function public.submit_department_application(p_department_id uuid,p_aspiration text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_department public.departments;
  v_balance bigint;
  v_cost bigint;
  v_id uuid;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;
  if length(trim(coalesce(p_aspiration,''))) < 5 then raise exception '포부를 5자 이상 작성해 주세요.'; end if;

  select * into v_department from public.departments where id=p_department_id for update;
  if v_department.id is null then raise exception '부서를 찾을 수 없습니다.'; end if;
  if not v_department.is_open then raise exception '현재 지원할 수 없는 부서입니다.'; end if;
  if exists(select 1 from public.department_applications where user_id=v_uid and department_id=p_department_id and status='pending') then
    raise exception '이미 해당 부서에 지원한 상태입니다.';
  end if;
  if exists(select 1 from public.profiles where id=v_uid and service_department_id is not null) then
    raise exception '이미 소속 부서가 있습니다.';
  end if;

  select coin_balance into v_balance from public.profiles where id=v_uid for update;
  if v_balance is null then raise exception '회원 정보를 찾을 수 없습니다.'; end if;
  v_cost := v_department.application_cost;
  if v_balance < v_cost then raise exception '코인이 부족합니다. 필요한 코인: %',v_cost; end if;

  update public.profiles set coin_balance=coin_balance-v_cost,updated_at=now() where id=v_uid;

  insert into public.department_applications(user_id,department_id,aspiration,cost)
  values(v_uid,p_department_id,trim(p_aspiration),v_cost)
  returning id into v_id;

  return jsonb_build_object('request_id',v_id,'cost',v_cost,'new_balance',v_balance-v_cost,'status','pending');
end;
$function$;

grant execute on function public.submit_department_application(uuid,text) to authenticated;

create or replace function public.review_department_application(
  p_application_id uuid,
  p_status text,
  p_admin_note text default null
)
returns public.department_applications
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_application public.department_applications;
  v_current_department uuid;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if p_status not in ('approved','rejected') then raise exception '처리 상태가 올바르지 않습니다.'; end if;

  select * into v_application
  from public.department_applications
  where id=p_application_id
  for update;

  if v_application.id is null then raise exception '부서 지원서를 찾을 수 없습니다.'; end if;
  if v_application.status <> 'pending' then raise exception '이미 처리된 지원서입니다.'; end if;

  if p_status='approved' then
    select service_department_id into v_current_department from public.profiles where id=v_application.user_id for update;
    if v_current_department is not null then raise exception '이미 다른 부서에 소속되어 있습니다.'; end if;
    perform set_config('dohongjonwi.department_assignment','1',true);
    update public.profiles
    set service_department_id=v_application.department_id, updated_at=now()
    where id=v_application.user_id;
  else
    update public.profiles
    set coin_balance=coin_balance+v_application.cost, updated_at=now()
    where id=v_application.user_id;
  end if;

  update public.department_applications
  set status=p_status,admin_note=nullif(trim(coalesce(p_admin_note,'')),''),reviewed_by=auth.uid(),reviewed_at=now()
  where id=p_application_id
  returning * into v_application;

  return v_application;
end;
$function$;

grant execute on function public.review_department_application(uuid,text,text) to authenticated;

/* =========================================================
   5) 관리자용 계급 RPC
   ========================================================= */
drop function if exists public.admin_create_rank(text,integer,bigint);
create or replace function public.admin_create_rank(p_name text,p_order integer,p_cost bigint,p_high_rank boolean default false)
returns public.ranks
language plpgsql security definer set search_path to 'public'
as $function$
declare v_rank public.ranks;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if trim(p_name)='' then raise exception '계급 이름을 입력해 주세요.'; end if;
  if p_order<1 then raise exception '계급 순서는 1 이상이어야 합니다.'; end if;
  if p_cost<0 then raise exception '진급 코인은 0 이상이어야 합니다.'; end if;
  insert into public.ranks(name,rank_order,promotion_cost,is_high_rank)
  values(trim(p_name),p_order,p_cost,coalesce(p_high_rank,false)) returning * into v_rank;
  return v_rank;
end;
$function$;
grant execute on function public.admin_create_rank(text,integer,bigint,boolean) to authenticated;

drop function if exists public.admin_update_rank(uuid,text,integer,bigint);
create or replace function public.admin_update_rank(p_id uuid,p_name text,p_order integer,p_cost bigint,p_high_rank boolean default false)
returns public.ranks
language plpgsql security definer set search_path to 'public'
as $function$
declare v_rank public.ranks;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if trim(p_name)='' then raise exception '계급 이름을 입력해 주세요.'; end if;
  if p_order<1 then raise exception '계급 순서는 1 이상이어야 합니다.'; end if;
  if p_cost<0 then raise exception '진급 코인은 0 이상이어야 합니다.'; end if;
  update public.ranks
  set name=trim(p_name),rank_order=p_order,promotion_cost=p_cost,is_high_rank=coalesce(p_high_rank,false),updated_at=now()
  where id=p_id
  returning * into v_rank;
  if v_rank.id is null then raise exception '계급을 찾을 수 없습니다.'; end if;
  return v_rank;
end;
$function$;
grant execute on function public.admin_update_rank(uuid,text,integer,bigint,boolean) to authenticated;

create or replace function public.admin_delete_rank(p_id uuid)
returns boolean
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if exists(select 1 from public.profiles where rank_id=p_id) then raise exception '현재 회원이 사용 중인 계급은 삭제할 수 없습니다.'; end if;
  if exists(select 1 from public.rank_promotion_requests where from_rank_id=p_id or to_rank_id=p_id) then raise exception '진급 요청 기록에 사용된 계급은 삭제할 수 없습니다.'; end if;
  delete from public.ranks where id=p_id;
  return found;
end;
$function$;
grant execute on function public.admin_delete_rank(uuid) to authenticated;

create or replace function public.admin_move_rank(p_id uuid,p_direction integer)
returns public.ranks
language plpgsql security definer set search_path to 'public'
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
  select * into v_other from public.ranks where rank_order=v_rank.rank_order+p_direction for update;
  if v_other.id is null then return v_rank; end if;
  v_order:=v_rank.rank_order;
  v_other_order:=v_other.rank_order;
  update public.ranks set rank_order=0 where id=v_rank.id;
  update public.ranks set rank_order=v_order where id=v_other.id;
  update public.ranks set rank_order=v_other_order where id=v_rank.id;
  select * into v_rank from public.ranks where id=p_id;
  return v_rank;
end;
$function$;
grant execute on function public.admin_move_rank(uuid,integer) to authenticated;

/* =========================================================
   6) 관리자 회원 계급 직접 변경
   ========================================================= */
create or replace function public.admin_set_member_rank(p_user_id uuid,p_rank_id uuid)
returns public.profiles
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_profile public.profiles;
  v_rank_exists boolean;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if p_user_id is null or p_rank_id is null then raise exception '회원과 계급을 선택해 주세요.'; end if;

  select exists(select 1 from public.ranks where id=p_rank_id) into v_rank_exists;
  if not v_rank_exists then raise exception '존재하지 않는 계급입니다.'; end if;

  update public.profiles
  set rank_id=p_rank_id, updated_at=now()
  where id=p_user_id
  returning * into v_profile;

  if v_profile.id is null then raise exception '회원을 찾을 수 없습니다.'; end if;
  return v_profile;
end;
$function$;
grant execute on function public.admin_set_member_rank(uuid,uuid) to authenticated;

/* =========================================================
   7) 부서 CRUD RPC
   ========================================================= */
create or replace function public.admin_create_department(p_name text,p_description text,p_cost bigint,p_is_open boolean default true)
returns public.departments
language plpgsql security definer set search_path to 'public'
as $function$
declare v_row public.departments;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if trim(p_name)='' then raise exception '부서 이름을 입력해 주세요.'; end if;
  if p_cost<0 then raise exception '지원 코인은 0 이상이어야 합니다.'; end if;
  insert into public.departments(name,description,application_cost,is_open)
  values(trim(p_name),trim(coalesce(p_description,'')),p_cost,coalesce(p_is_open,true)) returning * into v_row;
  return v_row;
end;
$function$;
grant execute on function public.admin_create_department(text,text,bigint,boolean) to authenticated;

create or replace function public.admin_update_department(p_id uuid,p_name text,p_description text,p_cost bigint,p_is_open boolean)
returns public.departments
language plpgsql security definer set search_path to 'public'
as $function$
declare v_row public.departments;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if trim(p_name)='' then raise exception '부서 이름을 입력해 주세요.'; end if;
  if p_cost<0 then raise exception '지원 코인은 0 이상이어야 합니다.'; end if;
  update public.departments
  set name=trim(p_name),description=trim(coalesce(p_description,'')),application_cost=p_cost,is_open=p_is_open,updated_at=now()
  where id=p_id returning * into v_row;
  if v_row.id is null then raise exception '부서를 찾을 수 없습니다.'; end if;
  return v_row;
end;
$function$;
grant execute on function public.admin_update_department(uuid,text,text,bigint,boolean) to authenticated;

create or replace function public.admin_delete_department(p_id uuid)
returns boolean
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if exists(select 1 from public.profiles where service_department_id=p_id) then raise exception '현재 소속 인원이 있는 부서는 삭제할 수 없습니다.'; end if;
  if exists(select 1 from public.department_applications where department_id=p_id) then raise exception '지원 기록이 있는 부서는 삭제할 수 없습니다.'; end if;
  delete from public.departments where id=p_id;
  return found;
end;
$function$;
grant execute on function public.admin_delete_department(uuid) to authenticated;

/* =========================================================
   8) 기존 프로필 보호 트리거 보강
   ========================================================= */
create or replace function public.prevent_member_privilege_changes()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is not null and not public.is_admin() then
    if new.id<>old.id or new.email<>old.email or new.role<>old.role or new.status<>old.status then
      raise exception '권한이 없는 필드입니다';
    end if;
    if new.rank_id is distinct from old.rank_id
       and current_setting('dohongjonwi.rank_purchase',true)<>'1' then
      raise exception '계급 변경은 진급 요청을 통해서만 가능합니다';
    end if;
    if new.service_department_id is distinct from old.service_department_id
       and current_setting('dohongjonwi.department_assignment',true)<>'1' then
      raise exception '부서 변경은 부서 지원 승인으로만 가능합니다';
    end if;
  end if;
  return new;
end;
$function$;

/* =========================================================
   9) 일반 진급 RPC
   - 다음 계급이 고위직으로 설정되어 있으면 관리자 심사
   - 고위직이 아니면 코인 즉시 진급
   - 숫자가 작을수록 높은 계급
   ========================================================= */
create or replace function public.purchase_next_rank()
returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_current_order integer;
  v_next_id uuid;
  v_next_name text;
  v_next_high boolean;
  v_cost bigint;
  v_balance bigint;
  v_new_balance bigint;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;
  -- profiles 행만 잠급니다. LEFT JOIN + FOR UPDATE 조합을 피합니다.
  select p.coin_balance, p.rank_id into v_balance, v_next_id
  from public.profiles p
  where p.id=v_uid for update;
  if v_balance is null then raise exception '회원 정보를 찾을 수 없습니다.'; end if;

  select coalesce(r.rank_order,0) into v_current_order
  from public.ranks r
  where r.id=v_next_id;
  v_current_order := coalesce(v_current_order,0);

  -- 숫자가 작을수록 높은 계급. 현재보다 번호가 1 낮아지는 가장 가까운 계급을 찾습니다.
  select id,name,is_high_rank,promotion_cost into v_next_id,v_next_name,v_next_high,v_cost
  from public.ranks
  where rank_order < v_current_order
  order by rank_order desc
  limit 1;

  if v_next_id is null then raise exception '더 이상 진급할 계급이 없습니다.'; end if;
  if v_next_high then raise exception '다음 계급은 고위직으로 설정되어 있어 관리자 진급 요청이 필요합니다.'; end if;
  if v_balance<v_cost then raise exception '코인이 부족합니다. 필요한 코인: %',v_cost; end if;
  perform set_config('dohongjonwi.rank_purchase','1',true);
  v_new_balance:=v_balance-v_cost;
  update public.profiles set rank_id=v_next_id,coin_balance=v_new_balance,updated_at=now() where id=v_uid;
  return jsonb_build_object('rank_id',v_next_id,'rank_name',v_next_name,'cost',v_cost,'new_balance',v_new_balance,'status','approved');
end;
$function$;
grant execute on function public.purchase_next_rank() to authenticated;

