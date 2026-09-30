-- 채팅 첨부파일 기능용 Supabase 마이그레이션
-- 기존 채팅/DM 데이터는 그대로 유지하고 attachments 컬럼과 전용 Storage 버킷만 추가합니다.

alter table public.chat_messages
  add column if not exists attachments jsonb not null default '[]'::jsonb;

alter table public.direct_messages
  add column if not exists attachments jsonb not null default '[]'::jsonb;

insert into storage.buckets (id, name, public, file_size_limit)
values ('chat-files', 'chat-files', false, 52428800)
on conflict (id) do update
set public = false,
    file_size_limit = 52428800;

drop policy if exists "Chat files authenticated upload" on storage.objects;
create policy "Chat files authenticated upload"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'chat-files'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Chat files authenticated read" on storage.objects;
create policy "Chat files authenticated read"
on storage.objects
for select
to authenticated
using (bucket_id = 'chat-files');

drop policy if exists "Chat files owner delete" on storage.objects;
create policy "Chat files owner delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'chat-files'
  and (storage.foldername(name))[1] = auth.uid()::text
);
