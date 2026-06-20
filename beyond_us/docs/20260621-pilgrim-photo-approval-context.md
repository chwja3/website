# 2026-06-21 천로역정 사진 승인 전환 컨텍스트

기존 천로역정은 `pilgrim_assignments`에 유저별 랜덤 2스팟을 저장하고, `get_bbb_status` / `admin_bbb_pilgrim_status`에서 해당 배정과 완료 스팟을 내려준다. 완료 스팟은 `mission_photo_submissions`의 `mission_key='pilgrim'`, `approval_status='approved'` 기준으로 집계된다.

2026-06-19 QR 검증 전환 이후 `submit_mission_photo`는 `m3_*` 또는 `pilgrim` 업로드에 대해 `qr_required`를 반환하고, `verify_pilgrim_qr`만 즉시 승인 기록을 만들었다. 운영 정책이 다시 사진 승인 방식으로 바뀌었으므로, `submit_mission_photo`가 배정된 스팟 사진을 `pending`으로 저장하고 admin 승인 흐름이 최종 완료를 처리하도록 되돌린다.

앱의 현재 스토리지 업로드 경로는 닉네임을 ASCII-safe 경로로 변환하므로 한글 닉네임 `InvalidKey` 문제는 현재 코드 기준으로는 막혀 있다.

구현은 `20260621000200_pilgrim_photo_approval.sql`에 모았다. 이 마이그레이션은 `submit_mission_photo`의 천로역정 `m3_*` 경로를 다시 pending 사진 제출로 바꾸고, `admin_review_mission_photo` RPC를 추가해 BBB Mission 1/2와 천로역정 스팟 승인/거절을 한 함수로 처리한다. 천로역정은 배정 스팟 2개가 모두 `approved`가 되면 레어 카드 10번을 지급한다.

유저 앱은 `myPhotoM3Statuses`를 받아 `pending`은 주황색 승인 대기, `approved`는 초록색 완료로 표시한다. 기존 QR 링크는 더 이상 서버 완료를 호출하지 않고, 천로역정 화면에서 사진 제출 안내만 보여준다.
