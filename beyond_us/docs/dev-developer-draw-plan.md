# DEV 개발자 무제한 뽑기 계획

## 목표

DEV 환경에서 `Users.isDev`가 TRUE인 개발자 계정만 뽑기권 개수와 상관없이 일반 카드팩을 계속 뽑을 수 있게 한다.

데이터 정합성을 위해 개발자 계정이 뽑기를 실행할 때마다 서버가 먼저 `ticket.granted` 이벤트 1개를 만들고, 이어서 기존 흐름처럼 `ticket.consumed`와 `card.drawn` 이벤트를 기록한다.

## 범위

- 프론트는 DEV URL에서 로그인한 현재 계정이 개발자 계정일 때만 테스트 뽑기 UI를 노출한다.
- GAS는 `testMode`, `ALLOW_TEST_DRAWS`, `Users.isDev`를 모두 만족할 때만 자동 티켓 발급을 허용한다.
- 일반 사용자와 PROD 사용자는 기존처럼 보유 뽑기권이 있어야만 뽑을 수 있다.
- 특별 카드팩 로직은 이번 변경 범위에 포함하지 않는다.

## 성공 기준

1. DEV 개발자 계정은 보유 뽑기권이 0이어도 일반 카드팩 뽑기가 가능하다.
2. 개발자 계정이 뽑을 때마다 Events에 `ticket.granted`, `ticket.consumed`, `card.drawn`이 순서대로 기록된다.
3. DEV 일반 계정은 보유 뽑기권이 0이면 뽑기 버튼이 비활성화된다.
4. PROD에서는 프론트와 GAS 모두 개발자 무제한 뽑기 경로가 열리지 않는다.
5. 프론트 캐시 버전이 `APP_VERSION`, `version.txt`, `sw.js`, `app.html`에서 모두 일치한다.
