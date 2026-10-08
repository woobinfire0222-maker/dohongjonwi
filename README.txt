돼홍존위 GitHub Pages 최종 배포본

업로드:
- 이 폴더의 모든 파일을 GitHub 저장소 최상위에 업로드
- Settings > Pages > Deploy from a branch > main > / (root)
- Custom domain: know.kro.kr

SPA:
- /app, /app/notices, /app/chat, /app/meetings, /app/stocks,
  /app/notifications, /app/profile, /login, /signup, /notice/*, /admin 지원
- 404.html을 SPA fallback으로 사용
- 커스텀 도메인에서는 루트 base를 사용
- github.io 프로젝트 페이지에서는 저장소 경로를 자동 인식


이번 수정 배포에 추가된 Supabase SQL:
- news_chat_fix.sql: 뉴스 테이블/RLS 및 뉴스 관리 기능, DM 자기 자신 제외 조회, 채팅 작성자 이름 조회 보강
- SQL Editor에서 news_chat_fix.sql을 1회 실행한 뒤 사이트 파일을 GitHub Pages에 업로드하세요.


이번 수정 - 2026-10-08:
- 모바일 반응형 레이아웃 정리 및 채팅/DM 모바일 목록-채팅 전환 개선
- 긴 닉네임/메시지/첨부 요소의 가로 넘침 방지
- 관리자/뉴스를 포함한 전역 모바일 overflow 대응
- 프로필 꾸미기 기능 추가: 테마, 상태메시지, 아이콘, 이모지, 이름/상태 색상, 배경색
- 프로필 설정은 profiles.profile_customization JSONB에 저장하며 이미지 업로드는 사용하지 않음
- 기존 채팅 번들의 구문 오류를 수정해 빈 화면 발생 방지

Supabase SQL Editor에서 profile_customization.sql을 1회 실행하세요. 기존 데이터는 유지됩니다.
