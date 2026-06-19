# 숙소 배정 admin 매칭 수정 컨텍스트

## 결정

- 동명이인은 자동으로 한 명을 찍지 않고 `duplicate_needs_check` 상태를 유지한다.
- admin에서 후보 목록 중 한 명을 선택하면 `profile_id`, `login_id`, `match_status`를 확정한다.
- 후보 목록은 import SQL이 만든 `candidate_profiles`를 그대로 사용한다.

## 주의

- `candidate_profiles`가 비어 있는 미가입자는 이번 UI에서 직접 연결하지 않는다.
- 연결 해제는 운영자가 잘못 매칭한 경우를 되돌리기 위한 기능이다.
- PROD 적용 시 `20260619000300_logistics_assignments.sql`, `20260620000100_lodging_assignments_import.sql` 이후 이번 migration을 실행해야 한다.

## 구현 메모

- 새 RPC는 `admin_set_logistics_assignment_profile(p_assignment_id, p_profile_id)`다.
- admin 조회 RPC는 `duplicateProfileCount`, `matchStatus`, `candidateProfiles`를 내려준다.
- admin 표에서는 후보 select와 확정 버튼을 보여주고, 이미 연결된 row는 연결 해제 버튼을 보여준다.
- 검증은 `git diff --check`, `node --check beyond_us/app.js`, `admin.html` inline script 파싱, SQL 정적 문자열 확인을 실행했다.
