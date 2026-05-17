# Supabase auth frontend 체크리스트

- [x] 현재 앱 인증이 GAS sessionToken 기반임을 확인.
- [x] Supabase legacy 비밀번호 업데이트 pane 추가.
- [x] `weak_password_needs_reset` 응답에서 업데이트 pane으로 이동.
- [x] 새 비밀번호 6자 이상 검증과 확인값 검증 추가.
- [x] `legacy-password-upgrade` Edge Function 호출 helper 추가.
- [x] 성공 후 로그인 pane 복귀 처리.
- [x] 앱 버전과 script cache bust 값 갱신.
- [ ] Supabase anon key 확정 후 `signInWithPassword` 연결.
- [ ] Supabase 로그인 성공 후 기존 GAS sessionToken 의존 기능 대체.
- [ ] 실제 DEV 배포 후 모바일 로그인 modal 확인.
