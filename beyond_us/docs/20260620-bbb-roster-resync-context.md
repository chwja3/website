# B.B.B. 신규 가입자 조 매칭 재동기화 컨텍스트

2026-06-20. 신규 가입자 중 B.B.B. 조 명단에서 `닉네임 없음`으로 남아 있는 사람이 있어 재동기화 절차를 준비했다.

기존 구조상 `retreat_group_roster`는 조 원본 명단을 보존하고, `matched_profile_id`로 앱 가입자 `profiles`와 연결된다. 자동 매칭은 `bu_sync_group_roster_profile_matches('20260614')`가 담당한다.

`profiles` 변경 후 자동으로 맞춰져야 하므로 `sync_group_roster_profile_after_change` trigger도 함께 재보강한다. 이번 작업은 조 명단 자체를 삭제하거나 다시 import하지 않고, 현재 명단과 현재 가입자 기준으로 매칭 상태만 다시 계산한다.
