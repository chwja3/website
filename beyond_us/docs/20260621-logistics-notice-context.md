# 숙소 안내문 상단 노출 컨텍스트

- 숙소/차량 탭은 `sectionLogistics`에서 `logisticsContent` 영역을 렌더링한다.
- 현재 공용 숙소 이미지는 `renderGlobalLogisticsImages()`에서 `LOGISTICS_PUBLIC_IMAGE_PATHS`를 순회해 표시한다.
- 숙소 이미지를 사용할 수 있는 상태에서는 개인 배정 조회보다 공용 이미지 렌더링이 먼저 실행된다.
- 안내문은 이미지 자체를 바꾸지 않고, 이미지 목록 위에 별도 안내 카드로 추가한다.
- 앱 변경이므로 `APP_VERSION`, `version.txt`, `sw.js` cache 이름, `app.html` 쿼리 버전을 모두 `20260621f`로 맞췄다.
- 브라우저 자동 확인은 로컬 브라우저 연결 권한 오류로 실행하지 못했고, `node --check`와 버전 참조 검색으로 검증했다.
