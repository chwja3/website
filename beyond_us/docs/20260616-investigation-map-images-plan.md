# 2026-06-16 광범위수사 지도 이미지 반영 계획

## 목표

`beyond_us/images/maps`에 추가된 JPG 지도 파일 4개를 dev 앱의 광범위수사 탭에서 확인할 수 있게 한다.

## 범위

1. 기존 포스터 탭은 유지한다.
2. 지도 탭은 `전체배치도`, `예루살렘동`, `갈릴리동 1·2층`, `갈릴리동 3·4층`으로 구성한다.
3. 각 탭은 사용자가 업로드한 JPG 파일을 직접 참조한다.
4. 앱 캐시 갱신을 위해 `app.js` 쿼리 버전을 올린다.

## 검증

- `node --check beyond_us\app.js`가 통과한다.
- 새 JPG 4개가 Git에 포함된다.
- 광범위수사 섹션에 더 이상 없는 `booths.webp`, `overview.webp`, `galilee.webp`, `jerusalem.webp` 참조가 남지 않는다.
