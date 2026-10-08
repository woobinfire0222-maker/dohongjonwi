-- 초보자 룰렛 + 다트 최종 RPC
-- Supabase SQL Editor에서 실행

CREATE TABLE IF NOT EXISTS public.coin_game_action_counts (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  game_key text NOT NULL,
  action_count bigint NOT NULL DEFAULT 0 CHECK (action_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, game_key)
);

ALTER TABLE public.coin_game_action_counts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "coin_game_action_counts_select_own" ON public.coin_game_action_counts;
CREATE POLICY "coin_game_action_counts_select_own"
ON public.coin_game_action_counts
FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.play_beginner_roulette_game(bet_amount bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance bigint;
  v_action_count bigint;
  v_won boolean;
  v_payout bigint := 0;
  v_new_balance bigint;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
  IF bet_amount IS NULL OR bet_amount <= 0 THEN RAISE EXCEPTION '올바른 배팅 금액입니다.'; END IF;

  SELECT coin_balance INTO v_balance
  FROM public.profiles WHERE id = v_uid FOR UPDATE;

  IF v_balance IS NULL THEN RAISE EXCEPTION '회원 정보를 찾을 수 없습니다.'; END IF;
  IF v_balance < bet_amount THEN RAISE EXCEPTION '코인이 부족합니다.'; END IF;

  INSERT INTO public.coin_game_action_counts(user_id, game_key, action_count, updated_at)
  VALUES(v_uid, 'beginner_roulette', 1, now())
  ON CONFLICT(user_id, game_key)
  DO UPDATE SET action_count = public.coin_game_action_counts.action_count + 1,
                updated_at = now()
  RETURNING action_count INTO v_action_count;

  v_won := v_action_count BETWEEN 1 AND 3;
  IF v_won THEN v_payout := bet_amount * 2; END IF;

  v_new_balance := v_balance - bet_amount + v_payout;

  UPDATE public.profiles
  SET coin_balance = v_new_balance
  WHERE id = v_uid;

  RETURN jsonb_build_object(
    'success', v_won,
    'won', v_won,
    'actionCount', v_action_count,
    'bet', bet_amount,
    'payout', v_payout,
    'new_balance', v_new_balance
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.play_beginner_roulette_game(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.play_dart_game(bet_amount bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance bigint;
  v_won boolean;
  v_payout bigint := 0;
  v_new_balance bigint;
  v_score integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
  IF bet_amount IS NULL OR bet_amount <= 0 THEN RAISE EXCEPTION '올바른 배팅 금액입니다.'; END IF;

  SELECT coin_balance INTO v_balance
  FROM public.profiles WHERE id = v_uid FOR UPDATE;

  IF v_balance IS NULL THEN RAISE EXCEPTION '회원 정보를 찾을 수 없습니다.'; END IF;
  IF v_balance < bet_amount THEN RAISE EXCEPTION '코인이 부족합니다.'; END IF;

  v_won := random() < 0.60;
  v_score := CASE WHEN v_won THEN 100 ELSE 0 END;
  IF v_won THEN v_payout := bet_amount * 2; END IF;

  v_new_balance := v_balance - bet_amount + v_payout;

  UPDATE public.profiles
  SET coin_balance = v_new_balance
  WHERE id = v_uid;

  RETURN jsonb_build_object(
    'success', v_won,
    'won', v_won,
    'hit', v_won,
    'score', v_score,
    'bet', bet_amount,
    'payout', v_payout,
    'new_balance', v_new_balance
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.play_dart_game(bigint) TO authenticated;
