# Admin Dashboard Weekly And Parish Context

## 결정

이번 작업은 운영자용 admin 대시보드만 변경한다. 유저 앱 화면에는 영향을 주지 않는다.

## 데이터 기준

- 기준 이벤트는 `Events`의 `mission.submitted`다.
- inactive 유저는 모든 대시보드 집계에서 제외한다.
- 이번 주 참여자 수는 클릭 수가 아니라 해당 주차에 제출 이벤트가 1개 이상 있는 active 유저 수다.
- 유저별 참여 날짜 수는 해당 주차 `dateKey`의 distinct count다.
- 유저별 주차 참여 점수는 해당 주차 `payload.score`의 합계다.

## UI 기준

대시보드 맨 위는 이번 주 요약을 유지한다. 그 아래에 1~6주차 항목별 기록 버튼을 두고, 교구별 현황은 summary 카드와 펼침 상세 목록으로 보여준다.

## 구현 메모

- `getDashboardData()`의 기존 응답 필드는 유지하고 `currentWeekSummary`, `weeklySummaries`, `parishSummaries`를 추가했다.
- `MissionDefinitions`는 대시보드 요청당 한 번만 읽고, 읽은 결과를 1~6주차 설정으로 나눠 쓴다.
- 대시보드 캐시는 응답 형태 변경에 맞춰 `dashboard_v2`로 올렸다.
- 유저의 시트 값이 `1청` 또는 `1교구` 어느 쪽이어도 admin 대시보드에는 `1교구` 형식으로 묶어 보여준다.
