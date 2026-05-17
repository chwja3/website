# Supabase 쓰기 전환 Context

2026-05-18. 사전미션 제출 `submit_pre_mission`이 DEV에서 실제 갱신 확인되었다. 다음 요청은 남은 쓰기 전체 전환이지만, 사진 업로드는 Storage bucket과 public/private URL 정책이 필요하고 admin 쓰기는 Supabase Auth role 기반 권한 확인이 필요하다. 따라서 이번 묶음은 사용자 앱의 비파일, 비admin 쓰기 중 Supabase 현재 테이블로 정합성을 닫을 수 있는 경로를 우선 전환한다.

이번 묶음에 포함하는 경로는 카드팩 개봉, 교환, 개발자 문의, BBB 메시지, 시크릿버디 추측이다. 각 경로는 쓰기 후 같은 Supabase 데이터가 다시 보이도록 필요한 읽기 RPC도 함께 추가한다.

2026-05-18. `20260518000300_user_app_write_rpcs.sql`에 사용자 앱 비파일 쓰기 RPC를 추가했다. 포함 범위는 `draw_card_pack`, `get_public_collection`, `get_user_trades`, `request_trade`, `accept_trade`, `reject_trade`, `cancel_trade`, `pray_for_trade`, `get_my_inquiries`, `create_inquiry`, `update_inquiry`, `delete_inquiry`, `get_bbb_messages`, `send_bbb_message`, `guess_bbb_secret`이다. 앱은 `?supabaseData=1` 상태에서 이 RPC들을 먼저 호출하고 실패 시 GAS로 fallback한다.

사진 업로드, H&P 추측과 힌트, admin 쓰기는 아직 GAS에 남긴다. 사진은 Storage 정책이 필요하고, H&P는 `getHoldPray`의 카드 선택/정답 매칭을 Supabase 기준으로 먼저 고정해야 하며, admin은 role 기반 Auth 전환 없이는 `ADMIN_PASSWORD` fallback과 권한 모델이 섞인다.
