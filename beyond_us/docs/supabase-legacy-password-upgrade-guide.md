# Supabase legacy password upgrade 가이드

## 목적

기존 Google Sheet의 `pwv1$...` 비밀번호 해시를 이용해 사용자가 기존 비밀번호로 첫 로그인할 수 있게 한다. 기존 비밀번호가 Supabase Auth 정책을 만족하면 그대로 승격하고, 기존 4자리 비밀번호처럼 정책을 만족하지 않으면 기존 비밀번호로 본인 확인 후 새 비밀번호를 설정한다.

## 보안 원칙

- `PASSWORD_PEPPER`는 DB, Git, 채팅, 프론트 코드에 넣지 않는다.
- `PASSWORD_PEPPER`는 Supabase Edge Function Secret `LEGACY_PASSWORD_PEPPER`로만 저장한다.
- DEV와 PROD pepper는 서로 다를 수 있으므로 반드시 원본 Sheet와 같은 GAS 프로젝트의 값을 사용한다.
- 승격 성공 후 `legacy_auth_hashes.password_hash`는 `null`로 지운다.
- 실패 5회부터 10분간 `temporarily_locked` 상태가 된다.

## 1. Migration 적용

Supabase SQL Editor에서 아래 파일을 실행한다.

```text
beyond_us/supabase/migrations/20260517000500_legacy_auth_hashes.sql
```

## 2. 기존 해시 적재

먼저 dry-run으로 해시 개수와 issue를 확인한다.

```powershell
node "beyond_us\tools\supabase_import\import_legacy_auth_hashes.mjs" --file "C:\path\to\beyond_us_supabase_export_dev_YYYYMMDD_HHMMSS.json" --dry-run
```

`hashesPlanned`가 `profiles` 수와 같고 `issues`가 빈 배열이어야 한다.

문제 없으면 apply 한다.

```powershell
$env:SUPABASE_URL="https://프로젝트-ref.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="Supabase service role key"
node "beyond_us\tools\supabase_import\import_legacy_auth_hashes.mjs" --file "C:\path\to\beyond_us_supabase_export_dev_YYYYMMDD_HHMMSS.json" --apply
```

이미 승격이 끝난 사용자는 재실행해도 hash를 다시 살리지 않고 `skippedMigrated`로 건너뛴다.

## 3. Edge Function Secret 설정

Supabase Dashboard 또는 CLI에서 `legacy-password-upgrade` 함수에 아래 secret을 설정한다.

```text
LEGACY_PASSWORD_PEPPER=<GAS Script Properties의 PASSWORD_PEPPER>
```

값은 절대 문서나 채팅에 남기지 않는다.

`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_SECRET_KEYS`는 Supabase Edge Function에 기본으로 제공되는 reserved secret이다. Dashboard에서 직접 추가하려고 하면 `Name must not start with the SUPABASE_ prefix` 오류가 난다. 따라서 직접 추가하지 않는다.

## 4. Edge Function 배포

함수 소스는 아래 위치에 있다.

```text
beyond_us/supabase/functions/legacy-password-upgrade/index.ts
```

Supabase CLI를 사용할 경우 예시는 다음과 같다.

```powershell
Set-Location "C:\Users\jkjk9\OneDrive\Documents\00_Work\01_AGC\AGC\2026_Youth_treat\website\beyond_us"
npx supabase@latest login
npx supabase@latest functions deploy legacy-password-upgrade --project-ref qjwtkvfdzpeovjabdwxv
```

전역 `supabase` 명령이 없어도 `npx supabase@latest`로 실행할 수 있다. Node.js 20 이상이 필요하며, 현재 작업 환경은 Node.js 24 계열이라 조건을 만족한다.

`legacy-password-upgrade`는 로그인 전 사용자가 호출해야 하므로 `supabase/config.toml`에서 `verify_jwt = false`로 둔다.

## 5. 첫 로그인 흐름

프론트 전환 후 로그인 로직은 아래 순서를 따른다.

1. 사용자가 아이디와 비밀번호를 입력한다.
2. Supabase Auth `signInWithPassword`를 먼저 시도한다.
3. 실패했고 `profiles.password_migration_required=true`인 사용자라면 `legacy-password-upgrade`를 호출한다.
4. `legacy-password-upgrade`가 `{ ok: false, error: "weak_password_needs_reset" }`를 반환하면 새 비밀번호 입력 화면을 띄운다.
5. 사용자가 기존 비밀번호와 6자 이상 새 비밀번호를 함께 제출하면 `legacy-password-upgrade`를 다시 호출한다.
6. `legacy-password-upgrade`가 `{ ok: true, passwordMigrated: true }`를 반환하면 같은 아이디와 새 비밀번호로 다시 `signInWithPassword`를 호출한다.
7. 이후부터는 legacy hash를 쓰지 않는다.

## 수동 테스트

기존 4자리 비밀번호만 보내면 재설정 필요 응답이 나와야 한다.

```powershell
$body = @{
  loginId = "테스트아이디"
  password = "기존비밀번호"
} | ConvertTo-Json

Invoke-RestMethod `
  -Method Post `
  -Uri "https://qjwtkvfdzpeovjabdwxv.supabase.co/functions/v1/legacy-password-upgrade" `
  -ContentType "application/json" `
  -Body $body
```

예상 응답은 아래와 같다.

```json
{
  "ok": false,
  "error": "weak_password_needs_reset",
  "minPasswordLength": 6
}
```

새 비밀번호를 함께 보내면 승격이 완료되어야 한다.

```powershell
$body = @{
  loginId = "테스트아이디"
  password = "기존비밀번호"
  newPassword = "새비밀번호6자이상"
} | ConvertTo-Json

Invoke-RestMethod `
  -Method Post `
  -Uri "https://qjwtkvfdzpeovjabdwxv.supabase.co/functions/v1/legacy-password-upgrade" `
  -ContentType "application/json" `
  -Body $body
```

## 확인 쿼리

```sql
select count(*) as legacy_hashes
from public.legacy_auth_hashes;

select count(*) as pending_legacy_migration
from public.legacy_auth_hashes
where migrated_at is null
  and password_hash is not null;

select count(*) as migrated_legacy_passwords
from public.legacy_auth_hashes
where migrated_at is not null
  and password_hash is null;
```

## 보류 작업

- `app.js` 로그인 계층에 legacy upgrade 호출 추가.
- admin에서 사용자별 `password_migration_required` 상태 확인 표시.
- PROD 전환 후 legacy migration 기간 종료 시 `legacy_auth_hashes` 제거 또는 장기 비활성화.
