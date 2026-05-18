# Supabase Admin 전환 컨텍스트

2026-05-18. admin 화면은 `shouldUseSupabaseAdmin()`에서 Supabase 세션이 있으면 `admin_dispatch`를 먼저 호출하고 실패하면 GAS로 fallback하는 구조였다. 이 때문에 운영자는 작업이 성공한 것처럼 보여도 실제로는 Google Sheet에만 쓰일 수 있었다.

공지 등록의 직접 문제는 이미지 파일이 있는 경우였다. `postNotice` payload에 `imageFiles`가 있으면 `shouldUseSupabaseAdmin()`이 Supabase 경로를 건너뛰도록 되어 있어서, 이미지 공지는 항상 GAS Drive 업로드와 Sheet 저장으로 빠졌다.

이번 수정은 공지 흐름을 먼저 Supabase로 고정한다. 이미지는 `beyond-us-photos` Storage bucket의 `notices/` 아래에 업로드하고, `notices.image_path`에는 Storage path 배열 JSON을 저장한다. 읽을 때는 path를 public URL로 변환한다.

admin 쓰기 RPC는 Supabase access token이 있어야 호출할 수 있다. 기존 admin 비밀번호 로그인은 Supabase token을 만들지 않으므로, 공지 쓰기에서 token이 없으면 GAS로 fallback하지 않고 명시적으로 세션 필요 오류를 보여준다. admin 로그인 자체를 Supabase Auth 기반으로 바꾸는 것은 별도 작업이다.

현재 `admin_dispatch`가 지원하지 않아 GAS에 남아있는 주요 action은 `adminLogin`, `adminResetPassword`, `getCardStats`, `adminSetupBBBMatching`, `adminCreateCardEvent`, `adminRebuildEventDerivedViews`, `prodCutoverHealthCheck`, `prodCutoverDryRun`, `prodCutoverApply`다. `prodCutover*`는 Sheet 전환용이므로 Supabase 최종 전환 뒤 폐기 후보이고, `adminSetupBBBMatching`은 조별, 티어 기반 BBB 매칭 재설계와 함께 다시 잡아야 한다.

2026-05-18. admin 페이지에 일반 사용자 Supabase token이 남아 있으면 `admin_dispatch`가 401을 반환하고 GAS fallback으로 내려가는 문제가 있었다. access token 존재만으로 admin RPC를 시도하지 않고, DEV 계정 힌트나 `?supabaseAdmin=1` 명시 플래그가 있을 때만 Supabase admin 경로를 타도록 제한했다. 401이 한 번 발생하면 해당 페이지 세션에서는 Supabase admin 시도를 멈춘다.

2026-05-18. admin 로그인 폼을 Supabase Auth 기반으로 전환했다. 공용 관리자 비밀번호를 공유하지 않고, staff로 체크된 사람이 자기 앱 아이디와 비밀번호로 admin에 로그인한다. Sheet 이관 스크립트는 `Users.isStaff=true`를 `profiles.role='admin'`으로 변환하므로, 로그인 직후 `admin_dispatch('getUsers')`를 호출해 `bu_admin_profile()` 권한 검사를 통과한 경우에만 admin 화면에 진입한다. 아직 Supabase Auth 비밀번호 업그레이드를 하지 않은 staff 계정은 앱에서 6자 이상 비밀번호 업데이트를 먼저 해야 한다.

2026-05-18. admin 프론트의 Supabase 경로는 `admin_dispatch`에 실제 구현된 action만 사용하도록 제한했다. 아직 GAS에 남은 기능을 Supabase로 보내면 unknown action과 legacy password fallback이 섞여 원인 파악이 어려워지기 때문이다.

2026-05-18. staff 계정 로그인 전환 뒤 admin 대시보드와 실물 카드 수령에서 누락이 확인됐다. 원인은 `dashboard` action이 사용자 앱용 `get_app_bootstrap()`을 반환해서 admin 화면이 기대하는 교구별, 주차별 summary 필드가 비어 있었고, `setCardReceivedQty`가 프론트의 Supabase admin action 허용 목록에서 빠져 GAS fallback으로 내려갔기 때문이다. `admin_dashboard_summary()`와 `admin_card_stats()` RPC를 추가하고, 실물 카드 수령 쓰기는 기존 `admin_dispatch('setCardReceivedQty')`로 보내도록 연결했다. 공지 이미지 업로드는 SVG처럼 Storage 업로드에서 400이 날 수 있는 입력을 PNG로 rasterize한 뒤 업로드하도록 보강했다.

2026-05-18. admin 교구 참여 현황은 참여자가 있는 교구만 점수순으로 내려오면 운영자가 비교하기 어렵다. `admin_dashboard_summary()`를 다시 갱신해 이번 주 및 주차별 교구 참여 기록 모두 `1청`, `2청`, `3청`, `4청`, `VIP`, `교회학교/목양교구` 축을 먼저 고정하고, 참여자가 0명이어도 빈 카드와 빈 상세 표가 보이도록 했다. 기타 교구가 실제로 있으면 고정 축 아래에 추가로 붙인다.

2026-05-18. 남은 GAS 의존을 다시 분류했다. 운영 기능으로 계속 필요한 것은 유저 비밀번호 초기화, 카드 수동 지급과 회수, Supabase 파생 상태 재계산이다. Sheet cutover용 `prodCutoverDryRun`, `prodCutoverApply`, `prodCutoverHealthCheck`는 Supabase 전환 후 새 DB 운영에는 의미가 없으므로 옮기지 않고 폐기 후보로 둔다. 기존 `adminSetupBBBMatching`도 무작위 매칭 방식이라 조별, 티어 기반 BBB 매칭 재설계 때 새로 구현한다.

2026-05-18. `admin_adjust_card` RPC를 추가해 admin 카드 추가와 삭제가 `user_cards`, `events`, `user_summary`를 직접 갱신하게 했다. `admin_rebuild_user_state` RPC는 현재 Supabase 테이블 기준으로 활성 유저의 `user_summary`와 추첨권 정책 상태를 다시 맞춘다. 비밀번호 초기화는 `admin-reset-password` Edge Function으로 분리했다. 이 함수는 staff admin의 Supabase access token을 검증한 뒤 대상 유저의 Supabase Auth 비밀번호를 Auth Admin API로 변경한다. admin 시스템 상태 패널은 더 이상 Sheet cutover GAS를 호출하지 않고 Supabase RPC 상태만 확인한다.

2026-05-18. 운영 안정성 기준을 `정본 테이블 + Events 감사 로그`로 확정했다. 앱과 admin의 평상시 읽기는 `user_cards`, `user_inventory`, `mission_progress`, `raffle_tickets`, `user_summary`를 기준으로 하고, `events`는 추적과 감사 로그로 남긴다. 이를 위해 `20260518001100_operational_summary_refresh.sql`을 추가했다. 이 migration은 `user_cards`, `mission_submissions`, `raffle_tickets`, `trades`, `events`, `profiles` 변경 후 `user_summary`를 자동 refresh하고, 카드 보유 조건이 깨졌을 때 `card_3`, `card_5`, `card_10` 추첨권을 회수해 번호 풀로 되돌린다.

2026-05-18. Supabase Table Editor 운영 가독성을 위해 `20260518001200_ops_readable_views.sql`을 추가했다. 원본 테이블에 `login_id`를 복제하지 않고 `ops_*` view에서 `profiles`를 join해 닉네임, 이름, 교구를 바로 보여준다. 시간 컬럼이 있는 view는 최신 행이 위에 오도록 정렬한다. admin에서는 별도 `시스템 상태` 메뉴를 제거하고 `Events·시스템` 탭 안에 상태 확인을 통합했다. Supabase 운영에서 더 이상 의미가 없는 Sheet 전환 도구와 관련 JS 함수는 제거했다.

2026-05-18. DEV 앱과 admin에서는 GAS fallback을 차단했다. DEV `API_BASE`는 빈 문자열이며, Supabase 실패 시 GAS로 내려가지 않고 원래 오류를 드러낸다. PROD/main 전환 전까지 PROD GAS fallback 코드는 보존하되 DEV 런타임에서는 사용할 수 없다.

2026-05-18. admin 개발자 메뉴에 `Event 로그` 탭을 추가했다. `20260518001300_admin_event_logs.sql`이 staff 권한을 확인하는 `admin_event_logs` RPC를 제공하고, admin은 이 RPC로 최신순 이벤트 로그를 읽는다. 조회 UI는 이벤트 타입 필터, 닉네임/이름/ref/request 검색, 표시 개수 제한, payload 펼쳐보기를 제공한다.

2026-05-18. admin `앱 가입자` 탭의 목록 정렬을 생성일순에서 교구/이름순으로 바꾸기 위해 `20260518001400_admin_attendance_sorted.sql`을 추가했다. 기존 `admin_dispatch('adminGetRaffleAttendance')`는 서버에서 `created_at desc`로 limit을 먼저 적용하므로, 새 RPC `admin_get_raffle_attendance`가 교구 고정 순서와 이름순 정렬을 적용한 뒤 limit을 적용한다.
