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
for select
to authenticated
using (auth.uid() = user_id);

create or replace function public.play_entertainment_game(bet_amount bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_balance bigint;
  v_symbols text[];
  v_win boolean;
  v_payout bigint := 0;
  v_new_balance bigint;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if bet_amount is null or bet_amount <= 0 then
    raise exception '사용할 코인은 1개 이상이어야 합니다.';
  end if;

  select coin_balance::bigint
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

  v_symbols := array[
    (floor(random() * 7) + 1)::int::text,
    (floor(random() * 7) + 1)::int::text,
    (floor(random() * 7) + 1)::int::text
  ];

  v_win := v_symbols[1] = v_symbols[2] and v_symbols[2] = v_symbols[3];
  if v_win then
    v_payout := bet_amount * 2;
  end if;

  v_new_balance := v_balance - bet_amount + v_payout;

  update public.profiles
  set coin_balance = v_new_balance,
      updated_at = now()
  where id = v_user;

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

grant execute on function public.play_entertainment_game(bigint) to authenticated;


-- 미니게임 코인 선차감/후정산 로직
alter table public.entertainment_game_history
  add column if not exists settled boolean not null default true;

-- 기존 기록은 이미 정산된 것으로 간주하고, 신규 라운드만 false로 생성합니다.
create or replace function public.begin_entertainment_game(bet_amount bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_balance bigint;
  v_new_balance bigint;
  v_game_id uuid;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if bet_amount is null or bet_amount <= 0 then
    raise exception '사용할 코인은 1개 이상이어야 합니다.';
  end if;

  select coin_balance::bigint
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

  v_new_balance := v_balance - bet_amount;

  update public.profiles
  set coin_balance = v_new_balance,
      updated_at = now()
  where id = v_user;

  insert into public.entertainment_game_history
    (user_id, bet_amount, symbols, won, payout, balance_after, settled)
  values
    (v_user, bet_amount, array[]::text[], false, 0, v_new_balance, false)
  returning id into v_game_id;

  return jsonb_build_object(
    'game_id', v_game_id,
    'bet', bet_amount,
    'new_balance', v_new_balance
  );
end;
$$;

grant execute on function public.begin_entertainment_game(bigint) to authenticated;

create or replace function public.finish_entertainment_game(game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_bet bigint;
  v_balance bigint;
  v_symbols text[];
  v_win boolean;
  v_payout bigint := 0;
  v_new_balance bigint;
  v_settled boolean;
  v_won boolean;
  v_existing_payout bigint;
  v_existing_symbols text[];
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select bet_amount, settled, won, payout, symbols
    into v_bet, v_settled, v_won, v_existing_payout, v_existing_symbols
  from public.entertainment_game_history
  where id = game_id
    and user_id = v_user
  for update;

  if not found then
    raise exception '게임 라운드를 찾을 수 없습니다.';
  end if;

  if v_settled then
    select coin_balance::bigint
      into v_balance
    from public.profiles
    where id = v_user;

    return jsonb_build_object(
      'game_id', game_id,
      'symbols', v_existing_symbols,
      'win', v_won,
      'bet', v_bet,
      'payout', v_existing_payout,
      'new_balance', v_balance
    );
  end if;

  v_symbols := array[
    (floor(random() * 7) + 1)::int::text,
    (floor(random() * 7) + 1)::int::text,
    (floor(random() * 7) + 1)::int::text
  ];

  v_win := v_symbols[1] = v_symbols[2] and v_symbols[2] = v_symbols[3];
  if v_win then
    v_payout := v_bet * 2;
  end if;

  select coin_balance::bigint
    into v_balance
  from public.profiles
  where id = v_user
  for update;

  if not found then
    raise exception '회원 프로필을 찾을 수 없습니다.';
  end if;

  v_new_balance := v_balance + v_payout;

  update public.profiles
  set coin_balance = v_new_balance,
      updated_at = now()
  where id = v_user;

  update public.entertainment_game_history
  set symbols = v_symbols,
      won = v_win,
      payout = v_payout,
      balance_after = v_new_balance,
      settled = true
  where id = game_id
    and user_id = v_user;

  return jsonb_build_object(
    'game_id', game_id,
    'symbols', v_symbols,
    'win', v_win,
    'bet', v_bet,
    'payout', v_payout,
    'new_balance', v_new_balance
  );
end;
$$;

grant execute on function public.finish_entertainment_game(uuid) to authenticated;
