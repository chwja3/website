# H&P owner_name_input 정답 판정 Context

2026-05-26. H&P 기도제목 중 일부는 실제 가입 유저와 `profile_id`로 연결되어 있지 않고, 관리자 매칭 과정에서 입력한 실명만 `hold_pray_entries.owner_name_input`에 남아 있다.

기존 `submit_hold_pray_guess`는 `entry_profile_id`가 있을 때만 `profiles.name`과 비교했다. 그래서 기도제목 작성자가 앱 유저로 존재하지 않거나 아직 프로필 매칭이 안 된 경우, 사용자가 정확한 이름을 입력해도 정답 처리되지 않았다.

수정 방향은 H&P 엔트리의 정답 이름을 구하는 기준을 공통화하는 것이다. 프로필이 연결되어 있으면 `profiles.name`을 우선 사용하고, 프로필이 없으면 `owner_name_input`을 사용한다. 이 기준을 정답 제출, 정답 맵 조회, 기존 응답 재계산에 모두 적용한다.

구현은 `20260526000100_hp_owner_name_input_answer.sql`에 담았다. `bu_hold_pray_answer_name(entry_id)` helper를 추가하고, `get_hold_pray`, `submit_hold_pray_guess`, `bu_recalculate_hold_pray_guesses`가 모두 이 helper를 사용하도록 덮어쓴다.
