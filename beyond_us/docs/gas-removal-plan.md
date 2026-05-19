# GAS 제거 계획

앱과 admin의 실행 경로에서 Google Apps Script 호출을 제거하고 Supabase Auth, RPC, Edge Function만 남긴다. 기존 `Apps_Script` 파일과 과거 문서는 백업과 이관 기록으로 보관하되, 프론트 런타임은 더 이상 `script.google.com`으로 요청하지 않는다.

1. 사용자 앱에서 `API_BASE`, GAS helper, GAS fallback, `sessionToken` 기반 자동 로그인 검증을 제거한다.
2. 사용자 앱 인증은 Supabase primary 흐름만 사용한다.
3. admin 공통 `get`/`post`는 Supabase `admin_dispatch`만 호출하게 한다.
4. 캐시 버전을 갱신하고 관련 문서를 최신 상태로 기록한다.
5. 정적 문법 검사와 diff 검사를 통과시킨 뒤 커밋하고 `dev`에 푸시한다.

성공 기준.

- `app.js`와 `admin.html`에 `script.google.com`, `API_BASE`, `fetchGas`, `dev_gas_disabled`, `using PROD GAS fallback`이 남지 않는다.
- DEV와 향후 main 모두 앱/admin 실행 중 GAS 요청을 만들 수 없다.
- Supabase 미구현 action은 조용한 GAS fallback 없이 명시적으로 실패한다.
