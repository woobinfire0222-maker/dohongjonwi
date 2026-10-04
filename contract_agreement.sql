-- 돼홍존위 필수 회원 계약서 동의 기록
create table if not exists public.membership_contract_agreements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  contract_version text not null default '2026-10-04',
  accepted_at timestamptz not null default now()
);

alter table public.membership_contract_agreements enable row level security;

drop policy if exists "members can read own contract agreement" on public.membership_contract_agreements;
create policy "members can read own contract agreement"
  on public.membership_contract_agreements for select
  using (auth.uid() = user_id);

drop policy if exists "members can create own contract agreement" on public.membership_contract_agreements;
create policy "members can create own contract agreement"
  on public.membership_contract_agreements for insert
  with check (auth.uid() = user_id);

drop policy if exists "members can update own contract agreement" on public.membership_contract_agreements;
create policy "members can update own contract agreement"
  on public.membership_contract_agreements for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists membership_contract_agreements_accepted_at_idx
  on public.membership_contract_agreements(accepted_at desc);
