# B.B.B. 신규 가입자 조 매칭 재동기화 계획

1. 기존 `retreat_group_roster`와 `profiles` 매칭 RPC를 재사용한다.
2. `profiles` 변경 시 자동 동기화하는 trigger가 살아있도록 보강한다.
3. `bu_sync_group_roster_profile_matches('20260614')`를 실행한다.
4. 실행 후 남은 `닉네임 없음`, 중복 확인 필요, 매칭 완료 요약을 한 번에 확인한다.
