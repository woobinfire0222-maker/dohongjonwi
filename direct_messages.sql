-- DM 기능 수정용 Supabase SQL
-- direct_messages 테이블/RLS/Realtime 설정

create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now(),
  constraint direct_messages_not_self check (sender_id <> recipient_id),
  constraint direct_messages_content_not_empty check (length(trim(content)) > 0)
);

create index if not exists direct_messages_sender_recipient_created_idx
  on public.direct_messages(sender_id, recipient_id, created_at);

create index if not exists direct_messages_recipient_sender_created_idx
  on public.direct_messages(recipient_id, sender_id, created_at);

alter table public.direct_messages enable row level security;

drop policy if exists "Users can read their own DMs" on public.direct_messages;
create policy "Users can read their own DMs"
on public.direct_messages
for select
to authenticated
using (auth.uid() = sender_id or auth.uid() = recipient_id);

drop policy if exists "Users can send DMs" on public.direct_messages;
create policy "Users can send DMs"
on public.direct_messages
for insert
to authenticated
with check (auth.uid() = sender_id);

drop policy if exists "Users can delete their own DMs" on public.direct_messages;
create policy "Users can delete their own DMs"
on public.direct_messages
for delete
to authenticated
using (auth.uid() = sender_id);

-- 실시간 DM을 사용하려면 한 번만 실행하세요.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'direct_messages'
  ) then
    alter publication supabase_realtime add table public.direct_messages;
  end if;
end $$;
