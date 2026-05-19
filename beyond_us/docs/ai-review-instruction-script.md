# 다른 AI에게 전달할 수정사항 확인 지시문

아래 내용을 Claude, Codex, 또는 다른 AI에게 그대로 붙여넣으면 된다. 목적은 Beyond Us 프로젝트의 최근 Supabase 전환, GAS 제거, main 전환 절차를 문서 기준으로 정확히 이해하게 한 뒤, 누락이나 위험 요소가 있는지 검토하게 하는 것이다.

```text
너는 Beyond Us 프로젝트의 인수인계/검토 담당 AI다.

목표는 최근 수정사항을 새로 구현하는 것이 아니라, 문서를 읽고 현재 서버 전환 상태와 main 반영 절차를 정확히 이해한 뒤 검토 의견을 주는 것이다. 아직 코드를 수정하지 말고, 먼저 아래 문서들을 순서대로 읽어라.

작업 위치.

C:\Users\jkjk9\OneDrive\Documents\00_Work\01_AGC\AGC\2026_Youth_treat\website

먼저 읽을 문서.

1. beyond_us\docs\supabase-server-handoff.md
   - 현재 서버 구조와 Supabase 전환 상태의 기준 문서다.
   - GAS 제거 후 런타임 경로, Edge Functions, SQL migrations, 데이터 흐름, 폐기된 기능을 파악해라.

2. beyond_us\docs\supabase-main-cutover-runbook.md
   - main/PROD 전환일에 사람이 그대로 따라야 하는 최신 실행 절차다.
   - 서버를 닫고 진행할 순서, SQL 적용 범위, Edge Function secrets, import 절차, smoke test, rollback 기준을 확인해라.

3. beyond_us\docs\gas-removal-plan.md
4. beyond_us\docs\gas-removal-context.md
5. beyond_us\docs\gas-removal-checklist.md
   - 앱/admin 런타임에서 GAS가 어떻게 제거됐는지 확인해라.
   - `Apps_Script`는 복구 참고용으로만 남아 있고, 런타임에서 참조하면 안 된다는 점을 확인해라.

6. beyond_us\docs\admin-post-gas-fixes-plan.md
7. beyond_us\docs\admin-post-gas-fixes-context.md
8. beyond_us\docs\admin-post-gas-fixes-checklist.md
   - GAS 제거 이후 admin에서 보정한 항목을 확인해라.
   - 추첨권 번호 탭, 비밀번호 초기화 목록 정렬, 시스템 상태 audit 처리 방식을 확인해라.

9. beyond_us\docs\supabase-data-import-plan.md
10. beyond_us\docs\supabase-data-import-context.md
11. beyond_us\docs\supabase-data-import-checklist.md
   - 기존 Sheet 데이터를 Supabase로 옮기는 흐름과 PROD 이관 시 주의사항을 확인해라.

12. beyond_us\docs\supabase-admin-cutover-plan.md
13. beyond_us\docs\supabase-admin-cutover-context.md
14. beyond_us\docs\supabase-admin-cutover-checklist.md
   - admin 기능이 GAS에서 Supabase로 전환된 흐름을 확인해라.
   - 단, 이 문서 중 일부는 전환 중간 단계의 기록이므로 최신 기준은 `supabase-server-handoff.md`와 `supabase-main-cutover-runbook.md`를 우선한다.

15. beyond_us\docs\supabase-gas-action-inventory.md
   - GAS action 중 폐기된 것과 Supabase로 옮긴 기능을 확인해라.

필요하면 같이 볼 코드와 SQL.

1. beyond_us\app.js
   - `script.google.com`, `API_BASE`, `fetchGas`, `sessionToken` 기반 GAS 호출이 남아 있으면 안 된다.
   - Supabase Auth, RPC, Storage, Edge Function 호출 구조를 확인해라.

2. beyond_us\admin.html
   - admin 공통 get/post가 GAS fallback 없이 Supabase `admin_dispatch` 또는 전용 RPC/Edge Function만 호출해야 한다.
   - 시스템 상태 audit에서 `ok:false`를 RPC 실패로 오해하지 않고 mismatch 결과로 표시하는지 확인해라.

3. beyond_us\supabase\migrations
   - `20260517000100_initial_schema.sql`부터 `20260518001600_admin_post_gas_fixes.sql`까지의 역할을 파악해라.
   - `20260518001500_dev_reset_cards.sql`은 DEV 전용이므로 PROD 기본 적용 대상이 아니라는 점을 확인해라.

4. beyond_us\supabase\functions\app-auth\index.ts
5. beyond_us\supabase\functions\legacy-password-upgrade\index.ts
6. beyond_us\supabase\functions\admin-reset-password\index.ts
   - 필요한 secret과 service role 사용 범위를 확인해라.

검토할 핵심 질문.

1. main/PROD 전환 절차가 현재 Supabase-only 구조와 일치하는가?
2. 아직 오래된 GAS/Sheet cutover 절차를 최신 절차로 착각할 위험이 있는가?
3. PROD에 적용하면 안 되는 DEV 전용 SQL이나 테스트 경로가 문서에 명확히 분리되어 있는가?
4. Supabase 프로젝트 URL과 anon key가 DEV/PROD 정책에 맞게 확인하도록 되어 있는가?
5. Edge Function secrets 중 누락되면 치명적인 값이 문서에 적혀 있는가?
6. Sheet export, import, Auth 계정 생성, legacy password hash import 순서가 실행 가능한가?
7. 전환 후 smoke test와 rollback 기준이 충분히 구체적인가?
8. 앱/admin 런타임에서 GAS 요청이 다시 발생할 가능성이 남아 있는가?

검토 결과는 아래 형식으로 답해라.

1. 현재 구조 요약.
2. main/PROD 전환 절차 요약.
3. 반드시 지켜야 할 중단 조건.
4. 누락 또는 위험 요소.
5. 수정 제안. 단, 사용자가 명시적으로 요청하기 전에는 파일을 수정하지 마라.
6. PROD 전환일에 사람이 체크해야 할 최종 체크리스트.

중요한 규칙.

- `supabase-server-handoff.md`와 `supabase-main-cutover-runbook.md`를 최신 기준으로 본다.
- `sheet-restructure-plan.md`의 GAS/Sheet cutover 절차는 과거 절차가 섞여 있으므로 최신 기준으로 쓰지 않는다.
- 문서만 보고 확신하기 어려운 부분은 코드나 SQL에서 실제 호출 경로를 확인해라.
- 무언가를 수정하기 전에 반드시 사용자에게 먼저 보고하고 승인받아라.
```
