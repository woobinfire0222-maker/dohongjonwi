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
