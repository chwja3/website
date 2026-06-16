# 2026-06-16 광범위수사 지도 이미지 반영 컨텍스트

## 입력 파일

- `beyond_us/images/maps/전체배치도.jpg`
- `beyond_us/images/maps/예루살렘동.jpg`
- `beyond_us/images/maps/갈릴리동12층.jpg`
- `beyond_us/images/maps/갈릴리동34층.jpg`

## 결정

- 광범위수사 포스터는 기존 `images/Police.webp`를 유지한다.
- 빈 안내도 placeholder 대신 새 JPG를 바로 띄운다.
- `부스` 탭은 아직 별도 파일이 없으므로 이번 화면 구성에서 제외한다.

## 구현 메모

- 지도 탭은 `전체배치도`, `예루살렘동`, `갈릴리동 1·2층`, `갈릴리동 3·4층` 순서로 배치했다.
- `app.js` 캐시 버전은 `20260616a`로 올렸다.
