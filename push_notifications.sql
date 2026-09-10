-- 웹 푸시 구독 저장 테이블
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.push_subscriptions enable row level security;

drop policy if exists "push_subscriptions_select_own" on public.push_subscriptions;
drop policy if exists "push_subscriptions_insert_own" on public.push_subscriptions;
drop policy if exists "push_subscriptions_delete_own" on public.push_subscriptions;

create policy "push_subscriptions_select_own"
on public.push_subscriptions for select
to authenticated using (auth.uid() = user_id);

create policy "push_subscriptions_insert_own"
on public.push_subscriptions for insert
to authenticated with check (auth.uid() = user_id);

create policy "push_subscriptions_delete_own"
on public.push_subscriptions for delete
to authenticated using (auth.uid() = user_id);

create index if not exists push_subscriptions_user_id_idx on public.push_subscriptions(user_id);
