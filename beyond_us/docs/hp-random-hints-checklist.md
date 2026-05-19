# H&P 랜덤 노출과 자동 초성 힌트 체크리스트

- [x] H&P RPC가 사용자 본인 기도제목을 제외한다.
- [x] H&P RPC가 사용자/주차별 deterministic random 3장만 반환한다.
- [x] 이름 맞히기 RPC가 같은 3장 기준 card index를 사용한다.
- [x] 힌트 RPC가 이름 초성을 즉시 반환한다.
- [x] 앱이 오래된 H&P 캐시를 무효화한다.
- [x] 앱이 초성 힌트를 즉시 표시한다.
- [x] 문법, 버전, SQL shape 검사를 실행한다.
- [ ] main에 커밋/푸시한다.
- [ ] PROD SQL migration 적용 후 RPC를 검증한다.
