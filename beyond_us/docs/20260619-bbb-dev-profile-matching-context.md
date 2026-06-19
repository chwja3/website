# B.B.B. 개발자 계정 조 매칭 컨텍스트

2026-06-19. 조 명단에도 이름이 있고 앱에도 가입했지만 B.B.B. 매칭에서 빠진 사람이 확인되었다.

진단 CSV 기준으로 안성재는 `카니보어시즌2`, 전도현은 `SingSangSong` 계정이 각각 active 상태였지만 `is_dev = true` 때문에 기존 자동 매칭 후보에서 제외되었다. 기존 `bu_sync_group_roster_profile_matches`와 `admin_resolve_group_roster_profile`는 모두 active 계정 중에서도 `is_dev = false`, `is_test = false`만 허용했다.

B.B.B. 조 편성 여부는 개발자 계정 여부와 별개다. 따라서 이번 변경은 B.B.B. 조 명단 매칭 RPC에만 dev/test 허용을 적용한다. DEV 전용 카드팩 보정, 관리자 권한, staff 로그인, 앱 기능 플래그 정책은 그대로 유지한다.

PROD 적용 후에는 `select public.bu_sync_group_roster_profile_matches('20260614');`가 자동 실행되며, 같은 이름 중복이 없는 dev 계정은 매칭될 수 있다. 여전히 중복 계정이나 조 명단 중복은 admin BBB 매칭 화면에서 수동으로 확정해야 한다.
