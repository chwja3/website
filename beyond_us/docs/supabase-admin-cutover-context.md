# Supabase Admin 전환 컨텍스트

2026-05-18. admin 화면은 `shouldUseSupabaseAdmin()`에서 Supabase 세션이 있으면 `admin_dispatch`를 먼저 호출하고 실패하면 GAS로 fallback하는 구조였다. 이 때문에 운영자는 작업이 성공한 것처럼 보여도 실제로는 Google Sheet에만 쓰일 수 있었다.

공지 등록의 직접 문제는 이미지 파일이 있는 경우였다. `postNotice` payload에 `imageFiles`가 있으면 `shouldUseSupabaseAdmin()`이 Supabase 경로를 건너뛰도록 되어 있어서, 이미지 공지는 항상 GAS Drive 업로드와 Sheet 저장으로 빠졌다.

이번 수정은 공지 흐름을 먼저 Supabase로 고정한다. 이미지는 `beyond-us-photos` Storage bucket의 `notices/` 아래에 업로드하고, `notices.image_path`에는 Storage path 배열 JSON을 저장한다. 읽을 때는 path를 public URL로 변환한다.

admin 쓰기 RPC는 Supabase access token이 있어야 호출할 수 있다. 기존 admin 비밀번호 로그인은 Supabase token을 만들지 않으므로, 공지 쓰기에서 token이 없으면 GAS로 fallback하지 않고 명시적으로 세션 필요 오류를 보여준다. admin 로그인 자체를 Supabase Auth 기반으로 바꾸는 것은 별도 작업이다.

현재 `admin_dispatch`가 지원하지 않아 GAS에 남아있는 주요 action은 `adminLogin`, `adminResetPassword`, `getCardStats`, `adminSetupBBBMatching`, `adminCreateCardEvent`, `adminRebuildEventDerivedViews`, `prodCutoverHealthCheck`, `prodCutoverDryRun`, `prodCutoverApply`다. `prodCutover*`는 Sheet 전환용이므로 Supabase 최종 전환 뒤 폐기 후보이고, `adminSetupBBBMatching`은 조별, 티어 기반 BBB 매칭 재설계와 함께 다시 잡아야 한다.

2026-05-18. admin 페이지에 일반 사용자 Supabase token이 남아 있으면 `admin_dispatch`가 401을 반환하고 GAS fallback으로 내려가는 문제가 있었다. access token 존재만으로 admin RPC를 시도하지 않고, DEV 계정 힌트나 `?supabaseAdmin=1` 명시 플래그가 있을 때만 Supabase admin 경로를 타도록 제한했다. 401이 한 번 발생하면 해당 페이지 세션에서는 Supabase admin 시도를 멈춘다.

2026-05-18. admin 로그인 폼을 Supabase Auth 기반으로 전환했다. 관리자는 닉네임과 계정 비밀번호를 입력하고, 프론트는 앱과 같은 synthetic email 규칙으로 Supabase Auth password grant를 호출한다. 로그인 직후 `admin_dispatch('getUsers')`를 한 번 호출해 `bu_admin_profile()` 권한 검사를 통과한 경우에만 admin 화면에 진입한다. 닉네임을 비워두면 기존 GAS 관리자 비밀번호 로그인도 임시 fallback으로 유지한다.

2026-05-18. admin 프론트의 Supabase 경로는 `admin_dispatch`에 실제 구현된 action만 사용하도록 제한했다. 아직 GAS에 남은 기능을 Supabase로 보내면 unknown action과 legacy password fallback이 섞여 원인 파악이 어려워지기 때문이다.
