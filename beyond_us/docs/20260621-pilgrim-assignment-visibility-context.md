# 2026-06-21 천로역정 랜덤 2스팟 표시 보강 컨텍스트

증상은 천로역정 탭이 열려도 유저별 붉은 미션 스팟 2개가 보이지 않는 것이었다. 앱은 `m3AssignedSpots` 배열에 들어온 인덱스만 붉은 원으로 표시한다.

최신 `get_bbb_status()`는 `bu_photo_payload(profile_id)`를 호출해 `m3AssignedSpots`를 내려준다. 그런데 `20260621000200_pilgrim_photo_approval.sql`의 `bu_photo_payload()`는 `pilgrim_assignments`를 읽기만 해서, 아직 배정 row가 없는 유저에게 `[]`를 반환했다.

해결은 `bu_photo_payload()`에서 `public.bu_ensure_pilgrim_assignment(profile_id)`를 호출해 배정을 보장하는 것이다. 기존 배정이 있으면 그대로 반환하고, 없으면 `pilgrim_spots`의 활성 스팟 중 유저별 안정적 랜덤 2개를 생성한다.

`20260621000300_pilgrim_assignment_visibility_hotfix.sql`은 이 보강과 함께 활성 유저 전체에 대해 누락 배정을 한 번 backfill한다.
