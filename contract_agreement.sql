-- 돼홍존위 필수 회원 계약서 동의 기록
create table if not exists public.membership_contract_agreements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  contract_version text not null default '2026-10-04',
  accepted_at timestamptz not null default now()
);

alter table public.membership_contract_agreements enable row level security;

-- 이전에 생성된 정책 이름이 무엇이든 모두 제거하여
-- INSERT에서 잘못된 USING 정책이 남아있는 문제를 방지합니다.
do $$
declare
  p record;
begin
  for p in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'membership_contract_agreements'
  loop
    execute format('drop policy if exists %I on public.membership_contract_agreements', p.policyname);
  end loop;
end $$;

create policy "membership_contract_select_own"
on public.membership_contract_agreements
for select
to authenticated
using (auth.uid() = user_id);

create policy "membership_contract_insert_own"
on public.membership_contract_agreements
for insert
to authenticated
with check (auth.uid() = user_id);

create index if not exists membership_contract_agreements_accepted_at_idx
on public.membership_contract_agreements(accepted_at desc);
