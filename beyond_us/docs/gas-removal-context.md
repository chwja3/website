# GAS 제거 컨텍스트

2026-05-18. 직전 작업에서는 DEV 환경의 GAS fallback을 차단했지만, `app.js`와 `admin.html`에는 PROD fallback 코드와 GAS helper가 남아 있었다. 이번 작업은 차단이 아니라 제거다.

2026-05-18. 앱과 admin의 실사용 데이터 경로는 이미 Supabase Auth, RPC, Storage, Edge Function 기준으로 전환됐다. 따라서 `script.google.com` URL, `API_BASE`, GAS GET/POST helper, Supabase 실패 후 GAS fallback은 더 이상 유지하지 않는다.

2026-05-18. `Apps_Script` 파일과 과거 문서는 삭제하지 않는다. 이유는 PROD Sheet 이관 기록, 기존 export 함수, 운영 복구 참고 자료로만 가치가 있기 때문이다. 다만 프론트 런타임 경로에서는 참조하지 않는다.

2026-05-18. `app.js`에서 `API_BASE`, GAS helper, Supabase 실패 후 fallback, `sessionToken` 기반 자동 로그인 검증을 제거했다. 인증, 회원가입, 닉네임 찾기, 비밀번호 재설정, 사용자 데이터 읽기와 쓰기는 Supabase Auth, `app-auth`, RPC만 사용한다.

2026-05-18. `admin.html`에서 `API_BASE`와 공통 `get`/`post`의 fallback fetch를 제거했다. 지원하지 않는 action은 `unsupported_admin_action:*`으로 즉시 실패하며, 지원 action은 `admin_dispatch` 또는 전용 admin RPC/Edge Function만 호출한다.

2026-05-18. `CLAUDE.md`의 현재 아키텍처 설명을 Supabase 기준으로 갱신했다. 기존 `Apps_Script`는 런타임이 아니라 이관 기록과 백업 소스라고 명시했다.

2026-05-18. 제거 후 `app.js` 문법 검사, `admin.html` 인라인 스크립트 문법 검사, `git diff --check`를 통과했다. `app.js`와 `admin.html`에서는 `API_BASE`, `script.google.com`, `fetchGas`, `sessionToken` 기반 GAS 경로가 더 이상 검색되지 않는다.
