# Raffle Available Numbers Context

## 결정

- 회수된 번호는 `RaffleTickets.active`가 false인 기존 번호 row를 의미한다.
- 아직 한 번도 생성되지 않은 미래 번호는 표시 대상이 아니다.
- 표시 영역은 admin `추첨권 번호` 탭의 `회수된 번호` 통계 카드 아래에 둔다.
- `adminGetRaffleTickets`는 전체 번호 목록 기준으로 inactive 번호를 `availableNumbers`에 담아 내려준다.
- admin 화면은 회수된 번호를 최대 24개까지 chip으로 보여주고, 초과분은 `외 N개`로 축약한다.
