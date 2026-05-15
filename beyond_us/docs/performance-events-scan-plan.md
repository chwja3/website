# 성능 최적화 계획

## 목표

앱의 일상 조회 경로에서 `Events` 전체 스캔과 Sheet 쓰기를 제거한다. `Events`는 원장으로 유지하되, 사용자 앱과 관리자 대시보드는 `Collection`, `RaffleTickets`, 향후 집계 시트 같은 projection을 우선 읽는다.

## Phase A. userStatus 읽기 전용화

`getUserStatus()`에서 추첨권 backfill 발급을 제거한다. 추첨권 발급은 가입, 카드 뽑기, 카드 지급, 발급 제외 해제, 수동 backfill 같은 명시적 쓰기 경로에서만 실행한다.

검증 기준은 `userStatus` 호출만으로 `RaffleTickets` 행이 새로 생기지 않는 것이다.

## Phase B. Collection 증분 업데이트

카드/티켓 관련 이벤트가 발생할 때 `Events`에 append한 뒤, 같은 요청 안에서 `Collection` 행을 현재 row 기준으로 delta 업데이트한다.

`rebuildCollectionRowsFromEvents_()`와 admin의 Events 기준 재계산 버튼은 유지한다. 이 버튼은 projection이 틀어졌을 때 원장 기준으로 복구하는 버퍼 역할을 한다.

## Phase C. Dashboard 집계 사전계산

대시보드는 매 요청마다 `Events` 전체를 1~6주차로 다시 집계하지 않는다. 다음 중 하나로 간다.

1. `MissionProgress` projection. 사용자/주차 단위 row를 유지하고, 대시보드는 이 작은 표를 읽어 집계한다.
2. `DashboardAggregates` projection. 주차/항목/교구별 숫자를 미리 저장하고, 대시보드는 거의 그대로 읽는다.

중복 제출, 유저 비활성화, 교구 변경까지 고려하면 1번이 더 안전하다. 2번은 더 빠르지만 정합성 복구 로직이 복잡하다.

## 권장 순서

1. `userStatus` backfill 제거.
2. 카드팩/카드 지급/교환부터 Collection delta update 적용.
3. BBB 특별 카드팩 카운터도 Collection 또는 별도 projection으로 이동.
4. `MissionProgress` projection 추가.
5. dashboard를 `MissionProgress` 기준으로 전환.
6. 기존 Events 전체 집계는 admin 수동 재계산/검증 함수로만 유지.
