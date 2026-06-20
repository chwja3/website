# BBB/천로역정 승인 화면 통합 컨텍스트

- 요청자는 천로역정 Mission 3 승인도 BBB 승인 화면과 묶어서 한 번에 보기 편하길 원한다.
- 현재 admin에는 `BBB 사진 승인` 카드와 `BBB/천로역정 운영 현황` 카드가 나뉘어 있다.
- `admin_bbb_pilgrim_status()`는 유저별 `m1`, `m2`, `pilgrimAssignedSpots`, `pilgrimCompletedSpots`, `pilgrimSpotPhotos`를 이미 내려준다.
- 승인/거절은 기존 `reviewBBBPhotoFromButton()`과 `adminApproveBBBPhoto` / `adminRejectBBBPhoto` 경로를 그대로 사용한다.
- 첫 번째 카드는 `BBB/천로역정 Mission 승인`으로 바꾸고, `admin_bbb_pilgrim_status()`를 직접 읽어서 Mission 1/2와 Mission 3 스팟 2개를 유저별 같은 details 카드 안에 렌더한다.
- Mission 3의 각 스팟은 기존 `renderOpsPhotoMini()`를 재사용하므로 승인/거절 버튼과 보상 지급 흐름은 BBB 사진 승인과 같은 경로를 탄다.
- 두 번째 `BBB/천로역정 매칭 요약` 카드는 사진 승인 버튼을 반복하지 않고, 케어버디/시크릿버디/조/미션 상태 요약만 보여준다.
