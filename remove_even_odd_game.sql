-- 홀짝 맞추기 게임을 기존 Supabase DB에서 제거합니다.
DROP FUNCTION IF EXISTS public.play_even_odd_game(text,bigint);
