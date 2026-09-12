drop function if exists public.play_entertainment_game(bigint);

create table if not exists public.entertainment_game_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  bet_amount bigint not null check (bet_amount > 0),
  symbols text[] not null,
  won boolean not null,
  payout bigint not null default 0 check (payout >= 0),
  balance_after bigint not null,
  created_at timestamptz not null default now()
);

create index if not exists entertainment_game_history_user_created_idx
  on public.entertainment_game_history(user_id, created_at desc);

alter table public.entertainment_game_history enable row level security;

drop policy if exists "Users can read their own entertainment game history" on public.entertainment_game_history;
create policy "Users can read their own entertainment game history"
on public.entertainment_game_history
for select to authenticated
using (auth.uid() = user_id);

create or replace function public.play_entertainment_game(bet_amount bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_user uuid := auth.uid();
  v_balance bigint;
  v_symbols text[];
  v_win boolean;
  v_payout bigint := 0;
  v_new_balance bigint;
  v_roll numeric;
  v_pick int;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if bet_amount is null or bet_amount <= 0 then
    raise exception '사용할 코인은 1개 이상이어야 합니다.';
  end if;

  select floor(coalesce(coin_balance::numeric, 0))::bigint
    into v_balance
  from public.profiles
  where id = v_user
  for update;

  if not found then
    raise exception '회원 프로필을 찾을 수 없습니다.';
  end if;

  if v_balance < bet_amount then
    raise exception '보유 코인이 부족합니다.';
  end if;

  v_roll := random();
  v_win := v_roll < 0.20;

  if v_win then
    v_pick := floor(random() * 8)::int + 1;
    v_symbols := array_fill(v_pick::text, ARRAY[3]);
    v_payout := bet_amount * 2;
    v_new_balance := v_balance + v_payout;
  else
    v_symbols := array[
      (floor(random() * 8) + 1)::int::text,
      (floor(random() * 8) + 1)::int::text,
      (floor(random() * 8) + 1)::int::text
    ];
    while v_symbols[1] = v_symbols[2] and v_symbols[2] = v_symbols[3] loop
      v_symbols[3] := (floor(random() * 8) + 1)::int::text;
    end loop;
    v_new_balance := v_balance - bet_amount;
  end if;

  update public.profiles
  set coin_balance = v_new_balance
  where id = v_user;

  if not found then
    raise exception '코인 잔액을 업데이트하지 못했습니다.';
  end if;

  insert into public.entertainment_game_history
    (user_id, bet_amount, symbols, won, payout, balance_after)
  values
    (v_user, bet_amount, v_symbols, v_win, v_payout, v_new_balance);

  return jsonb_build_object(
    'symbols', v_symbols,
    'win', v_win,
    'bet', bet_amount,
    'payout', v_payout,
    'new_balance', v_new_balance
  );
end;
$$;

revoke all on function public.play_entertainment_game(bigint) from public;
revoke all on function public.play_entertainment_game(bigint) from anon;
grant execute on function public.play_entertainment_game(bigint) to authenticated;
