# DEV GAS 제거 계획

DEV 환경에서는 사용자 앱과 admin이 Google Apps Script로 내려가지 않도록 모든 GAS 경로를 차단한다. PROD는 아직 별도 전환 전이므로 코드상 fallback 경로를 보존하되, DEV 런타임에서는 사용할 수 없게 한다.

1. DEV에서 `API_BASE`를 비워 GAS URL이 노출되거나 호출되지 않게 한다.
2. 사용자 앱의 GAS helper는 DEV에서 즉시 `dev_gas_disabled` 오류를 던지게 한다.
3. DEV 전용 카드 초기화는 Supabase RPC로 대체한다.
4. admin 공통 `get`/`post`도 DEV에서는 Supabase 실패 후 GAS로 fallback하지 않게 한다.
5. 캐시 버전을 갱신하고 정적 검사를 통과시킨다.

성공 기준.

- DEV host에서 `script.google.com` 요청이 발생하지 않는다.
- Supabase RPC가 빠져 있거나 실패하면 DEV 화면은 오류를 드러내고 GAS로 조용히 내려가지 않는다.
- PROD용 GAS URL과 fallback은 main 전환 전까지 보존한다.
