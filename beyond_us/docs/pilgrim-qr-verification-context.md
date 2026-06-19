# 천로역정 QR 검증 컨텍스트

2026-06-19. 기존 천로역정은 유저별 랜덤 2스팟 배정을 `pilgrim_assignments`에 저장하고, 배정된 스팟에 사진을 올리면 즉시 완료 처리했다.

QR 검증 이후에는 사진이 아니라 스팟 QR 토큰 일치 여부를 완료 판정의 핵심으로 둔다. 사용자는 QR을 찍어 앱 URL로 들어오고, 서버는 해당 유저에게 배정된 스팟인지와 토큰이 맞는지를 동시에 확인한다.

현장 운영 편의를 위해 7개 QR은 앱 URL 형태로 만든다. 카메라 앱에서 찍으면 브라우저가 열리고, 로그인 세션이 있으면 바로 검증한다. 로그인 전이면 앱 진입 후 다시 시도하도록 안내한다.

2026-06-19. `20260619000100_pilgrim_qr_verification.sql`을 추가했다. `pilgrim_spots.qr_token`을 DB에서 랜덤 생성하고, `verify_pilgrim_qr`만 천로역정 스팟 완료를 만들 수 있게 했다. 기존 `submit_mission_photo`의 천로역정 사진 업로드 경로는 `qr_required`로 막는다.

앱은 `pilgrimSpot`과 `pilgrimCode` URL 파라미터를 읽어 로그인 후 자동으로 QR 검증을 요청한다. 관리자 `BBB/천로역정` 탭에는 `admin_get_pilgrim_qr_codes`를 호출해 7개 스팟별 QR URL을 복사하는 도구를 추가했다.
