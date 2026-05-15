# 성능 최적화 2차 Context

## 관찰

- `loadUserStatus()`는 앱에서 자주 호출되지만 서버의 `getUserStatus()`는 미션, Collection, 추첨권, 유저, 참석자 데이터를 한 번에 읽는다.
- 카드팩 버튼과 Collection 렌더링에는 추첨권 전체 행 스캔이 필요하지 않다.
- 로그인 직후 `syncInitialData()`는 `loadAll`, `loadNotices`, `loadUserStatus`, `loadTrades`를 동시에 시작하고, 짧은 시간 뒤 H&P와 B.B.B 예열도 시작한다.
- `loadBBB()`는 B.B.B 기본 데이터와 메시지 데이터를 동시에 기다린 뒤 화면을 갱신한다.

## 결정

- 기본 상태 조회는 `userStatusLite`로 바꾸고, 전체 추첨권 정보는 별도 전체 상태 조회로 보강한다.
- 기존 `userStatus` 엔드포인트는 그대로 유지해 호환성과 운영 안정성을 지킨다.
- B.B.B 메시지는 기본 미션 화면이 뜬 뒤 백그라운드로 가져온다.
- `images/unused`는 사용자가 밖으로 빼기 전까지라도 Cloudflare Pages 배포 대상에서 제외되도록 설정한다.

## 구현 메모

- `userStatusLite`는 Collection 스냅샷과 미션 진행 상태를 우선 사용하고, 추첨권 전체 번호 스캔은 하지 않는다.
- 추첨권 모달을 열거나 백그라운드 보강이 돌 때만 기존 `userStatus`를 호출해 전체 추첨권 통계를 채운다.
- 로그인 직후에는 `loadUserStatusLite`를 먼저 끝내고, 전체 상태 보강, 교환 데이터, H&P/B.B.B 예열은 순차적으로 늦춘다.
- B.B.B 메시지 조회는 `getBBB` 응답과 분리해 기본 미션 화면이 먼저 보이도록 했다.
- 정적 파일 캐시는 `_headers`에 명시했고, `images/unused`는 `.cfignore`로 배포 제외를 시도한다.
