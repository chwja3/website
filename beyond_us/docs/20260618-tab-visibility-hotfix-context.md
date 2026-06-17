# 2026-06-18 탭 표시 누락 핫픽스 컨텍스트

- `목사님께 무물`과 `별빛 우편함` drawer 항목은 HTML에서 기본 `display:none`으로 시작한다.
- 앱은 dashboard의 `tabSettings`를 받은 뒤에만 해당 항목을 표시한다.
- `별빛 우편함`은 DB key가 `visible_radio`이고 앱 section key는 `visibleRadio`다. 이 둘 중 한쪽만 처리하면 탭이 숨김으로 남을 수 있다.
- admin의 탭 활성화 화면은 `tabSettings.items` 배열을 렌더링하고 다시 `tabItems`로 저장한다.
- 따라서 앱도 top-level boolean만 보지 않고 `items[].key`와 `items[].apiKey`를 함께 해석해야 한다.
- service worker cache 이름이 오래 유지되면 일부 기기에서 이전 앱 파일을 들고 있을 수 있으므로 이번 패치에서 캐시 이름도 갱신한다.
- PowerShell `Get-Content` 출력은 한글이 깨져 보일 수 있지만, 파일 자체는 UTF-8로 정상 저장되어 있다.
