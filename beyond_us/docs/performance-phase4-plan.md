# 성능 최적화 4차 계획

## 목표

admin 대시보드와 큰 목록 조회에서 서버 계산량과 응답 크기를 줄인다.

## 범위

1. `DashboardStats` 시트를 추가해 대시보드 응답 JSON을 영구 캐시한다.
2. admin 대시보드 새로고침과 Events 기준 재계산은 `DashboardStats`를 강제로 갱신한다.
3. 앱 가입자 목록 API는 `query`, `limit`을 받아 서버에서 필터링한다.
4. 추첨권 번호 목록 API는 `query`, `limit`을 받아 서버에서 필터링한다.
5. admin 프론트는 전체 목록을 한 번에 받지 않고 검색어와 limit을 서버로 보낸다.

## 제외

- H&P 하드코딩 제거는 하지 않는다.
- BBB 조별 매칭 재설계는 하지 않는다.
- legacy 함수 정리는 하지 않는다.
- 구글 시트 외부 DB 이전은 하지 않는다.

## 검증 기준

- admin 대시보드 응답 구조가 기존과 동일하다.
- admin 강제 새로고침은 최신 대시보드를 계산하고 `DashboardStats`에 저장한다.
- 앱 가입자 탭은 기본 일부만 불러오고, 검색 시 서버 결과를 갱신한다.
- 추첨권 번호 탭은 기본 일부만 불러오고, 검색 시 서버 결과를 갱신한다.
- `node --check beyond_us/app.js`, `node --check beyond_us/sw.js`, `node --check beyond_us/Apps_Script`, admin inline script 파싱, `git diff --check`가 통과한다.
