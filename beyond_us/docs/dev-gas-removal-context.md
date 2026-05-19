# DEV GAS 제거 컨텍스트

2026-05-18. DEV Supabase SQL 014까지 실행했고 admin 주요 기능이 Supabase 기준으로 동작함을 확인했다. 다음 단계는 DEV에서 GAS fallback을 유지하지 않는 것이다. 아직 `app.js`와 `admin.html`에는 PROD 백업을 위한 GAS 코드가 남아 있으므로, DEV 런타임에서만 `API_BASE`를 비워 실제 요청이 나가지 않게 한다.

2026-05-18. 완전 삭제 대신 DEV 차단을 먼저 선택한다. PROD/main 전환 전까지는 PROD가 GAS 백업 경로를 쓸 수 있기 때문이다. DEV에서는 Supabase RPC 누락이나 오류가 있으면 즉시 드러나야 하므로 fallback을 허용하지 않는다.

2026-05-18. 사용자 앱과 admin 모두 DEV에서는 `API_BASE`를 빈 문자열로 두고, 공통 GAS helper 진입 시 `dev_gas_disabled` 오류를 던지도록 막았다. Supabase RPC 실패 후 GAS로 내려가던 `apiClient`, admin `get`/`post` fallback은 DEV에서 원래 오류를 그대로 드러낸다. DEV 전용 카드 초기화 버튼은 GAS `devResetCards` 대신 Supabase RPC `dev_reset_my_cards`를 호출한다.

2026-05-18. `20260518001500_dev_reset_cards.sql`을 추가했다. 이 SQL은 개발자 계정에서만 자기 카드, 카드팩, 카드 보유 조건 추첨권을 Supabase 기준으로 초기화한다. DEV Supabase SQL Editor에서 이 migration까지 실행해야 앱의 DEV 카드 초기화 버튼이 동작한다.
