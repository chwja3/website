# 하진 프로필 보정과 H&P 정답 정책 핫픽스 컨텍스트

## 확인한 내용

- 최신 조 명단 SQL에는 4조 `유하진` row가 있다.
- 사용자가 보고한 실제 앱 가입 프로필 이름은 `하진`이다.
- H&P 최신 함수는 제출 시 이름 비교를 하고, 조회 시에도 이름 비교로 `correctMap`을 다시 만든다.

## 결정

- 프로필 이름을 `유하진`으로 고친 뒤 조 명단 row를 `matched_manual`로 고정한다.
- 이후 `bu_sync_group_roster_profile_matches('20260614')`를 실행해 `group_members`와 `bbb_assignments`를 갱신한다.
- H&P 정책은 운영 요청 기준으로 비익명 카드에 입력값이 있으면 정답으로 처리한다.
- 조회는 이름 재비교가 아니라 저장된 `hold_pray_guesses.correct` 값을 기준으로 한다.

## 구현 메모

- 최신 조 명단 패치도 `source_batch = '20260614'`를 유지하므로, 유하진 보정도 같은 batch에 적용한다.
- `matched_manual` 상태는 조 명단 자동 동기화가 덮어쓰지 않으므로, 수동 보정 뒤 `bu_sync_group_roster_profile_matches('20260614')`를 호출해도 매칭이 유지된다.
- 이전 `20260620000400_hp_bbb_operational_hotfix.sql`은 일부 H&P 비교 helper만 완화했기 때문에, 제출/조회/재계산 함수까지 다시 정의해 정책 차이를 없앴다.
