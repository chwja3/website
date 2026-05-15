# 성능 최적화 컨텍스트

2026-05-15. 느림의 핵심 원인은 `Events`를 원장과 실시간 조회 테이블로 동시에 쓰는 구조다. `Events`는 계속 append-only 원장으로 유지하되, 앱의 평상시 조회는 projection을 읽게 바꾸기로 했다.

첫 변경은 `getUserStatus()`의 읽기 전용화다. 기존에는 사용자가 상태를 조회할 때도 `ensureUserRaffleTickets_()`가 실행되어 `RaffleTickets`를 쓰거나 cache invalidation을 일으킬 수 있었다. 이제 추첨권 발급은 명시적인 쓰기 경로에서만 발생해야 한다.

Collection은 앞으로 이벤트 발생 시점에 delta로 업데이트하는 방향이 더 낫다. 다만 원장과 projection이 어긋날 수 있으므로, 기존 `Events 기준으로 Collection 재계산` 버튼은 삭제하지 않고 복구/검증 버퍼로 남긴다.

Dashboard는 `MissionProgress` 같은 사용자/주차 projection을 두는 방향이 가장 안전하다. 단순 숫자 aggregate만 저장하면 빠르지만, 중복 제출, 유저 비활성화, 교구 변경, 주차별 참여자 수 같은 정책 변경에 취약하다.

2026-05-15. 카드팩 뽑기, admin 카드 지급/삭제, 히든 카드 지급, H&P 티켓 보상, 사전미션 티켓 보상, 교환 승인, BBB 희귀카드 지급은 `rebuildCollectionRow_()` 대신 `updateCollectionRowWithDeltas_()`를 사용한다. 이제 이 경로들은 Events를 append한 뒤 Collection 한 행만 읽고 쓰며, `Events_readAll_()`로 전체 원장을 다시 스캔하지 않는다.

특별 카드팩 잔여 수는 `Collection` 확장 컬럼 `specialPackEarned`, `specialPackConsumed`, `specialPackRemaining`으로 projection화했다. 기존 행은 아직 값이 비어 있을 수 있으므로 projection 값이 없는 사용자만 기존 Events 계산을 임시 fallback으로 사용한다. `Events 기준 Collection 재계산`을 실행하면 기존 사용자도 새 컬럼이 채워져 이후 특별 카드팩 확인에서 Events 스캔이 줄어든다.

Dashboard는 `MissionProgress` projection을 추가했다. `saveCheckin()`은 새 미션 제출이 저장될 때 사용자/주차 단위 row를 증분 업데이트하고, `getDashboardData()`는 `MISSION_PROGRESS_READY=true`인 경우 Events 전체 스캔 대신 MissionProgress를 읽어 주차별 항목 기록과 교구별 참여 기록을 만든다. `adminRebuildEventDerivedViews()`와 `prodCutoverApply()`는 Events 기준 Collection 재계산과 함께 MissionProgress도 재생성한다. 기존 데이터 전환 전에는 dashboard가 기존 Events 집계 경로를 사용한다.

admin의 `Events 기준 재계산` 버튼 문구와 완료 메시지도 새 projection 구조에 맞춰 수정했다. 버튼을 실행하면 Collection, MissionProgress, UserDashboard를 재계산하고, 완료 후 티켓/카드/대시보드 패널을 다시 불러온다.
Follow-up context.

2026-05-15. 사용자 앱에서 여전히 느린 경로는 userStatus와 saveCheckin의 Events_readByUser 호출이다. MissionProgress가 dashboard 용도만 갖고 있으면 오늘 제출한 항목을 빠르게 알 수 없으므로, 날짜별 제출 인덱스 projection을 추가해서 사용자 상태와 제출 전 중복 검증도 projection을 우선 보도록 확장한다. 기존 Events 경로는 projection이 준비되지 않은 DEV/PROD 전환 직후의 fallback으로만 남긴다.

2026-05-15. MissionProgress에 dateSlotIndicesJson 컬럼을 추가했다. rebuildMissionProgressFromEvents 또는 admin Events 기준 재계산을 실행하면 기존 mission.submitted 이벤트에서 날짜별 제출 인덱스가 다시 채워진다. 이후 getUserStatus와 saveCheckin은 MissionProgress를 우선 읽고, projection이 준비되지 않았거나 오늘 제출 기록의 날짜별 인덱스가 비어 있는 경우에만 Events_readByUser로 fallback한다.

2026-05-15. 카드 뽑기 직후 추첨권 조건 확인은 updateCollectionRowWithDeltas 결과 snapshot을 재사용하도록 바꿨다. 기존 ensureUserRaffleTickets는 Collection을 다시 읽은 뒤 조건마다 issueRaffleTicket을 호출했지만, 이제 snapshot 기반 helper가 3종/5종/10종 조건을 계산하고 RaffleTickets를 한 번 읽어서 필요한 번호만 발급한다.
