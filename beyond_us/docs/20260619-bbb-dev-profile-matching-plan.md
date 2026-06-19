# B.B.B. 개발자 계정 조 매칭 계획

## 목표

B.B.B. 조 명단 매칭에서 실제 조원인 개발자/테스트 계정이 `is_dev` 또는 `is_test` 값 때문에 자동/수동 매칭에서 제외되지 않게 한다.

## 범위

- `bu_sync_group_roster_profile_matches` RPC의 앱 계정 후보 조건에서 `is_dev`, `is_test` 제외 조건을 제거한다.
- `admin_resolve_group_roster_profile` RPC의 수동 매칭 대상 조건에서도 `is_dev`, `is_test` 제외 조건을 제거한다.
- 앱의 DEV 전용 뽑기 기능, 관리자 권한, 로그인 정책은 변경하지 않는다.

## 검증

- SQL 문법을 정적으로 확인한다.
- PROD 적용 후 `bu_sync_group_roster_profile_matches('20260614')` 결과와 안성재/전도현 매칭 상태를 재확인한다.
