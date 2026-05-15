# 추첨권 대상 교구 제한 Context

## 결정

추첨권 대상 여부는 `Users.raffleExcluded`로 관리한다. 목양교구와 교회학교처럼 기본 대상이 아닌 교구는 기본값이 제외로 들어가고, admin 앱 가입자 탭에서 수동으로 바꿀 수 있다.

## 현재 흐름

- 가입 시 `registerUser()`가 `issueRaffleTicket_(nickname, 'signup')`를 호출한다.
- 카드 뽑기나 레어 카드 지급 후 `ensureUserRaffleTickets_()`가 카드 3종, 5종, 10종 조건을 backfill한다.
- `getUserStatus()`는 `raffle` 객체를 내려주고, 앱은 컬렉션 헤더에 추첨권 배지를 표시한다.
- `RaffleTickets`는 `ticket_no`, `active`, `userId`, `name`, `parish`, `condition_label` 등을 가진 번호 풀이다.

## 구현 메모

- 발급 제외 사용자의 기존 번호는 `active=0`으로 바꾸고 받은 사람 정보와 이벤트 정보를 비운다.
- 회수된 번호는 재사용한다.
- admin 번호 검색에서는 `active=0` 번호를 미지급 번호로 보여준다.
- 앱 가입자 탭의 발급 제외 체크는 해당 유저의 활성 추첨권을 즉시 회수하고 향후 발급도 막는다.
- 참석 체크는 운영 기록용으로 남기되, 추첨권 발급 조건에는 계속 반영하지 않는다.

## 변경 결정

사용자별 초기화 버튼 대신 `raffleExcluded` 상태를 둔다. 체크된 사용자는 현재 활성 추첨권을 모두 회수하고, 조건을 다시 만족해도 새 추첨권을 받지 않는다. 회수된 번호는 `active=0`인 번호 풀로 돌아가 다음 발급 시 재사용한다.

목양교구와 교회학교처럼 기본 대상이 아닌 교구는 `raffleExcluded`의 기본값을 `true`로 둔다. admin에서 이 값을 바꾸면 수동 설정이 우선한다.
