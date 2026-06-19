# 관리자 천로역정 QR PNG 열기 수정 컨텍스트

2026-06-19. 사용자는 main의 admin 개발자 탭에서 천로역정 QR `PNG 열기` 버튼이 정상 동작하지 않는다고 했다. 또한 PNG 안에 QR만 있는 것이 아니라 상단에 `천로역정 스팟 n / 이름 / 인증 QR` 안내가 함께 들어가길 원했다.

기존 구현은 `api.qrserver.com`의 QR 이미지 URL을 그대로 새 탭으로 열었다. 이를 admin에서 새 창을 먼저 열고, QR 이미지를 canvas에 합성해 PNG data URL로 표시하는 방식으로 바꾼다. 외부 QR 이미지 로딩이나 canvas 변환이 실패하면 제목과 QR 이미지를 포함한 HTML fallback을 표시한다.
