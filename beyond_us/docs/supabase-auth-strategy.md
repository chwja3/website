# Supabase Auth 전환 전략

## 결정 요약

- 사용자 화면은 지금처럼 아이디, 비밀번호 입력 경험을 유지한다.
- 내부 인증은 Supabase Auth email/password를 사용한다.
- 실제 이메일을 수집하지 않으므로 Auth email은 화면 아이디에서 만든 내부용 synthetic email을 사용한다.
- 비밀번호는 `profiles`나 다른 public 테이블에 저장하지 않고 Supabase Auth에만 맡긴다.
- 기존 GAS `sessionToken`은 Supabase Auth session과 JWT로 대체한다.
- 관리자 로그인은 공용 `ADMIN_PASSWORD` 방식이 아니라 Supabase Auth 계정과 `profiles.role` 기반으로 전환한다.

## 아이디 정책

- `profiles.login_id`는 대소문자를 구분하는 사용자 로그인 아이디다.
- `Oh! New`와 `oh! New`는 서로 다른 아이디로 취급한다.
- 앞뒤 공백은 가입과 로그인 입력에서 제거한다.
- 화면 표시 이름은 `display_name`을 우선 사용하고, 운영진 확인용 실제 이름은 `name`에 보관한다.

## Synthetic email 규칙

Supabase Auth는 email/password 또는 phone/password 기반 흐름이 가장 단순하다. 실제 이메일을 받지 않기 위해 앱 내부에서만 쓰는 이메일을 만든다.

```text
u_<sha256(trim(login_id))>@auth.beyond-us.local
```

- 해시는 정확한 대소문자를 포함한 `login_id`로 계산한다.
- 해시 결과는 hex 소문자로 둔다.
- 사용자는 이 이메일을 보지 않는다.
- 같은 아이디를 같은 대소문자로 입력하면 항상 같은 synthetic email이 만들어진다.

## 가입 흐름

1. 프론트에서 이름, 교구, 아이디, 비밀번호를 입력받는다.
2. `auth_register_profile` Edge Function을 호출한다.
3. Edge Function은 `login_id` 중복, 필수값, 비밀번호 길이, 교구 값을 검증한다.
4. Edge Function은 service role로 Supabase Auth 사용자를 생성한다.
5. Edge Function은 `profiles`, `retreat_attendance`, `user_inventory`, `user_summary` 기본 행을 생성한다.
6. 추첨권 제외 대상이 아니면 가입 추첨권을 발급하고 `events`에 기록한다.
7. 가입 성공 후 프론트는 바로 `signInWithPassword` 또는 반환된 session으로 앱에 진입한다.

## 로그인 흐름

1. 사용자가 아이디와 비밀번호를 입력한다.
2. 프론트는 아이디를 trim한 뒤 synthetic email을 계산한다.
3. `supabase.auth.signInWithPassword({ email, password })`로 로그인한다.
4. 로그인 성공 후 `get_user_status` 또는 `get_app_bootstrap` 계열 RPC를 호출한다.
5. localStorage에는 Supabase session과 화면 캐시만 남기고, 비밀번호와 기존 GAS `sessionToken`은 저장하지 않는다.

## 비밀번호 재설정

실제 이메일을 쓰지 않으므로 Supabase의 이메일 링크 기반 재설정은 기본 경로로 사용하지 않는다.

### 사용자 재설정

- 기존 UX를 유지하되 `reset_password_by_profile` Edge Function으로 옮긴다.
- 입력값은 아이디, 이름, 교구, 새 비밀번호다.
- 함수는 rate limit, 감사 이벤트, 실패 횟수 제한을 둔다.
- 일치하는 활성 사용자 1명만 있을 때 service role로 Auth password를 갱신한다.
- 재설정 성공 시 기존 세션은 무효화한다.

### 관리자 재설정

- `admin_reset_password` Edge Function으로 옮긴다.
- 호출자는 Supabase Auth로 로그인되어 있어야 하고, `profiles.role in ('admin', 'dev')`인 경우만 허용한다.
- 모든 재설정은 `events`에 `auth.password_reset.admin`으로 남긴다.

## 기존 사용자 이관

- Google Sheet의 기존 비밀번호 해시는 Supabase Auth 해시로 직접 변환하지 않는다.
- 이관 시 기존 사용자별 Supabase Auth 계정을 생성하되 임시 랜덤 비밀번호를 사용한다.
- 기존 GAS `pwv1$...` 해시는 `legacy_auth_hashes`에 임시 보관한다.
- `PASSWORD_PEPPER`는 Edge Function Secret `LEGACY_PASSWORD_PEPPER`에만 저장한다.
- 사용자가 기존 아이디와 비밀번호로 첫 로그인을 시도하면 `legacy-password-upgrade` Edge Function이 기존 해시를 1회 검증한다.
- 검증 성공 시 입력한 비밀번호를 Supabase Auth password로 설정하고 `profiles.password_migration_required=false`로 바꾼다.
- 승격 성공 후 `legacy_auth_hashes.password_hash`는 `null`로 지운다.
- 기존 해시 검증이 불가능하거나 실패한 사용자는 비밀번호 재설정 흐름으로 새 비밀번호를 설정한다.

## 관리자 권한

- 관리자와 개발자도 일반 Supabase Auth 계정으로 로그인한다.
- 권한은 `profiles.role`과 `profiles.is_dev`로 판단한다.
- 프론트 admin 페이지에는 admin password를 저장하지 않는다.
- admin 전용 RPC와 Edge Function은 매 호출마다 현재 JWT의 `auth.uid()`와 `profiles.role`을 확인한다.

## RLS에 주는 영향

- 사용자 본인 데이터는 `profiles.auth_user_id = auth.uid()` 기준으로 읽고 쓴다.
- 관리자 데이터 접근은 `exists` 조건으로 현재 사용자의 role을 확인한다.
- public table 직접 접근은 최소화하고, 복잡한 집계와 보상 지급은 RPC 또는 Edge Function에서 처리한다.

## Supabase Dashboard 설정

- Email provider는 사용하되 실제 이메일 확인 링크를 핵심 플로우로 쓰지 않는다.
- 공개 sign up은 프론트에서 직접 열지 않고 `auth_register_profile` Edge Function을 통해서만 처리한다.
- service role key는 Edge Function 환경변수에만 저장하고 프론트 코드에는 절대 넣지 않는다.
