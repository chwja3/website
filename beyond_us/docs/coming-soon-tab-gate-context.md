# Coming Soon 탭 게이트 Context

2026-05-26. 운영자가 B.B.B 미션과 천로역정 탭에 날짜 태그를 붙였지만, 사용자가 Coming Soon 상태의 탭을 누르면 실제 기능 화면이 열리는 문제가 확인됐다.

현재 구조는 `applyDrawerTabState()`가 `status !== open`일 때 drawer 항목에 회색 스타일과 날짜 태그만 붙이고, `switchSection()`은 그대로 실제 섹션을 연다. 그래서 B.B.B가 Coming Soon이어도 일반 유저가 BBB 상세 박스와 사진 업로드 UI를 볼 수 있다.

수정 방향은 메뉴 노출 상태와 기능 진입 상태를 분리하는 것이다. `enabled=false`는 숨김, `enabled=true/status=closed`는 메뉴 표시 + 안내 페이지, `enabled=true/status=open`은 실제 기능 진입으로 해석한다.

구현 후 상태는 다음과 같다. `sectionComingSoon` 공통 안내 섹션을 추가했고, `switchSection()`이 `status !== open`인 탭 요청을 실제 섹션 대신 안내 섹션으로 라우팅한다. B.B.B 미션은 `6/20 Open`, 천로역정은 `6/21 Open` 날짜와 짧은 설명을 보여준다. 이 상태에서는 `loadBBB()`가 호출되지 않으므로 일반 유저가 BBB 상세 UI나 천로역정 지도/업로드 UI에 진입하지 않는다.

추가로 로그인 후 idle preload에서 BBB 데이터를 백그라운드로 불러오던 경로도 막았다. `secret` 또는 `pilgrim` 탭 중 하나라도 실제 `open` 상태일 때만 BBB 데이터를 미리 불러오고, 둘 다 Coming Soon 또는 숨김 상태이면 숨겨진 DOM도 채우지 않는다.
