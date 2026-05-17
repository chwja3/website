# Supabase 전환 컨텍스트

## 배경

현재 Beyond Us 앱은 `app.html`, `app.js`, `admin.html`이 GAS Web App을 호출하고, GAS가 Google Sheet를 데이터베이스처럼 사용한다. 최근 Events, Collection, UserDashboard, RaffleTickets, BBBPhotos, MissionProgress 같은 보조 시트가 늘어나면서 조회와 집계가 무거워졌다.

## 결정

- Supabase 전환은 단순 DB 교체가 아니라 GAS 서버 로직 제거까지 포함한다.
- 기존 HTML 구조와 디자인은 최대한 유지한다.
- 프론트에서 직접 테이블을 많이 읽는 방식보다, 보안과 집계를 위해 RPC 또는 Edge Function을 중심으로 둔다.
- 유저 화면은 `get_user_status` 같은 통합 API를 사용한다.
- 관리자 화면은 admin 전용 RPC와 view를 사용한다.
- 기존 GAS의 마이그레이션, cutover, Phase 2E 진단 action은 Supabase 이후 의미가 없어지므로 폐기 대상으로 둔다.
- 첫 migration은 `beyond_us/supabase/migrations/20260517000100_initial_schema.sql`에 작성했다.
- 첫 migration은 핵심 테이블, enum, 기본 seed, 인덱스, RLS 활성화까지 포함한다.
- 테이블과 주요 컬럼 설명은 `beyond_us/supabase/migrations/20260517000200_schema_comments.sql`에서 `COMMENT ON`으로 별도 관리한다.
- Auth 전환 방식은 `beyond_us/docs/supabase-auth-strategy.md`에 정리했다.
- 사용자 화면은 아이디와 비밀번호 입력을 유지하되, 내부적으로는 `sha256(trim(login_id))` 기반 synthetic email로 Supabase Auth email/password 로그인을 사용한다.
- `profiles.login_id`는 대소문자를 구분하는 `text`로 고정한다. 이를 위해 `beyond_us/supabase/migrations/20260517000300_auth_login_id_policy.sql`을 추가했다.
- 관리자 로그인은 `ADMIN_PASSWORD` 공유 방식에서 Supabase Auth 계정과 `profiles.role` 기반 권한 확인으로 전환한다.
- 기존 Sheet 비밀번호 해시는 Supabase Auth로 직접 변환하지 않고, 이관 계정은 `password_migration_required=true` 상태에서 사용자 재설정 흐름으로 새 비밀번호를 설정하게 한다.
- 기존 Sheet 데이터와 로그 이관 순서는 `beyond_us/docs/supabase-data-import-plan.md`에 분리했다.
- Google Sheet 원본 row는 `legacy_sheet_rows`에 보관하고, 변환 대상과 연결은 `legacy_import_refs`에 남긴다. 감사 테이블은 `beyond_us/supabase/migrations/20260517000400_import_audit_tables.sql`에서 만든다.
- DEV Sheet를 먼저 이관해 검증한 뒤, PROD는 서버 점검 상태에서 같은 절차를 한 번에 수행한다.
- 실제 접근 정책은 다음 RLS migration에서 작성한다. 따라서 이 migration만 적용하면 service role 외 클라이언트 접근은 아직 막혀 있는 상태가 정상이다.
- 2026-05-18. DEV Sheet 데이터는 Supabase 정규 테이블로 가져오는 도구와 검증 쿼리가 준비되어 있지만, 앱과 admin의 실제 읽기/쓰기는 아직 GAS `API_BASE`를 사용한다.
- 2026-05-18. 첫 API 전환은 사용자 앱의 `dashboard`, `userStatus` 읽기부터 진행한다. RPC가 실패하거나 Supabase 세션이 없으면 기존 GAS로 fallback해 DEV 앱이 깨지지 않게 한다.
- 2026-05-18. `dashboard`, `userStatus` Supabase 읽기 RPC를 추가했다. 아직 쓰기 action은 GAS에 남아 있으므로 DEV 앱 기본값은 GAS이고, `?supabaseData=1` 또는 `localStorage.beyondus_supabase_data_read=1` 상태에서만 Supabase 읽기를 먼저 시도한다.
- 2026-05-18. 첫 쓰기 전환으로 `submit_pre_mission` RPC를 추가했다. `?supabaseData=1` 상태에서 사전미션 제출은 Supabase를 먼저 호출하고, 실패하면 기존 GAS `submit`으로 fallback한다. RPC는 클라이언트 score를 신뢰하지 않고 `mission_items`의 활성 항목과 점수를 기준으로 저장 항목, 저장 인덱스, 새 점수, 주차 누적 점수를 다시 계산한다.

## 주요 리스크

- 기존 비밀번호 평문 또는 해시 방식에서 Supabase Auth로 넘어가는 계정 이관 전략이 필요하다.
- Google Sheet의 대소문자 민감 ID 문제를 Supabase에서는 `login_id` 유니크 정책으로 명확히 정해야 한다.
- 현재 앱은 `nickname`을 user id처럼 사용하므로, 내부 UUID와 표시용 아이디를 분리해야 한다.
- 사진 base64를 DB에 저장하면 성능과 비용이 악화되므로 Storage 이전이 필요하다.
- Events와 현재 상태 테이블의 동기화 규칙을 명확히 잡아야 한다.
