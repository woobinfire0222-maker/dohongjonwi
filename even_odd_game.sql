-- 홀짝 맞추기 게임
CREATE OR REPLACE FUNCTION public.play_even_odd_game(bet_choice text, bet_amount bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_balance bigint;
  v_number integer;
  v_result text;
  v_won boolean;
  v_payout bigint := 0;
  v_new_balance bigint;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;
  if lower(coalesce(bet_choice,'')) not in ('홀','짝') then raise exception '홀 또는 짝을 선택해 주세요.'; end if;
  if bet_amount is null or bet_amount <= 0 then raise exception '배팅 금액이 올바르지 않습니다.'; end if;
  select coin_balance into v_balance from public.profiles where id=v_uid for update;
  if v_balance is null then raise exception '회원 정보를 찾을 수 없습니다.'; end if;
  if v_balance < bet_amount then raise exception '코인이 부족합니다.'; end if;
  v_number := floor(random()*100)::integer + 1;
  v_result := case when mod(v_number,2)=0 then '짝' else '홀' end;
  v_won := v_result = bet_choice;
  if v_won then v_payout := bet_amount * 2; end if;
  v_new_balance := v_balance - bet_amount + v_payout;
  update public.profiles set coin_balance=v_new_balance where id=v_uid;
  return jsonb_build_object('bet_choice',bet_choice,'number',v_number,'result',v_result,'won',v_won,'bet',bet_amount,'payout',v_payout,'new_balance',v_new_balance);
end;
$function$;

grant execute on function public.play_even_odd_game(text,bigint) to authenticated;
