# 추첨권 Events 편입 체크리스트

- [x] `raffle.granted`, `raffle.revoked` 이벤트 타입 추가.
- [x] `Collection` 추첨권 projection 컬럼 추가.
- [x] Collection snapshot 읽기/쓰기/비교에 추첨권 필드 반영.
- [x] 발급 함수에서 raffle 이벤트와 Collection delta 갱신.
- [x] 회수 함수에서 raffle 이벤트와 Collection delta 갱신.
- [x] 기존 active 추첨권 이벤트 백필 함수 추가.
- [x] `getUserStatusLite_`, `getUserStatus`, `adminGetRaffleAttendance` 조회 경로 최적화.
- [x] 문법 검증과 diff 검토.
- [x] 커밋.
