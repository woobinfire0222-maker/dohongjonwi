-- =========================================================
-- 초보자 룰렛 + 다트 게임 추가
-- 기존 play_wheel_game(행운의 돌림판)은 원래 30% 룰렛으로 유지
-- =========================================================

CREATE TABLE IF NOT EXISTS public.coin_game_action_counts (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  game_key text NOT NULL,
  action_count bigint NOT NULL DEFAULT 0 CHECK (action_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, game_key)
);

ALTER TABLE public.coin_game_action_counts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "coin_game_action_counts_select_own"
ON public.coin_game_action_counts;

CREATE POLICY "coin_game_action_counts_select_own"
ON public.coin_game_action_counts
FOR SELECT TO authenticated
USING (auth.uid() = user_id);

-- 초보자 룰렛
-- 화면 표기는 50:50이지만 실제 서버 규칙은
-- 1~3회 성공, 4회부터 실패를 강제한다.
CREATE OR REPLACE FUNCTION public.play_beginner_roulette_game(bet_amount bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_balance bigint;
  v_action_count bigint;
  v_won boolean;
  v_payout bigint := 0;
  v_new_balance bigint;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;
  if bet_amount is null or bet_amount <= 0 then
    raise exception '배팅 금액이 올바르지 않습니다.';
  end if;

  select coin_balance into v_balance
  from public.profiles
  where id = v_uid
  for update;

  if v_balance is null then raise exception '회원 정보를 찾을 수 없습니다.'; end if;
  if v_balance < bet_amount then raise exception '코인이 부족합니다.'; end if;

  insert into public.coin_game_action_counts(user_id, game_key, action_count, updated_at)
  values (v_uid, 'beginner_roulette', 1, now())
  on conflict (user_id, game_key)
  do update set
    action_count = public.coin_game_action_counts.action_count + 1,
    updated_at = now()
  returning action_count into v_action_count;

  v_won := v_action_count between 1 and 3;

  if v_won then
    v_payout := bet_amount * 2;
  end if;

  v_new_balance := v_balance - bet_amount + v_payout;

  update public.profiles
  set coin_balance = v_new_balance
  where id = v_uid;

  return jsonb_build_object(
    'bet', bet_amount,
    'won', v_won,
    'success', v_won,
    'actionCount', v_action_count,
    'displayOdds', '50:50',
    'payout', v_payout,
    'new_balance', v_new_balance
  );
end;
$function$;

grant execute on function public.play_beginner_roulette_game(bigint) to authenticated;

-- 다트 게임
-- 서버 결과 확률: 적중 60%, 실패 40%
CREATE OR REPLACE FUNCTION public.play_dart_game(bet_amount bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_balance bigint;
  v_hit boolean;
  v_payout bigint := 0;
  v_new_balance bigint;
  v_score integer;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;
  if bet_amount is null or bet_amount <= 0 then
    raise exception '배팅 금액이 올바르지 않습니다.';
  end if;

  select coin_balance into v_balance
  from public.profiles
  where id = v_uid
  for update;

  if v_balance is null then raise exception '회원 정보를 찾을 수 없습니다.'; end if;
  if v_balance < bet_amount then raise exception '코인이 부족합니다.'; end if;

  v_hit := random() < 0.60;

  if v_hit then
    v_score := floor(random() * 21)::integer + 80;
    v_payout := bet_amount * 2;
  else
    v_score := floor(random() * 40)::integer;
  end if;

  v_new_balance := v_balance - bet_amount + v_payout;

  update public.profiles
  set coin_balance = v_new_balance
  where id = v_uid;

  return jsonb_build_object(
    'hit', v_hit,
    'success', v_hit,
    'score', v_score,
    'bet', bet_amount,
    'payout', v_payout,
    'new_balance', v_new_balance,
    'displayOdds', '60:40'
  );
end;
$function$;

grant execute on function public.play_dart_game(bigint) to authenticated;
