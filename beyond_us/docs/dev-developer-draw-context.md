# DEV 개발자 무제한 뽑기 컨텍스트

## 2026-05-13 결정

- 사용자는 DEV의 개발자 계정에서만 뽑기권 개수와 상관없이 무제한 뽑기를 원한다.
- 단순히 티켓 검사를 우회하면 Events 기준 집계와 UserDashboard 검증이 어긋날 수 있다.
- 그래서 개발자 테스트 뽑기도 실제 데이터 흐름처럼 `ticket.granted` 이벤트를 먼저 추가하고, 그 다음 `ticket.consumed`, `card.drawn`을 기록한다.
- 서버 허용 조건은 `testMode === true`, `ALLOW_TEST_DRAWS === true`, `Users.isDev === TRUE` 세 가지를 모두 만족해야 한다.
- 프론트의 DEV 환경 감지는 UI 노출용으로만 쓰고, 실제 권한은 서버에서 다시 확인한다.
- 특별 카드팩은 BBB 미션 보상 흐름과 연결되어 있으므로 이번 변경에서는 건드리지 않는다.

## 구현 메모

- `drawCard`는 개발자 테스트 뽑기일 때 `dev_auto_draw` 사유의 `ticket.granted`를 먼저 기록한다.
- 이후 같은 요청 안에서 `ticket.consumed`와 `card.drawn`을 기록하므로 남은 일반 카드팩 수는 늘어나지 않고, 이벤트 집계만 온전하게 남는다.
- 프론트는 `localStorage.beyondus_is_dev`가 `true`이고 현재 호스트가 DEV일 때만 무제한 뽑기 버튼을 보여준다.
- 요청 본문의 `testMode`도 일반 카드팩에서 현재 개발자 계정일 때만 true로 보낸다.
- 검증은 `node --check beyond_us/app.js`, `node --check beyond_us/Apps_Script`, `git diff --check`로 수행했다.
