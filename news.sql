-- 돼홍존위 뉴스룸
create table if not exists public.news_articles (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  summary text not null default '',
  content text not null default '',
  category text not null default '일반',
  emoji text not null default '📰',
  published boolean not null default true,
  published_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists news_articles_published_idx
  on public.news_articles (published, published_at desc);

alter table public.news_articles enable row level security;

drop policy if exists news_public_read on public.news_articles;
drop policy if exists news_admin_insert on public.news_articles;
drop policy if exists news_admin_update on public.news_articles;
drop policy if exists news_admin_delete on public.news_articles;

create policy news_public_read
on public.news_articles
for select to authenticated
using (published = true or public.is_admin());

create policy news_admin_insert
on public.news_articles
for insert to authenticated
with check (public.is_admin() and created_by = auth.uid());

create policy news_admin_update
on public.news_articles
for update to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy news_admin_delete
on public.news_articles
for delete to authenticated
using (public.is_admin());

create or replace function public.news_articles_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_news_articles_updated_at on public.news_articles;
create trigger trg_news_articles_updated_at
before update on public.news_articles
for each row execute function public.news_articles_set_updated_at();
