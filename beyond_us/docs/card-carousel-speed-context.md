# 카드팩 캐러셀 로딩 단축 Context

## 관찰

- 카드팩 캐러셀은 `drawOverlay` 안의 `carouselLayer`에서 세 개의 `.c-pack`을 보여준다.
- `.c-pack`, `.pack`, `#packTopPiece`는 `images/앤카드팩디자인배경제거.png`를 CSS background/mask로 사용한다.
- `#packCardPreview`는 `images/앤카드뒷면최최종.png`를 사용한다.
- 기존 `preloadCardImages()`는 카드 앞면과 히든 카드 이미지만 idle 시점에 선로딩하고, 카드팩 이미지와 카드 뒷면은 별도 선로딩하지 않았다.
- `openDrawOverlay()`는 캐러셀을 보여주기 전에 사운드 프리로드, BGM 시작, reveal spark와 particle 초기화를 함께 실행했다.

## 결정

- 카드팩 이미지와 카드 뒷면은 뽑기 UI 핵심 자산이므로 `preloadDrawAssets()`로 별도 선로딩한다.
- 카드 앞면 선로딩은 유지하되 낮은 우선순위로 요청한다.
- 첫 캐러셀 표시 전에 필요하지 않은 사운드 프리로드와 이펙트 DOM 생성은 첫 paint 이후 또는 카드 공개 시점으로 미룬다.
- 사용자 플로우나 보상 로직은 건드리지 않는다.

## 구현 메모

- `preloadImage()` 공통 헬퍼로 이미지 중복 요청을 막는다.
- `preloadDrawAssets()`는 카드팩 이미지와 카드 뒷면을 높은 우선순위로 선로딩한다.
- `openDrawOverlay()`에서는 사운드 프리로드와 BGM 시작을 `requestAnimationFrame()` 뒤로 미룬다.
- reveal spark와 particle DOM은 캐러셀 오픈 시점에 만들지 않고 실제 이펙트가 필요할 때 lazy 생성한다.
- 캐러셀 첫 fade-in과 팩 줌 전환 시간을 짧게 줄여 체감 대기 시간을 줄인다.
