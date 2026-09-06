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


이메일 기능 변경:
- 비밀번호 찾기/재설정 메일 기능 제거
- 이메일 인증/인증번호 UI 및 호출 제거
- 회원가입 이메일 입력값은 회원 데이터로 저장되며 별도 메일 발송 기능을 사용하지 않음
- Supabase Authentication의 이메일 확인(Confirm email)은 Supabase 대시보드에서 OFF로 설정해야 가입 시 확인 메일이 발송되지 않음
