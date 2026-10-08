-- 돼홍존위 프로필 꾸미기 기능
-- 기존 사용자/프로필/데이터를 삭제하거나 변경하지 않고 프로필 설정 컬럼만 추가합니다.
-- 이미지 업로드/Storage 기능은 사용하지 않습니다.

alter table public.profiles
  add column if not exists profile_customization jsonb not null default '{}'::jsonb;

comment on column public.profiles.profile_customization is
  '카카오톡 스타일 프로필 꾸미기 설정(JSON): theme, status_message, background_color, icon, name_color, status_color, decoration, theme_color';

-- 기존 RLS 정책을 유지합니다.
-- profiles의 기존 SELECT/UPDATE 정책이 있다면 그대로 사용하며,
-- 기존 회원 정보 수정 기능과 동일한 권한 범위에서 profile_customization도 저장됩니다.

create index if not exists profiles_profile_customization_gin_idx
  on public.profiles using gin (profile_customization);
