# Supabase main 전환 실행 절차

이 문서는 운영 서버를 점검 상태로 닫은 뒤, 순서대로 따라 하면 `main`을 Supabase 기반으로 전환할 수 있도록 만든 최신 runbook이다. 2026-05-19 기준 `dev` 브랜치에서 검증된 Supabase 전환 상태를 기준으로 한다.

## 0. 절대 먼저 확인할 것

아래 조건 중 하나라도 불확실하면 서버를 닫기 전에 멈춘다.

- `main`이 붙을 Supabase 프로젝트가 정해져 있어야 한다.
- 해당 Supabase 프로젝트의 데이터가 PROD 정본이어야 한다.
- DEV 검증 데이터가 남아 있는 Supabase 프로젝트에 PROD Sheet 데이터를 섞어 넣으면 안 된다.
- 프론트 코드의 Supabase URL이 PROD 프로젝트를 바라보는지 확인한다.
- 별도 PROD Supabase 프로젝트를 쓸 계획이면, `app.js`와 `admin.html`의 Supabase URL과 anon key를 PROD 값으로 바꾸는 커밋을 먼저 만든다.
- 2026-05-19 전환 작업에서는 `AGC retreat PROD` 프로젝트를 사용한다.

권장 판단은 이렇다.

- DEV 검증용 데이터와 PROD 운영 데이터를 분리하고 싶으면 별도 PROD Supabase 프로젝트를 만든다.
- DEV 프로젝트를 최종 운영 DB로 착각해 연결하지 않는다.

## 1. 서버 닫기 전 준비

서버를 닫기 전에 미리 끝낼 수 있는 작업이다.

1. `dev` 브랜치 최신 상태를 받는다.

```powershell
git checkout dev
git pull origin dev
git status --short
```

2. `git status --short`에서 의도하지 않은 수정 파일이 없어야 한다. `.claude/worktrees/`, `K-translate/` 같은 무관한 untracked는 커밋하지 않는다.

3. Supabase 프로젝트 정보를 준비한다.

```powershell
$env:SUPABASE_URL="https://프로젝트-ref.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="service role key"
```

주의할 점.

- `SUPABASE_URL`에는 `/rest/v1/`을 붙이지 않는다.
- `SUPABASE_SERVICE_ROLE_KEY`는 Supabase Dashboard의 service role key다.
- 이 값들은 절대 repo에 커밋하지 않는다.

4. PowerShell에서 `npx`가 막히면 `npx.cmd`를 쓴다.

```powershell
npx.cmd supabase@latest --version
```

5. PROD용 Edge Function secrets를 Supabase Dashboard에서 확인한다.

필수 secret.

- `SUPABASE_URL`.
- `SUPABASE_SERVICE_ROLE_KEY` 또는 `SUPABASE_SECRET_KEYS`.
- `LEGACY_PASSWORD_PEPPER`.

`LEGACY_PASSWORD_PEPPER`는 기존 PROD GAS Script Properties에 있던 pepper 값이어야 한다. DEV pepper를 PROD에 넣으면 기존 비밀번호 승격이 실패한다.

6. Edge Functions를 배포한다.

Supabase CLI가 프로젝트에 link되어 있다면 아래처럼 실행한다.

```powershell
npx.cmd supabase@latest functions deploy app-auth
npx.cmd supabase@latest functions deploy legacy-password-upgrade
npx.cmd supabase@latest functions deploy admin-reset-password
```

link가 안 되어 있으면 먼저 프로젝트를 link한다.

```powershell
npx.cmd supabase@latest link --project-ref 프로젝트-ref
```

7. SQL migration 적용 범위를 확인한다.

PROD에 적용할 파일.

- `20260517000100_initial_schema.sql`.
- `20260517000200_schema_comments.sql`.
- `20260517000300_auth_login_id_policy.sql`.
- `20260517000400_import_audit_tables.sql`.
- `20260517000500_legacy_auth_hashes.sql`.
- `20260518000100_user_app_read_rpcs.sql`.
- `20260518000200_submit_pre_mission_rpc.sql`.
- `20260518000300_user_app_write_rpcs.sql`.
- `20260518000400_storage_hp_admin_rpcs.sql`.
- `20260518000500_raffle_ticket_policy_rpcs.sql`.
- `20260518000600_admin_raffle_backfill_rpc.sql`.
- `20260518000700_notice_read_rpc.sql`.
- `20260518000800_admin_dashboard_card_stats.sql`.
- `20260518000900_admin_parish_summary_axis.sql`.
- `20260518001000_admin_card_adjust_rebuild.sql`.
- `20260518001100_operational_summary_refresh.sql`.
- `20260518001200_ops_readable_views.sql`.
- `20260518001300_admin_event_logs.sql`.
- `20260518001400_admin_attendance_sorted.sql`.
- `20260518001600_admin_post_gas_fixes.sql`.

PROD에 기본적으로 적용하지 않을 파일.

- `20260518001500_dev_reset_cards.sql`.

`20260518001500_dev_reset_cards.sql`은 DEV 개발자 카드 초기화용이다. PROD에서는 원칙적으로 실행하지 않는다.

## 2. 서버 닫기

1. 사용자 앱을 점검 상태로 전환한다.
2. 운영진에게 점검 중에는 앱에서 데이터 변경을 하지 말라고 공유한다.
3. 이 시점 이후 Google Sheet와 기존 GAS 경로에 새 데이터가 쓰이면 안 된다.
4. 기존 GAS Active deployment는 이미 꺼져 있어도 Apps Script 편집기에서 수동 함수 실행은 가능하다.

## 3. PROD Sheet 백업

1. PROD Google Sheet 전체 사본을 만든다.
2. 사본 이름에 날짜와 시간을 넣는다.
3. 백업 파일 링크를 운영 기록에 남긴다.
4. 백업이 끝나기 전에는 export를 시작하지 않는다.

## 4. PROD Sheet JSON export

Apps Script 편집기에서 아래 함수를 실행한다.

```javascript
exportSupabaseMigrationJsonProd()
```

확인할 것.

- 실행 로그에 `ok: true`가 떠야 한다.
- Drive에 `beyond_us_supabase_export_prod_YYYYMMDD_HHMMSS.json` 형태의 파일이 생성되어야 한다.
- 이 JSON 파일은 PROD 이관 원본 스냅샷이므로 삭제하지 않는다.

생성된 JSON을 로컬로 내려받는다. 아래 예시는 다운로드 경로를 변수로 잡는 방식이다.

```powershell
$exportFile="C:\Users\jkjk9\Downloads\beyond_us_supabase_export_prod_YYYYMMDD_HHMMSS.json"
```

## 5. PROD Supabase SQL migration 적용

Supabase SQL Editor에서 1번 준비 단계에 적은 PROD용 SQL 파일을 순서대로 실행한다.

반드시 제외할 파일.

```text
beyond_us/supabase/migrations/20260518001500_dev_reset_cards.sql
```

마지막으로 실행되어 있어야 하는 파일.

```text
beyond_us/supabase/migrations/20260518001600_admin_post_gas_fixes.sql
```

실행 중 경고가 뜨는 경우.

- 테이블 생성, 함수 생성, 권한 변경이 포함되어 있으므로 Supabase SQL Editor가 destructive warning을 띄울 수 있다.
- 새 PROD DB 또는 전환용 DB에 적용하는 것이 맞다면 진행한다.
- 이미 운영 중인 다른 데이터가 섞인 DB라면 멈춘다.

## 6. JSON 원본 row 적재

로컬 PowerShell에서 repo 루트로 이동한다.

```powershell
cd "C:\Users\jkjk9\OneDrive\Documents\00_Work\01_AGC\AGC\2026_Youth_treat\website"
```

환경 변수를 다시 확인한다.

```powershell
$env:SUPABASE_URL="https://프로젝트-ref.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="service role key"
```

Dry run을 먼저 실행한다.

```powershell
node "beyond_us\tools\supabase_import\import_legacy_rows.mjs" --file $exportFile --dry-run
```

문제가 없으면 apply 한다.

```powershell
node "beyond_us\tools\supabase_import\import_legacy_rows.mjs" --file $exportFile --apply
```

이 단계는 원본 Sheet row를 `legacy_sheet_rows`와 import 감사 테이블에 보존하는 단계다.

## 7. 정규 테이블 적재

Dry run.

```powershell
node "beyond_us\tools\supabase_import\import_normalized_data.mjs" --file $exportFile --dry-run
```

Apply.

```powershell
node "beyond_us\tools\supabase_import\import_normalized_data.mjs" --file $exportFile --apply
```

이 단계에서 `profiles`, `events`, `user_inventory`, `user_cards`, `mission_progress`, `raffle_tickets`, H&P, BBB, 공지, 문의 등 정규 테이블이 채워진다.

## 8. 기존 비밀번호 해시 적재

Dry run.

```powershell
node "beyond_us\tools\supabase_import\import_legacy_auth_hashes.mjs" --file $exportFile --dry-run
```

Apply.

```powershell
node "beyond_us\tools\supabase_import\import_legacy_auth_hashes.mjs" --file $exportFile --apply
```

이 단계는 기존 GAS 비밀번호 해시를 `legacy_auth_hashes`에 저장한다. 기존 4자리 비밀번호를 그대로 복호화하는 것이 아니라, 사용자가 최초 접속 시 6자 이상 비밀번호로 승격할 수 있게 검증 재료를 보관하는 단계다.

## 9. Supabase Auth 계정 생성

Dry run.

```powershell
node "beyond_us\tools\supabase_import\create_auth_users.mjs" --dry-run
```

Apply.

```powershell
node "beyond_us\tools\supabase_import\create_auth_users.mjs" --apply
```

이 스크립트는 재실행 가능하다. 이미 `profiles.auth_user_id`가 있으면 건너뛰고, Auth 사용자만 존재하면 profile에 연결한다.

## 10. DB 검증

Supabase SQL Editor에서 아래 쿼리를 실행한다.

```sql
select
  source_environment,
  source_snapshot_label,
  status,
  row_counts->'source' as source_counts,
  row_counts->'targets' as target_counts,
  created_at,
  completed_at,
  notes
from public.migration_batches
where source_environment = 'prod'
order by created_at desc
limit 5;

select count(*) as profiles from public.profiles;
select count(*) as active_profiles from public.profiles where account_status = 'active';
select count(*) as events from public.events;
select count(*) as active_raffle_tickets from public.raffle_tickets where active = true;
select count(*) as user_inventory from public.user_inventory;
select count(*) as user_cards from public.user_cards;
select count(*) as mission_progress from public.mission_progress;
select count(*) as hold_pray_entries from public.hold_pray_entries;
select count(*) as mission_photo_submissions from public.mission_photo_submissions;
select count(*) as notices from public.notices;
select count(*) as inquiries from public.inquiries;

select count(*) as missing_auth_user
from public.profiles
where account_status = 'active'
  and auth_user_id is null;

select count(*) as active_raffle_for_excluded_users
from public.raffle_tickets rt
join public.profiles p on p.id = rt.profile_id
where rt.active = true
  and p.raffle_excluded = true;
```

기준.

- 최근 `migration_batches`의 `source_environment`가 `prod`여야 한다.
- `missing_auth_user`는 0이어야 한다.
- `active_raffle_for_excluded_users`는 0이어야 한다.
- 숫자가 PROD Sheet의 예상 규모와 크게 다르면 멈춘다.

## 11. 프론트 URL과 버전 확인

현재 프론트가 붙을 Supabase 프로젝트를 확인한다.

확인 파일.

- `beyond_us/app.js`.
- `beyond_us/admin.html`.

확인할 상수.

- `SUPABASE_PROJECT_URL`.
- `SUPABASE_ANON_KEY`.

버전 동기화도 확인한다.

- `beyond_us/app.js`의 `APP_VERSION`.
- `beyond_us/app.html`의 `app.css?v=...`, `app.js?v=...`.
- `beyond_us/sw.js`의 `CACHE`.
- `beyond_us/version.txt`.

네 값이 모두 같은 버전이어야 한다.

## 12. dev를 main으로 승격

권장 방식은 GitHub에서 `dev` to `main` PR을 만들고 merge하는 것이다.

로컬에서 직접 해야 한다면, main에서 코드를 수정하지 말고 merge만 한다.

```powershell
git checkout main
git pull origin main
git merge --no-ff dev
git push origin main
```

충돌이 나면 멈춘다. 특히 아래 파일 충돌은 신중히 본다.

- `beyond_us/app.js`.
- `beyond_us/admin.html`.
- `beyond_us/app.html`.
- `beyond_us/sw.js`.
- `beyond_us/version.txt`.
- `beyond_us/supabase/migrations`.

충돌 해결 후에도 버전 네 값이 같은지 다시 확인한다.

## 13. 배포 확인

main push 후 GitHub Pages 또는 Cloudflare Pages 배포가 끝날 때까지 기다린다.

확인할 것.

1. 실제 PROD URL에서 앱이 열린다.
2. `version.txt`가 최신 버전으로 보인다.
3. 브라우저 강력 새로고침 또는 PWA 재시작 후 최신 화면이 뜬다.
4. DevTools Network에서 `script.google.com` 요청이 없어야 한다.
5. Supabase `rest/v1`, `auth/v1`, `functions/v1`, `storage/v1` 요청만 보여야 한다.

## 14. 운영 smoke test

운영자 계정으로 admin 테스트.

1. admin 로그인.
2. 대시보드 로딩.
3. 앱 가입자 목록.
4. 추첨권 번호 탭.
5. 공지 목록.
6. 실물 카드 수령.
7. 개발자 문의.
8. 시스템 상태 확인.
9. 시스템 상태에서 `audit.mismatchCount`가 0인지 확인.

일반 사용자 계정으로 앱 테스트.

1. 로그인.
2. 대시보드 진입.
3. 사전미션 현황 확인.
4. 카드 컬렉션 확인.
5. 추첨권 화면 확인.
6. H&P 화면 확인.
7. BBB 사진 영역 확인.
8. 개발자 문의 작성과 조회.

기존 4자리 비밀번호 사용자 테스트.

1. 기존 비밀번호로 로그인 시도.
2. 비밀번호 변경 안내가 뜨는지 확인.
3. 6자 이상 새 비밀번호로 승격.
4. 재로그인 확인.

## 15. 서버 열기

아래 조건을 모두 만족하면 점검을 해제한다.

- admin 시스템 상태가 정상이다.
- 일반 사용자 smoke test가 통과했다.
- 기존 비밀번호 승격 흐름이 정상이다.
- Network에서 GAS 요청이 없다.
- Supabase Table Editor에서 새 이벤트와 문의가 정상 기록된다.

점검 해제 후 운영진에게 다시 사용 가능하다고 공유한다.

## 16. 전환 후 보관

- PROD Sheet 백업 사본은 삭제하지 않는다.
- PROD export JSON은 삭제하지 않는다.
- GAS Active deployment는 꺼둔다.
- Apps Script 프로젝트와 로컬 `Apps_Script` 파일은 당분간 보관한다.
- 안정화 전에는 Supabase 데이터만 임의 수정하지 않는다.

## 17. 롤백 기준

main merge 전 문제가 생긴 경우.

- main으로 올리지 않는다.
- Supabase import 문제는 백업과 JSON을 기준으로 원인 확인 후 다시 시도한다.

main merge 후 앱 진입 자체가 안 되는 경우.

- main을 직전 정상 커밋으로 되돌리거나 GitHub/Cloudflare 배포를 이전 배포로 rollback한다.
- GAS Active deployment를 다시 켤지 여부는 마지막 수단으로만 판단한다.

Supabase 데이터 정합성만 틀어진 경우.

- admin의 Supabase 파생 상태 재계산을 먼저 실행한다.
- 그래도 안 되면 `user_cards`, `user_inventory`, `user_summary`, `raffle_tickets`, `events` 중 어느 정본이 맞는지 확인한다.
- Sheet 백업과 PROD export JSON을 기준으로 비교한다.

## 18. 실행 중 멈춰야 하는 신호

- Supabase URL에 `/rest/v1/`을 붙여서 import가 실패한다.
- `missing_auth_user`가 0이 아니다.
- `active_raffle_for_excluded_users`가 0이 아니다.
- PROD export의 `sourceEnvironment`가 `prod`가 아니다.
- admin 시스템 상태에서 audit mismatch가 재계산 후에도 남는다.
- Network에 `script.google.com` 요청이 보인다.
- main merge 후 `APP_VERSION`, `version.txt`, `sw.js` cache 값이 다르다.

이 경우 서버를 열지 말고 원인을 먼저 해결한다.
