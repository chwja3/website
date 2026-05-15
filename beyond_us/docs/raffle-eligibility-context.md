# 추첨권 대상 교구 제한 Context

## 결정

추첨권 대상자는 1청, 2청, 3청, 4청, VIP만이다. 목양교구와 교회학교는 추첨권 정책에서 제외한다. 1청(사역자), 3청(사역자)처럼 청년 교구명으로 시작하는 값은 포함한다.

## 현재 흐름

- 가입 시 `registerUser()`가 `issueRaffleTicket_(nickname, 'signup')`를 호출한다.
- 카드 뽑기나 레어 카드 지급 후 `ensureUserRaffleTickets_()`가 카드 3종, 5종, 10종 조건을 backfill한다.
- `getUserStatus()`는 `raffle` 객체를 내려주고, 앱은 컬렉션 헤더에 추첨권 배지를 표시한다.
- `RaffleTickets`는 `ticket_no`, `userId`, `parish`, `condition`, `deposit_status` 등을 가진다.

## 구현 메모

- 비대상자 기존 번호는 삭제하지 않고 `deposit_status`를 `revoked_ineligible_parish`로 바꾼다.
- 회수된 번호는 재사용하지 않는다.
- admin 번호 검색에서는 회수된 번호를 유효한 추첨권처럼 보여주지 않고 회수 상태를 알려준다.
- 앱 가입자 탭의 사용자별 초기화는 해당 유저의 활성 추첨권만 `revoked_admin_reset`으로 바꾼다.
- 앱 가입자 탭에서 초기화된 `userId + condition` 조합은 자동 backfill이 다시 새 번호를 만들지 않도록 기존 발급 이력으로 취급한다.
- 참석 체크는 운영 기록용으로 남기되, 추첨권 발급 조건에는 계속 반영하지 않는다.
