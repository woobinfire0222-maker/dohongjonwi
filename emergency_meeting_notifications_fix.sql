-- 긴급회의 참여 + 전체 알림 안정화 마이그레이션
-- 기존 테이블/인증/프로필 구조는 유지합니다.

create table if not exists public.emergency_meeting_participants (
  id uuid primary key default gen_random_uuid(),
  meeting_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  unique (meeting_id, user_id)
);

alter table public.emergency_meeting_participants enable row level security;

drop policy if exists "meeting_participants_select_auth" on public.emergency_meeting_participants;
drop policy if exists "meeting_participants_insert_own" on public.emergency_meeting_participants;
create policy "meeting_participants_select_auth"
on public.emergency_meeting_participants for select
to authenticated using (true);
create policy "meeting_participants_insert_own"
on public.emergency_meeting_participants for insert
to authenticated with check (auth.uid() = user_id);

create index if not exists emergency_meeting_participants_meeting_idx
on public.emergency_meeting_participants(meeting_id);
create index if not exists emergency_meeting_participants_user_idx
on public.emergency_meeting_participants(user_id);

create or replace function public.join_emergency_meeting(p_meeting_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_exists boolean;
  v_status text;
  v_count bigint;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;
  if p_meeting_id is null or btrim(p_meeting_id) = '' then raise exception '회의 정보가 올바르지 않습니다.'; end if;

  select true, status::text into v_exists, v_status
  from public.emergency_meetings
  where id::text = p_meeting_id
  limit 1;

  if not coalesce(v_exists,false) then raise exception '존재하지 않는 긴급회의입니다.'; end if;
  if v_status not in ('active','live','scheduled') then raise exception '현재 참여할 수 없는 회의입니다.'; end if;

  insert into public.emergency_meeting_participants(meeting_id,user_id)
  values (p_meeting_id,v_uid)
  on conflict (meeting_id,user_id) do nothing;

  select count(*) into v_count from public.emergency_meeting_participants where emergency_meeting_participants.meeting_id = p_meeting_id;

  return jsonb_build_object('meeting_id',p_meeting_id,'joined',true,'participant_count',v_count);
end;
$$;

grant execute on function public.join_emergency_meeting(text) to authenticated;

create or replace function public.send_global_notification(notification_title text, notification_content text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;
  if not public.is_admin() then raise exception '관리자만 전체 알림을 보낼 수 있습니다.'; end if;
  if coalesce(btrim(notification_title),'') = '' then raise exception '알림 제목을 입력해 주세요.'; end if;
  if coalesce(btrim(notification_content),'') = '' then raise exception '알림 내용을 입력해 주세요.'; end if;

  insert into public.notifications(user_id,title,content,type)
  select p.id,btrim(notification_title),btrim(notification_content),'announcement'
  from public.profiles p
  where coalesce(p.status,'active') = 'active';

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.send_global_notification(text,text) to authenticated;

-- Realtime 중복 추가를 피합니다.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'emergency_meetings'
  ) then
    alter publication supabase_realtime add table public.emergency_meetings;
  end if;
end $$;
