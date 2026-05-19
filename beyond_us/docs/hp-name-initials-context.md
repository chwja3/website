# H&P 실명 초성 힌트 컨텍스트

2026-05-19. 사용자가 H&P 힌트에서 초성이 제대로 나오지 않는다고 보고했다. 현재 H&P 힌트는 `post_hold_pray_hint` RPC에서 작성자 profile을 찾아 즉석으로 초성을 계산한다. 운영 관점에서는 user row마다 실명 기준 초성이 명시적으로 붙어 있는 편이 더 확인하기 쉽고, 닉네임이나 표시명 기준으로 힌트가 흔들리지 않는다.

결정은 `profiles.name`에서 초성을 만든 `profiles.name_initials`를 보관하는 것이다. 이 값은 H&P 힌트와 admin H&P 현황에서 사용한다. 표시명 `display_name`이나 로그인 아이디 `login_id`는 초성 기준으로 쓰지 않는다.

2026-05-19. `20260519000800_hp_name_initials.sql`을 추가했다. 이 migration은 `profiles.name_initials`를 backfill하고, 이름 변경 시 자동 갱신 trigger를 붙인다. `post_hold_pray_hint`는 H&P 작성자의 `name_initials`를 우선 사용하고, admin `H&P 현황`은 유저와 각 카드 작성자의 초성을 같이 반환한다.
