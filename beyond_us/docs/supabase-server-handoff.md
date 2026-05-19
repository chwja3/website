# Supabase 서버 변경점 핸드오프

이 문서는 다른 Codex, Claude, 또는 사람이 현재 Beyond Us 서버 전환 상태를 빠르게 이해하도록 만든 단일 인수인계 문서다. 2026-05-19 기준 DEV 브랜치와 DEV Supabase에서 검증된 내용을 기준으로 한다.

## 현재 결론

- 앱과 admin 런타임은 Google Apps Script를 더 이상 호출하지 않는다.
- 실행 중 API 경로는 Supabase Auth, Supabase Postgres RPC, Supabase Storage, Supabase Edge Functions다.
- `Apps_Script` 폴더와 과거 Sheet/GAS 문서는 삭제하지 않고 이관 기록과 복구 참고용으로만 보관한다.
- main/PROD 반영 시에는 프론트 머지뿐 아니라 Supabase SQL migration과 Edge Function 배포가 같이 필요하다.

## 프론트 런타임 경로

사용자 앱.

- 파일: `beyond_us/app.js`.
- Supabase project: `https://qjwtkvfdzpeovjabdwxv.supabase.co`.
- public anon key는 `SUPABASE_ANON_KEY` 상수로 들어가 있다. 이 값은 public key라 프론트에 있어도 된다.
- 인증은 Supabase Auth password grant를 사용한다.
- 회원가입, 닉네임 찾기, 비밀번호 재설정, 세션 profile 조회는 Edge Function `app-auth`를 호출한다.
- 기존 4자리 비밀번호 사용자는 Edge Function `legacy-password-upgrade`로 6자 이상 비밀번호 전환을 처리한다.
- 사진 업로드는 Storage bucket `beyond-us-photos`에 업로드한 뒤 RPC에 storage path를 기록한다.
- 앱 데이터 읽기와 쓰기는 `callSupabaseRpc()`로 Postgres RPC를 호출한다.

Admin.

- 파일: `beyond_us/admin.html`.
- Staff 계정도 Supabase Auth로 로그인한다.
- admin 권한은 Supabase `profiles`의 staff/dev role 기준으로 확인한다.
- 대부분의 admin action은 RPC `admin_dispatch`로 들어간다.
- 무거운 통계/재계산/감사 기능은 전용 RPC를 직접 호출한다.
- 비밀번호 초기화는 Edge Function `admin-reset-password`를 호출한다.
- GAS fallback은 없다. Supabase 함수가 빠져 있으면 조용히 GAS로 내려가지 않고 실패해야 정상이다.

## Supabase Edge Functions

위치: `beyond_us/supabase/functions`.

- `app-auth`.
  - 사용자 회원가입, session profile 확인, 닉네임 찾기, 비밀번호 재설정.
  - Service role key가 필요하다.
- `legacy-password-upgrade`.
  - 기존 GAS 비밀번호 해시와 pepper를 이용해 기존 사용자가 직접 비밀번호를 6자 이상으로 전환하게 한다.
  - 환경 변수로 기존 PASSWORD_PEPPER에 해당하는 값이 필요하다.
- `admin-reset-password`.
  - staff Supabase access token을 검증한 뒤 대상 유저의 Auth 비밀번호를 변경한다.
  - Service role key가 필요하다.

중요한 운영 원칙.

- Service role key, pepper 같은 비밀값은 repo에 커밋하지 않는다.
- Supabase Dashboard의 Edge Function Secrets에 저장한다.
- 새 PROD 프로젝트를 쓴다면 DEV와 같은 함수들을 PROD에도 배포하고 secrets를 별도로 넣어야 한다.

## Supabase SQL migrations

위치: `beyond_us/supabase/migrations`.

현재 서버 구조는 아래 파일들을 앞에서부터 순서대로 실행한 상태를 전제로 한다.

| 파일 | 역할 |
|---|---|
| `20260517000100_initial_schema.sql` | 기본 테이블, RLS, 초기 설정값, 카드/추첨권 기본 구조 |
| `20260517000200_schema_comments.sql` | Supabase Table Editor에서 보이는 테이블/컬럼 설명 |
| `20260517000300_auth_login_id_policy.sql` | 닉네임 login_id 대소문자 구분 정책 |
| `20260517000400_import_audit_tables.sql` | Sheet 원본 row 보존과 import 감사 테이블 |
| `20260517000500_legacy_auth_hashes.sql` | 기존 GAS 비밀번호 해시 보관용 테이블 |
| `20260518000100_user_app_read_rpcs.sql` | 앱 bootstrap, user status 등 읽기 RPC |
| `20260518000200_submit_pre_mission_rpc.sql` | 사전미션 제출 RPC |
| `20260518000300_user_app_write_rpcs.sql` | 카드팩, 교환, 문의 등 사용자 쓰기 RPC |
| `20260518000400_storage_hp_admin_rpcs.sql` | Storage, H&P, BBB, admin dispatch 기본 RPC |
| `20260518000500_raffle_ticket_policy_rpcs.sql` | 추첨권 정책과 번호 재사용 로직 |
| `20260518000600_admin_raffle_backfill_rpc.sql` | 추첨권 누락 검사와 보정 RPC |
| `20260518000700_notice_read_rpc.sql` | 공지 읽음 처리 RPC |
| `20260518000800_admin_dashboard_card_stats.sql` | admin 대시보드와 카드 통계 |
| `20260518000900_admin_parish_summary_axis.sql` | 교구별 주차 참여 기록 축 고정 |
| `20260518001000_admin_card_adjust_rebuild.sql` | admin 카드 수동 조정과 파생 상태 재계산 |
| `20260518001100_operational_summary_refresh.sql` | user_summary, 추첨권, 카드 상태 자동 동기화와 audit |
| `20260518001200_ops_readable_views.sql` | Table Editor에서 보기 쉬운 `ops_*` view |
| `20260518001300_admin_event_logs.sql` | admin 전체 Events 로그 조회 |
| `20260518001400_admin_attendance_sorted.sql` | 앱 가입자 목록 교구/이름 정렬과 추첨권 제외 상태 |
| `20260518001500_dev_reset_cards.sql` | DEV 개발자 계정 카드 초기화용 RPC. PROD에서는 실행하지 않는 것을 권장 |
| `20260518001600_admin_post_gas_fixes.sql` | 추첨권 번호 페이지네이션과 회수 번호 목록 보강 |

PROD에 반영할 때는 `20260518001500_dev_reset_cards.sql`을 제외할지 먼저 결정한다. 이 파일은 DEV 편의 기능이며 운영 PROD에는 필요하지 않다.

## 핵심 데이터 흐름

인증.

1. 사용자가 닉네임과 비밀번호로 로그인한다.
2. 프론트가 Supabase Auth password grant를 호출한다.
3. 성공 후 `app-auth`의 `session` action으로 `profiles` 정보를 읽는다.
4. localStorage에는 Supabase access/refresh token과 닉네임 정도만 저장한다.

앱 초기 로딩.

1. 공개 설정과 공지 일부는 `get_app_bootstrap`.
2. 로그인 유저 상태는 `get_user_status`.
3. 카드, 추첨권, 미션 진행 상태는 정본 테이블과 `user_summary` 기반으로 빠르게 읽는다.

미션과 카드.

1. 사전미션은 `submit_pre_mission`.
2. 카드팩 개봉은 `draw_card_pack`.
3. BBB/H&P/천로역정 사진은 Storage 업로드 후 `submit_mission_photo`.
4. 카드 보유 정본은 `user_cards`, 현재 카드팩 수는 `user_inventory`, 빠른 요약은 `user_summary`.
5. 정합성이 틀어지면 admin의 Supabase 파생 상태 재계산이 `admin_rebuild_user_state`를 호출한다.

추첨권.

1. 정본은 `raffle_tickets`.
2. 번호는 회수되면 재사용 가능 상태가 된다.
3. 앱 가입, 카드 3종, 카드 5종, 카드 10종 조건을 기준으로 자동 발급된다.
4. 목양교구/교회학교 또는 admin에서 추첨권 제외 체크된 유저는 기존 추첨권이 회수되고 이후 자동 발급도 막힌다.
5. admin 추첨권 번호 탭은 `admin_get_raffle_tickets`와 `adminFindRaffleTicket`을 사용한다.

Admin 시스템 상태.

- 대시보드: `admin_dashboard_summary`.
- 카드 현황: `admin_card_stats`.
- 유저와 설정: `admin_dispatch`.
- audit: `admin_audit_user_state`.
- audit의 `ok:false`는 RPC 실패가 아니라 mismatch가 있다는 뜻일 수 있다. `mismatchCount`와 `mismatches`를 먼저 본다.
- mismatch가 있으면 admin에서 Supabase 파생 상태 재계산을 실행하고 다시 상태 확인한다.

## 현재 서버에서 폐기된 것

아래는 기능 의미상 더 이상 운영 경로가 아니다.

- GAS `doGet`/`doPost` action 라우팅.
- `API_BASE`.
- `sessionToken`.
- Supabase 실패 후 GAS fallback.
- Sheet cutover용 `prodCutoverDryRun`, `prodCutoverApply`, `prodCutoverHealthCheck`.
- 기존 Sheet 기반 `UserDashboard`, `Collection`, `Events` 재계산 함수.

단, 과거 Sheet/GAS 자료는 PROD 데이터 검증이나 복구 참고로 남겨둔다.

## main/PROD 승격 절차

현재 Supabase 전환 이후 기준으로는 아래 순서를 따른다.

1. DEV 브랜치가 깨끗한지 확인한다.
   - `git status --short`.
   - 무관한 untracked 폴더는 커밋하지 않는다.
2. DEV Supabase에 필요한 SQL migration이 모두 적용되어 있는지 확인한다.
   - 현재 DEV 기준 최신은 `20260518001600_admin_post_gas_fixes.sql`.
   - PROD에는 DEV 전용 `20260518001500_dev_reset_cards.sql`을 넣을지 별도 판단한다.
3. DEV에서 smoke test를 끝낸다.
   - 앱 로그인.
   - 대시보드.
   - 공지.
   - 미션 제출.
   - 카드팩.
   - H&P.
   - BBB/사진.
   - 추첨권 번호.
   - 앱 가입자.
   - 시스템 상태 audit.
4. PROD Supabase에 DEV에서 검증된 SQL migration을 순서대로 적용한다.
5. PROD Supabase Edge Functions를 배포하고 secrets를 확인한다.
   - `app-auth`.
   - `legacy-password-upgrade`.
   - `admin-reset-password`.
6. 프론트의 Supabase project URL과 anon key가 PROD용이어야 하는지 확인한다.
   - 현재 파일에는 DEV project URL `qjwtkvfdzpeovjabdwxv`가 직접 들어가 있다.
   - DEV와 PROD가 같은 Supabase 프로젝트를 쓰는 정책이면 변경하지 않는다.
   - 별도 PROD 프로젝트를 쓸 정책이면 main 머지 전에 반드시 PROD URL/key로 분기 또는 교체한다.
7. `APP_VERSION`, `app.html` asset query, `sw.js` cache, `version.txt`가 같은 버전인지 확인한다.
8. `dev`를 `main`으로 merge 또는 PR merge한다.
9. GitHub Pages/Cloudflare Pages 배포 후 실제 PROD URL에서 smoke test한다.
10. 문제가 없으면 GAS Active deployment는 계속 꺼둔다. GAS 프로젝트 삭제는 안정화 뒤에만 한다.

## main 머지 절차가 적힌 기존 문서

현재 repo에 이미 있는 문서는 세 종류다.

- 일반 git 작업과 main 직접 작업 금지 원칙: `beyond_us/CLAUDE.md`의 `8. Git 작업 워크플로우`.
- 예전 Google Sheet/GAS 구조 개편의 PROD cutover 절차: `beyond_us/docs/sheet-restructure-plan.md`의 `3.0A — 빠른 PROD 전환 절차`.
- Supabase 데이터 최초 이관 runbook: `beyond_us/docs/supabase-data-import-plan.md`의 `PROD 한 번에 작업할 순서`.

주의할 점.

- `sheet-restructure-plan.md`의 3.0A는 GAS/Sheet cutover 기준이라 현재 Supabase-only 런타임에는 오래된 절차가 섞여 있다.
- 앞으로 다른 에이전트에게 current server state를 설명할 때는 이 문서 `beyond_us/docs/supabase-server-handoff.md`를 먼저 읽게 하는 것이 가장 안전하다.

## 다른 에이전트가 가장 먼저 볼 파일

1. `beyond_us/docs/supabase-server-handoff.md`.
2. `beyond_us/CLAUDE.md`.
3. `beyond_us/supabase/migrations` 전체 목록.
4. `beyond_us/supabase/functions/app-auth/index.ts`.
5. `beyond_us/supabase/functions/admin-reset-password/index.ts`.
6. `beyond_us/app.js`.
7. `beyond_us/admin.html`.
