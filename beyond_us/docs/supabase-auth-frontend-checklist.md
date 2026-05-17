# Supabase auth frontend 체크리스트

- [x] 현재 앱 인증이 GAS sessionToken 기반임을 확인.
- [x] Supabase legacy 비밀번호 업데이트 pane 추가.
- [x] `weak_password_needs_reset` 응답에서 업데이트 pane으로 이동.
- [x] 새 비밀번호 6자 이상 검증과 확인값 검증 추가.
- [x] `legacy-password-upgrade` Edge Function 호출 helper 추가.
- [x] 성공 후 로그인 pane 복귀 처리.
- [x] 앱 버전과 script cache bust 값 갱신.
- [x] Supabase Auth REST password login helper 추가.
- [x] synthetic email 생성 규칙을 프론트에 반영.
- [x] Supabase 세션 localStorage 저장 helper 추가.
- [x] Supabase auth mode를 `off`, `shadow`, `primary`로 분리.
- [x] Supabase publishable key 확정 후 `SUPABASE_ANON_KEY` 반영.
- [ ] 앱 데이터 API 전환 후 `SUPABASE_AUTH_MODE`를 `primary`로 전환.
- [ ] Supabase 로그인 성공 후 기존 GAS sessionToken 의존 기능 대체.
- [ ] 실제 DEV 배포 후 모바일 로그인 modal 확인.
