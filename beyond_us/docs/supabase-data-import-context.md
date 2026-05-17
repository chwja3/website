# Supabase 데이터 이관 컨텍스트

## 배경

사용자는 DEV 데이터를 먼저 Supabase로 가져와 검증하고, 이후 PROD 서버를 잠시 닫은 상태에서 같은 절차를 한 번에 수행하려고 한다. 기존 Sheet에는 현재 상태뿐 아니라 Events, hidden legacy 로그, 사진 base64, 문의와 공지 같은 운영 데이터가 섞여 있다.

## 결정

- 모든 Google Sheet row는 정규화 여부와 관계없이 `legacy_sheet_rows`에 보관한다.
- 정규 Supabase 테이블로 변환된 row는 `legacy_import_refs`로 원본 row와 연결한다.
- 이관 중 충돌과 누락은 `migration_issues`에 남긴다.
- DEV와 PROD는 같은 스크립트와 같은 검증 쿼리를 쓴다.
- `source_environment` 값은 `dev`와 `prod` 중 하나로 고정한다.
- `Collection`, `UserDashboard`, `MissionProgress`, `DashboardStats`는 projection 또는 cache 성격이므로 원본은 보관하지만 최종 상태는 재계산한다.
- `Events`는 원장으로 이관한다. 다만 hidden legacy 로그와 비교해 Events 누락이 확인되면 보강 이벤트를 만들고 issue에 기록한다.
- `BBBPhotos` base64는 Storage로 이동하고 DB에는 storage path만 저장한다. 원본 base64는 감사 row에 보관한다.
- 기존 사용자 비밀번호 해시는 가져오지 않고, Supabase Auth 계정은 임시 랜덤 비밀번호와 `password_migration_required=true`로 만든다.

## PROD에서 한 번에 해야 할 작업

1. 서버 점검 상태 전환.
2. PROD Sheet 사본 생성.
3. Supabase migration 적용 상태 확인.
4. 원본 row 전체 적재.
5. Auth와 profiles 생성.
6. 설정, Events, 도메인 데이터, 추첨권 이관.
7. 현재 상태 재계산.
8. 검증 쿼리 통과 확인.
9. 앱과 admin endpoint 전환.
10. smoke test.
11. 점검 해제.

## 다음 구현 후보

- Sheet export는 Apps Script JSON export 함수로 확정했다. 헤더 이름과 row number를 같이 보존할 수 있고, 한글 CSV 깨짐 문제를 피할 수 있기 때문이다.
- DEV에서는 `exportSupabaseMigrationJsonDev`, PROD에서는 `exportSupabaseMigrationJsonProd`를 실행한다.
- export 함수는 Google Drive에 `beyond_us_supabase_export_<env>_YYYYMMDD_HHMMSS.json` 파일을 생성하며 Sheet 데이터는 수정하지 않는다.
- import 스크립트는 `tools/supabase_import/import_legacy_rows.mjs`에 Node로 둔다.
- 첫 import 스크립트는 정규 테이블 변환이 아니라 `migration_batches`와 `legacy_sheet_rows` 적재까지만 담당한다.
- Supabase URL과 service role key는 환경변수 `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`로만 받는다.
- DEV export의 `missingSheets`는 빈 배열로 확인됐고, `legacy_sheet_rows` 적재도 정상 완료됐다.
- 다음 변환 스크립트는 Auth 계정 생성과 사진 Storage 업로드를 제외한다. 1차 목표는 `profiles`, 설정, Events, 도메인 현재 상태 테이블을 채워 Supabase 구조 검증을 가능하게 하는 것이다.
- `import_normalized_data.mjs --dry-run` 결과 DEV 기준 target count가 생성됐고, `TabSettings`의 `qt`, `pilgrim` 중복 row 2개만 warning으로 잡혔다. 같은 key는 마지막 row 기준으로 이관한다.
- 사용자가 정규 테이블 apply 후 `migration_issues`가 `qt`, `pilgrim` 2개뿐임을 확인했다.
- DEV 검증 SQL은 `supabase/verification/20260517_dev_import_checks.sql`에 둔다. row count, 예상 밖 issue, Collection/UserDashboard/MissionProgress projection, 유저별 활성 추첨권, 추첨권 제외 유저의 활성 추첨권 잔존 여부를 확인한다.
- Auth 사용자 생성 도구는 `tools/supabase_import/create_auth_users.mjs`에 둔다. 기존 비밀번호 해시는 가져오지 않고, synthetic email과 랜덤 임시 비밀번호로 Auth 사용자를 만든 뒤 `profiles.auth_user_id`를 연결한다.
- Auth 사용자 생성은 처음에 `--login-id`로 개발자 계정 1명만 apply해서 검증한 뒤 전체 실행한다.
- 사용자가 DEV Supabase Auth 계정 생성과 `profiles.auth_user_id` 연결을 완료했다고 확인했다.
- 사용자가 `PASSWORD_PEPPER`를 찾았으므로 기존 비밀번호 유지형 전환을 지원한다.
- `legacy_auth_hashes`는 기존 GAS `pwv1$...` 해시를 임시 보관한다. 승격 성공 후 `password_hash`는 null로 지운다.
- `legacy-password-upgrade` Edge Function은 `LEGACY_PASSWORD_PEPPER` secret으로 기존 비밀번호를 검증하고, 성공 시 Supabase Auth password를 입력한 비밀번호로 업데이트한다.
- 2026-05-18. DEV 수동 호출에서 `AuthWeakPasswordError: Password should be at least 6 characters`가 확인됐다. 기존 유저 비밀번호가 전부 4자리이므로 기존 비밀번호는 본인 확인용으로만 쓰고, 검증 성공 후 6자 이상 새 비밀번호를 받아 Supabase Auth로 승격하는 흐름으로 바꾼다.
