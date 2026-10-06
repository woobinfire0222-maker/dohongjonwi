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
