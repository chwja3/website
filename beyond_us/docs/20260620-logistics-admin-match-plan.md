# 숙소 배정 admin 매칭 수정 계획

## 목표

숙소 배정 import 과정에서 동명이인으로 자동 매칭되지 않은 row를 admin이 직접 후보 중에서 선택해 확정할 수 있게 한다.

## 범위

- `retreat_logistics_assignments`의 `candidate_profiles`를 admin 조회 응답에 포함한다.
- 동명이인 또는 미연결 상태를 admin UI에서 구분해서 보여준다.
- admin이 후보 프로필을 선택하면 해당 배정 row의 `profile_id`, `login_id`, `match_status`를 갱신한다.
- 잘못 연결된 경우를 대비해 admin에서 연결을 해제할 수 있게 한다.

## 제외

- 후보가 전혀 없는 사람을 새로 검색해서 연결하는 고급 검색 UI는 이번 범위에서 제외한다.
- 숙소/차량 배정 원본 데이터를 직접 수정하는 UI는 이번 범위에서 제외한다.

## 검증

- 새 SQL migration의 문자열과 함수명이 정상인지 정적 확인한다.
- `admin.html` inline script가 파싱되는지 확인한다.
- `node --check beyond_us/app.js`를 실행해 기존 앱 스크립트가 깨지지 않았는지 확인한다.
