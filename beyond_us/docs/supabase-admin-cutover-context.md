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
