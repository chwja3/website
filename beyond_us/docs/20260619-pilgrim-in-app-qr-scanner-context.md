# 천로역정 앱 안 QR 스캐너 컨텍스트

2026-06-19. 사용자는 천로역정 빨간 원을 누르면 QR을 찍는 화면이 나오고, 그 화면에서 QR을 입력하거나 촬영해 인증되길 원한다고 정정했다. 기존 구현은 앱 외부 카메라로 QR URL을 열거나, 빨간 원 클릭 시 안내문만 보여주는 방식이었다.

기존 Supabase RPC `verify_pilgrim_qr`는 그대로 사용한다. 프론트는 빨간 스팟 클릭 시 `openPilgrimQrScanner(spotIndex)`를 열고, `BarcodeDetector`가 있으면 카메라 영상에서 QR을 자동 인식한다. 미지원 브라우저나 권한 실패 상황에서는 QR URL 또는 토큰을 직접 입력해 인증할 수 있다.
