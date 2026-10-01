-- 투표 1인 1표 및 새로고침 재투표 문제 수정
-- Supabase SQL Editor에서 1회 실행

-- 기존에 중복 투표가 생겨 있다면 가장 먼저 한 표만 남깁니다.
with duplicate_votes as (
  select id,
         row_number() over (
           partition by poll_id, user_id
           order by created_at asc, id asc
         ) as rn
  from public.poll_votes
)
delete from public.poll_votes pv
using duplicate_votes d
where pv.id = d.id
  and d.rn > 1;

-- DB 차원에서 한 회원이 같은 투표에 두 번 투표하지 못하게 막습니다.
create unique index if not exists poll_votes_one_vote_per_user_idx
on public.poll_votes(poll_id, user_id);

-- 프론트에서 내 투표 기록을 안정적으로 읽도록 전용 RPC를 사용합니다.
create or replace function public.get_my_poll_votes()
returns table(poll_id uuid, option_id uuid)
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  return query
  select pv.poll_id, pv.option_id
  from public.poll_votes pv
  where pv.user_id = auth.uid();
end;
$function$;

grant execute on function public.get_my_poll_votes() to authenticated;

-- 투표 제출을 DB에서 원자적으로 처리합니다.
create or replace function public.vote_poll(p_poll_id uuid, p_option_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_poll public.polls;
  v_option public.poll_options;
  v_vote_id uuid;
begin
  if v_uid is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 투표 행만 잠가서 종료 시점/동시 요청을 안전하게 처리합니다.
  select *
    into v_poll
  from public.polls
  where id = p_poll_id
  for update;

  if v_poll.id is null then
    raise exception '투표를 찾을 수 없습니다.';
  end if;

  if v_poll.is_closed or (v_poll.ends_at is not null and v_poll.ends_at <= now()) then
    raise exception '이미 종료된 투표입니다.';
  end if;

  select *
    into v_option
  from public.poll_options
  where id = p_option_id
    and poll_id = p_poll_id;

  if v_option.id is null then
    raise exception '선택지가 올바르지 않습니다.';
  end if;

  insert into public.poll_votes(poll_id, option_id, user_id)
  values (p_poll_id, p_option_id, v_uid)
  on conflict (poll_id, user_id) do nothing
  returning id into v_vote_id;

  if v_vote_id is null then
    raise exception '이미 이 투표에 참여했습니다.';
  end if;

  return jsonb_build_object(
    'id', v_vote_id,
    'poll_id', p_poll_id,
    'option_id', p_option_id
  );
end;
$function$;

grant execute on function public.vote_poll(uuid, uuid) to authenticated;
