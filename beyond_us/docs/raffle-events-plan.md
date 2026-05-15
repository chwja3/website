# 추첨권 Events 편입 계획

## 목표

추첨권 발급과 회수를 `Events`에 기록하고, 앱에서 필요한 현재 추첨권 개수는 `Collection` projection에서 빠르게 읽는다.

## 범위

1. `raffle.granted`, `raffle.revoked` 이벤트 타입을 추가한다.
2. `Collection`에 현재 추첨권 개수와 번호 목록 projection 컬럼을 추가한다.
3. 추첨권 발급 함수는 RaffleTickets 상태 변경과 동시에 Events 로그와 Collection projection을 갱신한다.
4. 추첨권 회수 함수는 RaffleTickets 상태 변경과 동시에 Events 로그와 Collection projection을 갱신한다.
5. 기존에 이미 발급된 추첨권은 현재 상태 기준으로 `raffle.granted` 이벤트를 일괄 생성하는 함수를 추가한다.
6. Events 기준 Collection 재계산은 추첨권 projection도 함께 다시 계산한다.
7. 사용자 앱과 admin 앱 가입자 탭은 가능하면 Collection projection 값을 먼저 사용한다.

## 제외

- RaffleTickets 시트 제거는 하지 않는다. 번호 재활용과 상세 조회용 현재 상태표로 유지한다.
- 추첨권 당첨 처리나 deposit 상태 정책은 바꾸지 않는다.
- 외부 DB 이전은 하지 않는다.

## 검증 기준

- 추첨권 발급 시 `raffle.granted` 이벤트가 남는다.
- 추첨권 회수 시 `raffle.revoked` 이벤트가 남는다.
- 기존 active 추첨권 백필 함수는 중복 실행해도 같은 티켓 이벤트를 중복 생성하지 않는다.
- `rebuildCollectionRowsFromEvents_`가 raffle projection을 다시 만든다.
- 사용자 앱의 추첨권 배지는 full `RaffleTickets` 스캔 없이 Collection projection 값으로 먼저 표시된다.
