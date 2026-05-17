# Supabase auth frontend plan

## 목표

기존 4자리 비밀번호 사용자가 Supabase 전환 후 첫 로그인에서 새 6자 이상 비밀번호를 설정할 수 있게 한다.

## 범위

- 현재 GAS 로그인과 세션 흐름은 그대로 둔다.
- Supabase Auth가 본격 연결되기 전까지 기존 사용자 화면을 깨지 않도록 한다.
- 향후 로그인 응답이나 Supabase 로그인 계층이 `weak_password_needs_reset`을 반환하면 새 비밀번호 설정 pane으로 이동한다.

## 구현 방향

1. 앱 로그인 modal 안에 legacy 비밀번호 업데이트 pane을 추가한다.
2. 로그인 시 `weak_password_needs_reset` 계열 오류를 받으면 기존 아이디와 기존 비밀번호를 임시 state에 보관하고 pane을 연다.
3. 사용자가 새 비밀번호와 확인값을 입력하면 `legacy-password-upgrade` Edge Function에 `loginId`, `password`, `newPassword`를 전송한다.
4. 승격 성공 후 기존 비밀번호 state를 지우고 로그인 pane으로 되돌린다.
5. 실제 Supabase Auth sign-in 연결은 anon key와 API endpoint 전환이 끝난 뒤 별도 작업으로 처리한다.
