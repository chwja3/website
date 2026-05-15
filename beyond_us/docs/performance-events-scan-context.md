# 성능 최적화 컨텍스트

2026-05-15. 느림의 핵심 원인은 `Events`를 원장과 실시간 조회 테이블로 동시에 쓰는 구조다. `Events`는 계속 append-only 원장으로 유지하되, 앱의 평상시 조회는 projection을 읽게 바꾸기로 했다.

첫 변경은 `getUserStatus()`의 읽기 전용화다. 기존에는 사용자가 상태를 조회할 때도 `ensureUserRaffleTickets_()`가 실행되어 `RaffleTickets`를 쓰거나 cache invalidation을 일으킬 수 있었다. 이제 추첨권 발급은 명시적인 쓰기 경로에서만 발생해야 한다.

Collection은 앞으로 이벤트 발생 시점에 delta로 업데이트하는 방향이 더 낫다. 다만 원장과 projection이 어긋날 수 있으므로, 기존 `Events 기준으로 Collection 재계산` 버튼은 삭제하지 않고 복구/검증 버퍼로 남긴다.

Dashboard는 `MissionProgress` 같은 사용자/주차 projection을 두는 방향이 가장 안전하다. 단순 숫자 aggregate만 저장하면 빠르지만, 중복 제출, 유저 비활성화, 교구 변경, 주차별 참여자 수 같은 정책 변경에 취약하다.

2026-05-15. 카드팩 뽑기, admin 카드 지급/삭제, 히든 카드 지급, H&P 티켓 보상, 사전미션 티켓 보상, 교환 승인, BBB 희귀카드 지급은 `rebuildCollectionRow_()` 대신 `updateCollectionRowWithDeltas_()`를 사용한다. 이제 이 경로들은 Events를 append한 뒤 Collection 한 행만 읽고 쓰며, `Events_readAll_()`로 전체 원장을 다시 스캔하지 않는다.

특별 카드팩 잔여 수는 `Collection` 확장 컬럼 `specialPackEarned`, `specialPackConsumed`, `specialPackRemaining`으로 projection화했다. 기존 행은 아직 값이 비어 있을 수 있으므로 projection 값이 없는 사용자만 기존 Events 계산을 임시 fallback으로 사용한다. `Events 기준 Collection 재계산`을 실행하면 기존 사용자도 새 컬럼이 채워져 이후 특별 카드팩 확인에서 Events 스캔이 줄어든다.
