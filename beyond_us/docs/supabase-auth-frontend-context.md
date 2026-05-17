# Supabase auth frontend 컨텍스트

## 결정

- 2026-05-18. 현재 `app.js`는 GAS `login` 응답으로 `sessionToken`을 받아 모든 앱 API에 붙이는 구조다. Supabase Auth만 즉시 켜면 로그인은 되어도 미션, 카드, 대시보드 API가 이어지지 않으므로 이번 변경에서는 기존 GAS 로그인 흐름을 유지한다.
- 2026-05-18. 기존 유저 비밀번호가 전부 4자리라 Supabase Auth에 그대로 저장할 수 없다. 따라서 기존 비밀번호는 legacy hash 본인 확인용으로만 쓰고, 새 6자 이상 비밀번호를 받아 `legacy-password-upgrade` Edge Function으로 승격한다.
- 2026-05-18. 프론트는 `weak_password_needs_reset`, `password_migration_required`, `legacy_password_reset_required` 응답을 모두 같은 재설정 흐름으로 처리한다. 실제 백엔드 응답 이름이 전환 중 바뀌어도 UI가 흔들리지 않게 하기 위함이다.
- 2026-05-18. Supabase Auth REST password login helper를 추가했다. `SUPABASE_ANON_KEY`가 비어 있으면 `off`, 값이 있으면 기본 `shadow`로 동작한다. `shadow`는 기존 GAS 로그인 성공 후 Supabase 세션 저장만 시도하고, `primary`는 앱 데이터 API 전환 전까지 켜지 않는다.

## 남은 연결

- Supabase anon key를 `SUPABASE_ANON_KEY`에 추가해야 `signInWithPassword`에 해당하는 REST password login을 호출할 수 있다.
- Supabase Auth 로그인 후 앱 내부 데이터 API도 Supabase Edge Function 또는 PostgREST/RPC로 바뀌어야 한다.
