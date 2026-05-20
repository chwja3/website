# 2026-05-21 main 반영 체크리스트

- [x] `dev`와 `main` 차이 확인.
- [x] main에 이미 들어간 H&P SQL 중복 제외.
- [x] 신규 천로역정 SQL 2개를 하나의 PROD 실행 파일로 묶기.
- [x] `dev` 변경사항을 `main`에 병합.
- [x] main 전용 verification SQL 파일 삭제 여부 확인 후 보존.
- [x] 정적 검사 실행.
- [ ] main push.
- [ ] 사용자가 PROD Storage에 Q.T. PNG 수동 업로드.
- [ ] 사용자가 PROD Supabase에서 통합 SQL 실행.
