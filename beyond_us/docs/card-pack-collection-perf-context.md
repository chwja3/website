# 카드팩 Collection 반영 속도 개선 Context

## 관찰

- 카드 뽑기 서버 응답은 이미 최신 Collection과 Ticket 정보를 포함한다.
- `closeDrawOverlay()`는 서버 응답의 Collection 정보를 로컬 `userStatus`에 반영한 뒤 Collection을 렌더링한다.
- 그 직후 `switchSection('collection')`이 다시 Collection 렌더링과 `loadUserStatus({ silent: true })`를 실행한다.
- 추가로 `closeDrawOverlay()`도 별도의 `loadUserStatus({ silent: true })`를 호출하고 있어, 뽑기 직후 같은 계정 상태를 중복 조회한다.
- 카드 뒷면 클릭 가능 상태는 서버 응답과 애니메이션 상태가 모두 준비되어야 열린다.

## 결정

- 뽑기 직후에는 서버 응답에 포함된 Collection/Ticket 결과를 우선 신뢰한다.
- Collection 탭 전환 시 새로고침을 생략할 수 있는 옵션을 추가한다.
- 추첨권 등 서버에서 후속 계산되는 값은 화면 전환 이후 백그라운드로 조용히 갱신한다.
- 카드 뒷면 클릭 가능 전환은 사용자 요청대로 0.01초로 줄인다.
- WebP 변환은 현재 로컬 도구 사용 가능 여부를 먼저 확인한다.

## 결과

- `closeDrawOverlay()`에서 Collection 탭으로 넘어갈 때 `switchSection('collection', { skipUserStatusRefresh: true })`를 사용하도록 변경했다.
- 뽑기 직후의 확인용 `loadUserStatus({ silent: true })`는 `requestIdleCallback` 또는 0.9초 지연 후 백그라운드로 실행한다.
- 카드 뒷면 클릭 가능 상태 전환 지점을 0.46초에서 0.01초로 줄였다.
- Collection 카드 이미지와 교환 카드 선택 이미지에 `loading="lazy"`, `decoding="async"`, `fetchpriority="low"`를 추가했다.
- 카드, 카드팩, 카드 뒷면, 히든 카드, 천로역정 지도, H&P 이미지를 WebP로 변환하고 앱 참조를 WebP로 교체했다.
- `beyond_us/images` 루트는 약 142MB에서 약 2.7MB로 줄었고, 기존 원본은 `beyond_us/images/unused`로 이동했다.
- 프론트 캐시 버전은 `20260515o`로 동기화했다.
