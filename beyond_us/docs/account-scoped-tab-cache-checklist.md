# 계정별 탭 캐시 버그 체크리스트

- [x] 로그아웃 시 account-scoped 메모리와 DOM 초기화.
- [x] 다른 계정 로그인 시 H&P, BBB, 천로역정 상태 초기화.
- [x] H&P 로더에 loadedFor 계정 가드 추가.
- [x] H&P localStorage 정답과 힌트 키를 계정별로 분리.
- [x] BBB 로더에 loadedFor/loadingFor 계정 가드 추가.
- [x] BBB와 천로역정 DOM 초기화 함수 추가.
- [x] 로그인 후 H&P와 BBB 지연 prefetch 추가.
- [x] 프론트 버전 동기화.
- [x] 문법 검사와 diff 확인.
