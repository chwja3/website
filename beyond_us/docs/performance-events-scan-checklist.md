# 성능 최적화 체크리스트

- [x] `getUserStatus()`에서 `ensureUserRaffleTickets_()` 호출 제거.
- [x] `getUserStatus()`의 추첨권 번호 조회가 `RaffleTickets`를 중복으로 읽지 않도록 정리.
- [ ] 카드팩 뽑기 후 Collection을 Events 전체 재계산 대신 delta update로 반영.
- [ ] 특별 카드팩 잔여 수를 Events 전체/유저 이벤트 스캔 없이 읽을 수 있게 projection화.
- [ ] 카드 지급/삭제/admin 이벤트를 Collection delta update로 반영.
- [ ] 교환 승인 시 양쪽 Collection을 delta update로 반영.
- [ ] `rebuildCollectionRowsFromEvents_()`는 수동 복구/검증용으로 유지.
- [ ] `MissionProgress` 또는 동등한 dashboard projection 시트 설계.
- [ ] dashboard API를 projection 기준으로 전환.
- [ ] Events 기준 dashboard 재계산 함수는 admin 수동 복구 도구로 유지.
