# 성능 최적화 4차 Context

## 관찰

- 대시보드는 3차에서 CacheService 180초 캐시를 쓰지만, 캐시가 비거나 만료되면 다시 큰 집계를 수행한다.
- admin 앱 가입자 목록과 추첨권 번호 목록은 프론트 렌더링은 80개로 제한했지만, 서버 응답은 여전히 전체 행을 포함한다.
- 구글 시트 기반 앱에서는 계산량뿐 아니라 응답 JSON 크기도 체감 속도에 영향을 준다.

## 결정

- 대시보드 영구 캐시는 별도 `DashboardStats` 시트에 JSON payload로 저장한다.
- 대시보드 force 요청은 시트 캐시를 무시하고 새로 계산한 뒤 시트 캐시를 갱신한다.
- 일반 dashboard 요청은 Script Cache를 먼저 보고, 없으면 `DashboardStats` 시트 캐시를 본다.
- admin 목록 API는 서버에서 query와 limit을 적용하고, 프론트는 받은 결과만 렌더링한다.
- 전체 목록이 꼭 필요한 운영은 검색어를 비우고 더 많이 보기 버튼을 눌러 limit을 늘리는 방식으로 처리한다.

## 구현 메모

- `DashboardStats` 시트는 내부 캐시 용도라 숨김 시트로 생성한다.
- dashboard GET은 Script Cache를 먼저 보고, 없으면 `DashboardStats` 시트 캐시를 본 뒤, 둘 다 없거나 force면 새로 계산한다.
- admin 대시보드 새로고침과 Events 기준 재계산은 `force=true`로 대시보드 캐시를 새로 쓴다.
- 앱 가입자와 추첨권 번호 목록은 서버에서 query, limit, offset을 받는다. 현재 프론트는 offset을 0으로 두고 limit만 늘리는 단순한 더 보기 방식이다.
- 이번 작업에서는 H&P/BBB 개별 탭 캐시, 조회 단위 API 분리, DB 이전은 보류했다.
