# Performance Follow-up Context

## 결정

- H&P와 B.B.B는 실시간성이 필요하지만 초 단위 즉시성이 필요한 영역은 아니다. 짧은 TTL과 mutation 시 무효화를 조합해 첫 진입과 재진입 체감을 줄인다.
- 관리자 대시보드 새로고침은 평소에는 캐시된 `DashboardStats`를 사용한다. 실제 전체 재계산은 이미 있는 `Events 기준 재계산` 버튼으로 분리한다.
- GAS 함수 정리는 삭제가 아니라 주석 처리로 한다. admin/app action으로 연결된 함수와 현재 수동 실행이 필요한 backfill 함수는 보존한다.

## 2026-05-15 작업 기록

- `getHoldPray` GET action을 `getHoldPrayCached_`로 연결했다. TTL은 120초이며, H&P 정답 제출과 힌트 요청은 해당 사용자/주차 캐시를 지운다.
- 문의 수정, 삭제, 답변은 H&P 힌트 응답에 영향을 줄 수 있으므로 H&P 캐시 revision을 올린다.
- `getBBB`와 `getBBBMessages` GET action을 각각 `getBBBCached_`, `getBBBMessagesCached_`로 연결했다. TTL은 45초이며, 사진 업로드/삭제/승인/거절, 메시지 발송, 매칭 변경, BBB 설정 변경 시 캐시를 지운다.
- 관리자 대시보드 새로고침 버튼은 더 이상 `force=1`을 보내지 않는다. 전체 재계산은 `Events 기준 재계산` 버튼이 담당한다.
- `adminRebuildEventDerivedViews`는 Collection, MissionProgress, UserDashboard를 재생성한 뒤 `DashboardStats` 캐시도 바로 갱신한다.
- 직접 실행용으로 남아 있던 `migrateParishJangnyeon`, `rebuildMissionProgressFromEvents`, `setupAllWeeks`, `fixConfigSheetConflict`, `rebuildCollectionRowsFromEvents`, `adminRebuildCollection` public wrapper를 주석 처리했다. 내부 함수와 admin action 경로는 유지했다.
