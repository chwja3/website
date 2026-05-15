# 추첨권 Events 편입 Context

## 관찰

- 현재 추첨권 개수의 원천은 `RaffleTickets` 시트다.
- 사용자 앱의 컬렉션 배지는 `userStatus.raffle.myTickets`를 표시한다.
- `userStatusLite`는 추첨권 상세 계산을 deferred 처리해서 처음에는 정확한 추첨권 개수를 바로 주지 않는다.
- `userStatus`와 admin 앱 가입자 탭은 `getRaffleTicketSummaryCached_()`를 통해 `RaffleTickets` 전체 active 행을 집계한다.

## 결정

- `Events`는 추첨권 발급/회수 이력의 원장으로 사용한다.
- `RaffleTickets`는 번호 재활용과 번호 상세 조회를 위한 현재 상태표로 유지한다.
- `Collection`은 사용자별 빠른 projection 저장소로 확장한다.
- 기존 active 추첨권은 현재 시점 기준의 migration 이벤트로 한 번 백필한다.
- 회수된 번호는 Events에서 `raffle.revoked`로 남고, RaffleTickets에서는 available 상태가 되어 다음 발급 때 재사용된다.

## 이벤트 설계

- `raffle.granted`.
  - `refId`: ticket_no.
  - `amount`: 1.
  - `payload.condition`: signup, card_3, card_5, card_10 등.
  - `payload.reason`: 앱 가입, 카드 조건, 추첨권 제외 해제 등 트리거.
- `raffle.revoked`.
  - `refId`: ticket_no.
  - `amount`: 1.
  - `payload.condition`: 회수된 티켓의 원래 조건.
  - `payload.reason`: raffle_excluded, user_deactivated, dev_reset 등 회수 사유.

## 구현 메모

- `Collection`에는 `raffleTickets`, `raffleTicketNumbersJson` 컬럼을 추가한다.
- `userStatusLite`는 `Collection` projection에 추첨권 값이 있으면 그 값을 즉시 반환한다.
- full `userStatus`와 admin 앱 가입자 탭은 모든 active 가입자에 projection이 준비되어 있으면 `RaffleTickets` 전체 집계를 건너뛴다.
- projection이 아직 준비되지 않은 상태에서는 기존 `RaffleTickets` 집계로 fallback한다.
- 기존 active 티켓 백필은 `backfillRaffleTicketEventsDryRun`으로 계획을 확인하고, `backfillRaffleTicketEventsApply`로 이벤트 생성과 Collection 재계산을 함께 수행한다.
