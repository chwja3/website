# Admin Dashboard Weekly Parish History Context

## 결정

기존 `parishSummaries`는 현재 주차용으로 유지하고, 주차별 기록에는 새 필드 `weeklyParishSummaries`를 사용한다.

## 데이터 형태

`weeklyParishSummaries`의 각 항목은 `week`, `weekKey`, `weekTitle`, `parishSummaries`를 가진다. `parishSummaries` 내부 구조는 기존 `교구별 이번 주 참여`에서 쓰는 구조와 같다.

## UI 기준

새 영역은 `주차별 항목 기록` 바로 아래에 둔다. 한 화면에서 항목별 기록을 본 뒤 같은 주차 기준으로 교구별 참여도 이어서 확인할 수 있게 하기 위함이다.
