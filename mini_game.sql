-- 코인 게임 전체 SQL
-- 중요: profiles 보호 트리거가 coin_balance 변경을 막고 있으면 아래 첫 함수로 coin_balance만 허용합니다.

CREATE OR REPLACE FUNCTION public.prevent_member_privilege_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is not null and not public.is_admin() then
    if new.id <> old.id
      or new.email <> old.email
      or new.role <> old.role
      or new.status <> old.status then
      raise exception '권한이 없는 필드입니다';
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.play_entertainment_game(bet_amount bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_balance bigint;
  v_symbols int[];
  v_win boolean;
  v_payout bigint := 0;
  v_new_balance bigint;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;
  if bet_amount is null or bet_amount <= 0 then raise exception '배팅 금액이 올바르지 않습니다.'; end if;
  select coin_balance into v_balance from public.profiles where id=v_uid for update;
  if v_balance is null then raise exception '회원 정보를 찾을 수 없습니다.'; end if;
  if v_balance < bet_amount then raise exception '코인이 부족합니다.'; end if;
  v_win := random() < 0.30;
  v_symbols := ARRAY[(floor(random()*7)+1)::int,(floor(random()*7)+1)::int,(floor(random()*7)+1)::int];
  if v_win then
    v_symbols[2] := v_symbols[1]; v_symbols[3] := v_symbols[1]; v_payout := bet_amount * 2;
  else
    while v_symbols[1]=v_symbols[2] and v_symbols[2]=v_symbols[3] loop
      v_symbols[3] := (floor(random()*7)+1)::int;
    end loop;
  end if;
  v_new_balance := v_balance - bet_amount + v_payout;
  update public.profiles set coin_balance=v_new_balance where id=v_uid;
  insert into public.entertainment_game_history(user_id,bet_amount,symbols,won,payout,balance_after)
  values(v_uid,bet_amount,v_symbols,v_win,v_payout,v_new_balance);
  return jsonb_build_object('symbols',v_symbols,'win',v_win,'bet',bet_amount,'payout',v_payout,'new_balance',v_new_balance);
end;
$function$;

grant execute on function public.play_entertainment_game(bigint) to authenticated;

CREATE OR REPLACE FUNCTION public.play_wheel_game()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_balance bigint;
  v_roll numeric;
  v_reward bigint := 0;
  v_new_balance bigint;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;
  select coin_balance into v_balance from public.profiles where id=v_uid for update;
  if v_balance is null then raise exception '회원 정보를 찾을 수 없습니다.'; end if;
  if v_balance < 1 then raise exception '코인이 부족합니다.'; end if;

  -- 돌림판 보상: 꽝 40%, +1 20%, +2 15%, +3 10%, +5 10%, +10 5%
  v_roll := random();
  if v_roll < 0.40 then v_reward := 0;
  elsif v_roll < 0.60 then v_reward := 1;
  elsif v_roll < 0.75 then v_reward := 2;
  elsif v_roll < 0.85 then v_reward := 3;
  elsif v_roll < 0.95 then v_reward := 5;
  else v_reward := 10;
  end if;

  v_new_balance := v_balance - 1 + v_reward;
  update public.profiles set coin_balance=v_new_balance where id=v_uid;
  return jsonb_build_object('cost',1,'reward',v_reward,'new_balance',v_new_balance);
end;
$function$;

grant execute on function public.play_wheel_game() to authenticated;
