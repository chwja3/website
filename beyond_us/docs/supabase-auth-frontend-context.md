# Supabase auth frontend 컨텍스트

## 결정

- 2026-05-18. 현재 `app.js`는 GAS `login` 응답으로 `sessionToken`을 받아 모든 앱 API에 붙이는 구조다. Supabase Auth만 즉시 켜면 로그인은 되어도 미션, 카드, 대시보드 API가 이어지지 않으므로 이번 변경에서는 기존 GAS 로그인 흐름을 유지한다.
- 2026-05-18. 기존 유저 비밀번호가 전부 4자리라 Supabase Auth에 그대로 저장할 수 없다. 따라서 기존 비밀번호는 legacy hash 본인 확인용으로만 쓰고, 새 6자 이상 비밀번호를 받아 `legacy-password-upgrade` Edge Function으로 승격한다.
- 2026-05-18. 프론트는 `weak_password_needs_reset`, `password_migration_required`, `legacy_password_reset_required` 응답을 모두 같은 재설정 흐름으로 처리한다. 실제 백엔드 응답 이름이 전환 중 바뀌어도 UI가 흔들리지 않게 하기 위함이다.
- 2026-05-18. Supabase Auth REST password login helper를 추가했다. `SUPABASE_ANON_KEY`가 비어 있으면 `off`, 값이 있으면 기본 `shadow`로 동작한다. `shadow`는 기존 GAS 로그인 성공 후 Supabase 세션 저장만 시도하고, `primary`는 앱 데이터 API 전환 전까지 켜지 않는다.
- 2026-05-18. Supabase publishable key를 `SUPABASE_ANON_KEY`에 반영했다. 이 값은 public key이며, 반영 후 앱은 기본 `shadow` 모드로 동작한다.
- 2026-05-18. shadow mode에서 기존 GAS 로그인은 성공하지만 Supabase access token이 `null`로 남는 상황을 확인했다. 원인은 기존 4자리 비밀번호 계정이 아직 Supabase Auth password로 승격되지 않았기 때문이다. GAS 로그인 성공 후 Supabase 로그인 실패 시 `legacy-password-upgrade`를 probe로 호출하고, `weak_password_needs_reset`이면 새 비밀번호 업데이트 pane을 띄우도록 보강했다.
- 2026-05-18. 첫 보강에서는 `showApp()` 이후에 shadow probe가 실행되어 auth pane은 바뀌어도 화면에 보이지 않았다. GAS 로그인 성공 직후 앱 진입 전에 shadow login과 legacy probe를 먼저 실행하고, 업데이트가 필요하면 `showApp()`으로 넘어가지 않도록 순서를 바꿨다.
- 2026-05-18. 업데이트가 필요한 계정은 기존 4자리로 GAS 로그인 성공 시 받은 sessionToken을 보관했다가, 새 비밀번호 업데이트와 Supabase login 성공 후 그 GAS sessionToken으로 앱에 진입한다. 아직 앱 데이터 API가 GAS 기반이므로, 새 비밀번호만으로는 GAS 로그인이 되지 않는 과도기 문제를 피하기 위함이다.
- 2026-05-18. `SUPABASE_AUTH_MODE`는 DEV 환경에서만 shadow로 켜지도록 제한했다. PROD에 이 코드가 들어가도 Supabase 전환 전에는 기존 GAS 로그인 흐름에 영향을 주지 않는다.
- 2026-05-18. DEV 앱을 Supabase primary auth와 Supabase data read 기본값으로 전환했다. 로그인 성공 시 `app-auth` Edge Function의 `session` action으로 현재 `profiles` 정보를 확인하고, 기존 GAS `sessionToken` 없이 `showApp()`과 `syncInitialData()`로 진입한다. 회원가입, 닉네임 찾기, 사용자 비밀번호 재설정은 DEV primary mode에서 `app-auth` Edge Function을 사용한다. PROD는 여전히 `SUPABASE_AUTH_MODE=off`라 기존 GAS 경로를 사용한다.
- 2026-05-18. `legacy-password-upgrade`가 409 `already_migrated`를 반환하면 해당 계정은 이미 Supabase 비밀번호 설정이 끝난 상태다. 이 경우 기존 4자리로 다시 업데이트할 수 없으므로 DEV에서는 앱 진입을 막고 새 비밀번호 사용 안내를 표시한다.

## 남은 연결

- `app-auth` Edge Function을 DEV Supabase에 배포해야 primary auth 경로가 실제 동작한다.
- 아직 승격되지 않은 4자리 계정은 로그인 시 새 비밀번호 업데이트 pane이 뜨는지, 업데이트 후 Supabase session 기반 앱 진입이 되는지 확인한다.
- 앱 기능별 Supabase RPC 실패 시 남아있는 GAS fallback은 DEV primary 회귀 테스트 후 제거한다.
