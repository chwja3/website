# GAS 제거 체크리스트

- [x] 남은 GAS 호출 지점을 확인한다.
- [x] 사용자 앱의 GAS helper와 fallback을 제거한다.
- [x] 사용자 앱 인증은 Supabase primary만 사용하게 정리한다.
- [x] admin 공통 `get`/`post`에서 GAS fallback을 제거한다.
- [x] 캐시 버전을 갱신한다.
- [x] 문서에 GAS 제거 상태와 남은 백업 보관 방침을 기록한다.
- [x] 문법과 diff 검사를 실행한다.
- [x] 커밋하고 `dev`에 푸시한다.
