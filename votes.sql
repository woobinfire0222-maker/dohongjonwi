-- 돼홍존위: 투표 시스템
-- Supabase SQL Editor에서 기존 ranks_promotion.sql 실행 후 이 파일을 1회 실행하세요.

create table if not exists public.polls (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  poll_type text not null check (poll_type in ('choice','yes_no')),
  ends_at timestamptz,
  is_closed boolean not null default false,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.poll_options (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls(id) on delete cascade,
  label text not null,
  option_order integer not null default 1,
  created_at timestamptz not null default now(),
  unique(poll_id, option_order)
);

create table if not exists public.poll_votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls(id) on delete cascade,
  option_id uuid not null references public.poll_options(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(poll_id, user_id)
);

create index if not exists polls_created_at_idx on public.polls(created_at desc);
create index if not exists polls_ends_at_idx on public.polls(ends_at);
create index if not exists poll_options_poll_id_idx on public.poll_options(poll_id, option_order);
create index if not exists poll_votes_poll_id_idx on public.poll_votes(poll_id);
create index if not exists poll_votes_user_id_idx on public.poll_votes(user_id);

alter table public.polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;

drop policy if exists "Authenticated can read polls" on public.polls;
create policy "Authenticated can read polls"
on public.polls for select to authenticated using (true);
drop policy if exists "Admins can insert polls" on public.polls;
create policy "Admins can insert polls" on public.polls for insert to authenticated with check (public.is_admin());
drop policy if exists "Admins can update polls" on public.polls;
create policy "Admins can update polls" on public.polls for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "Admins can delete polls" on public.polls;
create policy "Admins can delete polls" on public.polls for delete to authenticated using (public.is_admin());

drop policy if exists "Authenticated can read poll options" on public.poll_options;
create policy "Authenticated can read poll options"
on public.poll_options for select to authenticated using (true);
drop policy if exists "Admins can insert poll options" on public.poll_options;
create policy "Admins can insert poll options" on public.poll_options for insert to authenticated with check (public.is_admin());
drop policy if exists "Admins can update poll options" on public.poll_options;
create policy "Admins can update poll options" on public.poll_options for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "Admins can delete poll options" on public.poll_options;
create policy "Admins can delete poll options" on public.poll_options for delete to authenticated using (public.is_admin());

drop policy if exists "Members can read own poll votes" on public.poll_votes;
create policy "Members can read own poll votes"
on public.poll_votes for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists "Members cannot directly insert poll votes" on public.poll_votes;
-- 투표 입력은 아래 SECURITY DEFINER RPC만 사용합니다.

create or replace function public.admin_create_poll(
  p_title text,
  p_description text,
  p_poll_type text,
  p_ends_at timestamptz default null,
  p_options jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_poll_id uuid;
  v_item text;
  v_index integer := 0;
  v_clean text[] := array[]::text[];
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if nullif(trim(p_title),'') is null then raise exception '투표 제목을 입력해 주세요.'; end if;
  if p_poll_type not in ('choice','yes_no') then raise exception '투표 방식이 올바르지 않습니다.'; end if;

  if p_poll_type='choice' then
    for v_item in select value from jsonb_array_elements_text(coalesce(p_options,'[]'::jsonb)) loop
      if nullif(trim(v_item),'') is not null then
        v_clean := array_append(v_clean,trim(v_item));
      end if;
    end loop;
    if array_length(v_clean,1) is null or array_length(v_clean,1)<2 then
      raise exception '선택지는 2개 이상 필요합니다.';
    end if;
  else
    v_clean := array['찬성','반대'];
  end if;

  insert into public.polls(title,description,poll_type,ends_at,created_by)
  values(trim(p_title),coalesce(trim(p_description),''),p_poll_type,p_ends_at,v_uid)
  returning id into v_poll_id;

  for v_index in 1..array_length(v_clean,1) loop
    insert into public.poll_options(poll_id,label,option_order)
    values(v_poll_id,v_clean[v_index],v_index);
  end loop;

  return jsonb_build_object('id',v_poll_id,'title',p_title);
end;
$function$;
grant execute on function public.admin_create_poll(text,text,text,timestamptz,jsonb) to authenticated;

create or replace function public.admin_close_poll(p_poll_id uuid)
returns public.polls
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_poll public.polls;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  update public.polls set is_closed=true,updated_at=now() where id=p_poll_id returning * into v_poll;
  if v_poll.id is null then raise exception '투표를 찾을 수 없습니다.'; end if;
  return v_poll;
end;
$function$;
grant execute on function public.admin_close_poll(uuid) to authenticated;

create or replace function public.admin_delete_poll(p_poll_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  delete from public.polls where id=p_poll_id;
end;
$function$;
grant execute on function public.admin_delete_poll(uuid) to authenticated;

create or replace function public.vote_poll(p_poll_id uuid, p_option_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_poll public.polls;
  v_option public.poll_options;
  v_vote public.poll_votes;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;
  select * into v_poll from public.polls where id=p_poll_id for update;
  if v_poll.id is null then raise exception '투표를 찾을 수 없습니다.'; end if;
  if v_poll.is_closed or (v_poll.ends_at is not null and v_poll.ends_at<=now()) then
    raise exception '이미 종료된 투표입니다.';
  end if;
  select * into v_option from public.poll_options where id=p_option_id and poll_id=p_poll_id;
  if v_option.id is null then raise exception '선택지가 올바르지 않습니다.'; end if;
  if exists(select 1 from public.poll_votes where poll_id=p_poll_id and user_id=v_uid) then
    raise exception '이미 이 투표에 참여했습니다.';
  end if;
  insert into public.poll_votes(poll_id,option_id,user_id) values(p_poll_id,p_option_id,v_uid) returning * into v_vote;
  return jsonb_build_object('id',v_vote.id,'poll_id',p_poll_id,'option_id',p_option_id);
exception when unique_violation then
  raise exception '이미 이 투표에 참여했습니다.';
end;
$function$;
grant execute on function public.vote_poll(uuid,uuid) to authenticated;

create or replace function public.get_poll_results(p_poll_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_poll public.polls;
  v_ended boolean;
  v_total integer;
  v_options jsonb;
begin
  select * into v_poll from public.polls where id=p_poll_id;
  if v_poll.id is null then raise exception '투표를 찾을 수 없습니다.'; end if;
  v_ended := v_poll.is_closed or (v_poll.ends_at is not null and v_poll.ends_at<=now());
  if not v_ended then raise exception '투표가 종료된 후 결과를 확인할 수 있습니다.'; end if;

  select count(*)::integer into v_total from public.poll_votes where poll_id=p_poll_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'label',o.label,'votes',o.vote_count) order by o.option_order),'[]'::jsonb)
  into v_options
  from (
    select po.id,po.label,po.option_order,count(pv.id)::integer as vote_count
    from public.poll_options po
    left join public.poll_votes pv on pv.option_id=po.id and pv.poll_id=p_poll_id
    where po.poll_id=p_poll_id
    group by po.id,po.label,po.option_order
  ) o;
  return jsonb_build_object('poll_id',p_poll_id,'total_votes',v_total,'options',v_options);
end;
$function$;
grant execute on function public.get_poll_results(uuid) to authenticated;
