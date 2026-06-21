# 숙소 안내 이미지 교체와 BBB 업로드 보강 컨텍스트

- 기존 숙소 탭은 `images/logistics/lodging_assignment_01.jpg`, `02.jpg`, `03.jpg` 세 장을 정적 fallback으로 보여준다.
- 새 숙소 안내 이미지는 사용자가 제공한 `KakaoTalk_20260621_085321520.jpg`, `KakaoTalk_20260621_085321520_01.jpg` 두 장이다.
- BBB 사진 업로드는 `_compressImage(file, 400, 0.55)` 뒤에 `uploadMissionPhoto`를 호출한다.
- 갤러리에서 파일을 선택한 뒤 브라우저 이미지 디코딩이 멈추면 기존 구조는 `catch`까지 도달하지 않을 수 있다.
- 이번 보강은 `_compressImage()`에 15초 타임아웃, 이미지 파일 검증, 디코딩 실패 메시지를 추가한다.
- Supabase Storage 경로는 이미 ASCII-safe helper를 사용하므로 이번 변경에서 SQL이나 Storage policy는 건드리지 않는다.
