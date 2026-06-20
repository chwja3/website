# 2026-06-21 천로역정 랜덤 2스팟 표시 보강 컨텍스트

증상은 천로역정 탭이 열려도 유저별 붉은 미션 스팟 2개가 보이지 않는 것이었다. 앱은 `m3AssignedSpots` 배열에 들어온 인덱스만 붉은 원으로 표시한다.

최신 `get_bbb_status()`는 `bu_photo_payload(profile_id)`를 호출해 `m3AssignedSpots`를 내려준다. 그런데 `20260621000200_pilgrim_photo_approval.sql`의 `bu_photo_payload()`는 `pilgrim_assignments`를 읽기만 해서, 아직 배정 row가 없는 유저에게 `[]`를 반환했다.

해결은 `bu_photo_payload()`에서 `public.bu_ensure_pilgrim_assignment(profile_id)`를 호출해 배정을 보장하는 것이다. 기존 배정이 있으면 그대로 반환하고, 없으면 `pilgrim_spots`의 활성 스팟 중 유저별 안정적 랜덤 2개를 생성한다.

`20260621000300_pilgrim_assignment_visibility_hotfix.sql`은 이 보강과 함께 활성 유저 전체에 대해 누락 배정을 한 번 backfill한다.

추가 확인 결과, 앱은 `pilgrim` 탭 상태가 `open`이 아니면 실제 천로역정 화면 대신 Coming Soon 설명 화면으로 전환한다. 또한 `bbb_settings.m3.open`이 false면 천로역정 라이브 영역이 숨겨진다.

`20260621000400_pilgrim_visibility_and_assignment_force.sql`은 배정 보장에 더해 `tab_settings.pilgrim`과 `bbb_settings.m3`를 함께 open으로 맞춘다. SQL 마지막에는 활성 유저 수와 2스팟 배정 유저 수를 확인할 수 있는 결과 JSON을 반환한다.

여전히 앱에서 보이지 않는 경우를 줄이기 위해 `20260621000500_get_pilgrim_status_rpc.sql`을 추가했다. 천로역정 탭은 B.B.B. 매칭 여부와 무관하게 `get_pilgrim_status`만 호출해서 `m3AssignedSpots`, `myPhotoM3`, `myPhotoM3Statuses`, `m3Rewarded`를 받는다.

프론트는 `loadPilgrim()`을 새로 두어 `switchSection('pilgrim')`에서 직접 호출한다. 이제 천로역정 화면은 `get_bbb_status`의 `ok:false/no_match` 분기나 B.B.B. 상세 박스 표시 상태에 덜 의존한다.
