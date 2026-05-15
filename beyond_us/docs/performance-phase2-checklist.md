# 성능 최적화 2차 체크리스트

- [x] 현재 초기 진입과 상태 조회 호출 흐름 확인.
- [x] GAS에 `userStatusLite` 엔드포인트 추가.
- [x] 앱 기본 `loadUserStatus`가 `userStatusLite`를 사용하도록 수정.
- [x] 추첨권 상세는 전체 `userStatus`로 지연 보강.
- [x] 로그인 직후 `loadTrades`와 feature preload를 지연 처리.
- [x] B.B.B 메시지 로드를 기본 B.B.B 화면 렌더 뒤로 분리.
- [x] `images/unused` 배포 제외 설정 추가.
- [x] 프론트 버전 동기화.
- [x] 문법 검증과 diff 검토.
