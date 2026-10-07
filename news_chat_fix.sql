-- 돼홍존위 뉴스 + 채팅 이름/DM 상대 조회 보강
-- Supabase SQL Editor에서 1회 실행하세요.

create table if not exists public.news (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) > 0),
  content text not null check (length(trim(content)) > 0),
  image_url text,
  author_id uuid not null references public.profiles(id) on delete restrict,
  author_name text not null,
  is_published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists news_created_at_idx on public.news(created_at desc);
create index if not exists news_published_created_at_idx on public.news(is_published, created_at desc);

alter table public.news enable row level security;

drop policy if exists "Authenticated can read published news" on public.news;
create policy "Authenticated can read published news"
on public.news
for select to authenticated
using (is_published = true or public.is_admin());

drop policy if exists "Admins can insert news" on public.news;
create policy "Admins can insert news"
on public.news
for insert to authenticated
with check (public.is_admin() and author_id = auth.uid());

drop policy if exists "Admins can update news" on public.news;
create policy "Admins can update news"
on public.news
for update to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "Admins can delete news" on public.news;
create policy "Admins can delete news"
on public.news
for delete to authenticated
using (public.is_admin());

-- 회원용 채팅 작성자 이름 조회.
-- profiles RLS 때문에 일반 회원에게 이름이 비어 나오는 경우를 피하기 위해
-- 현재 로그인한 회원이 접근할 수 있는 채팅 데이터의 작성자 이름만 반환합니다.
create or replace function public.get_chat_messages_with_names(p_room_id uuid)
returns setof jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', cm.id,
    'room_id', cm.room_id,
    'sender_id', cm.sender_id,
    'content', cm.content,
    'created_at', cm.created_at,
    'edited_at', cm.edited_at,
    'deleted_at', cm.deleted_at,
    'reply_to_id', cm.reply_to_id,
    'sender_name', coalesce(p.display_name, '회원')
  )
  from public.chat_messages cm
  left join public.profiles p on p.id = cm.sender_id
  where cm.room_id = p_room_id
  order by cm.created_at asc
$$;

create or replace function public.get_dm_messages_with_names(p_other_user_id uuid)
returns setof jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', dm.id,
    'sender_id', dm.sender_id,
    'recipient_id', dm.recipient_id,
    'content', dm.content,
    'created_at', dm.created_at,
    'edited_at', dm.edited_at,
    'deleted_at', dm.deleted_at,
    'reply_to_id', dm.reply_to_id,
    'sender_name', coalesce(p.display_name, '회원')
  )
  from public.direct_messages dm
  left join public.profiles p on p.id = dm.sender_id
  where auth.uid() is not null
    and (dm.sender_id = auth.uid() or dm.recipient_id = auth.uid())
    and (dm.sender_id = p_other_user_id or dm.recipient_id = p_other_user_id)
  order by dm.created_at asc
$$;

-- DM 상대 목록 자체에서 현재 로그인한 사용자를 제외.
create or replace function public.get_dm_partners()
returns setof jsonb
language sql
security definer
set search_path = public
as $$
  with partner_ids as (
    select distinct
      case when dm.sender_id = auth.uid() then dm.recipient_id else dm.sender_id end as partner_id
    from public.direct_messages dm
    where auth.uid() is not null
      and (dm.sender_id = auth.uid() or dm.recipient_id = auth.uid())
      and dm.sender_id <> dm.recipient_id
  )
  select jsonb_build_object(
    'id', p.id,
    'display_name', p.display_name,
    'department', p.department,
    'role', p.role,
    'status', p.status,
    'rank_id', p.rank_id
  )
  from partner_ids x
  join public.profiles p on p.id = x.partner_id
  where p.id <> auth.uid()
  order by p.display_name asc
$$;

-- 채팅 상대 선택용 회원 목록도 DB 단계에서 자기 자신을 제외.
create or replace function public.get_chat_members()
returns setof jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', p.id,
    'display_name', p.display_name,
    'department', p.department,
    'role', p.role,
    'status', p.status,
    'rank_id', p.rank_id
  )
  from public.profiles p
  where auth.uid() is not null
    and p.id <> auth.uid()
  order by p.display_name asc
$$;

revoke all on function public.get_chat_messages_with_names(uuid) from public;
grant execute on function public.get_chat_messages_with_names(uuid) to authenticated;
revoke all on function public.get_dm_messages_with_names(uuid) from public;
grant execute on function public.get_dm_messages_with_names(uuid) to authenticated;
revoke all on function public.get_dm_partners() from public;
grant execute on function public.get_dm_partners() to authenticated;
revoke all on function public.get_chat_members() from public;
grant execute on function public.get_chat_members() to authenticated;

-- 기존 자기 자신 DM 데이터가 남아 있더라도 목록에서 절대 노출되지 않도록
-- 조회 함수에서 sender_id <> recipient_id를 강제한다.
-- 새 자기 자신 DM은 direct_messages_not_self CHECK 제약으로 차단된다.
