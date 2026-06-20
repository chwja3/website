# 2026-06-21 BBB/천로역정 오픈 설정 핫픽스 컨텍스트

안성재의 활성 프로필은 `카니보어시즌2`이며 BBB 매칭, 조 roster 매칭, 천로역정 `pilgrim_assignments`가 존재한다. 천로역정 배정 스팟은 `[1,4]`로 확인됐다.

PROD `tab_settings`에서는 `pilgrim`이 `enabled=true`, `status=open`이다. 그러나 `app_settings`의 `bbb_settings` 값에 `m3`가 없고, 앱의 기본 `_bbbSections.m3.open`은 `false`다. 앱은 `applyTabSettings()`에서 서버의 `bbbSections`를 병합하므로 `m3`가 누락되면 천로역정 탭이 열려 있어도 Mission 3 영역은 Coming Soon으로 남을 수 있다.

BBB Mission 1/2는 `bbb_settings.m1.open=true`, `bbb_settings.m2.open=true`로 확인됐다. 따라서 Mission 1/2 제출 실패가 계속되면 탭 오픈 설정보다는 실제 업로드 오류, 스토리지 경로 오류, 인증 세션, 또는 RPC 응답 메시지를 확인해야 한다.

관리자 `saveBBBSections()`는 기존에 `m3`만 담은 `bbbSections`를 전송했다. 서버의 `setTabSettings`는 `bbbSections`를 통째로 저장하므로, 이 상태로 저장하면 기존 BBB 섹션 값이 부분적으로 사라질 수 있다. admin 저장 로직은 기존 `_bbbSectionsData`를 복사한 뒤 `m3.open`만 갱신하도록 수정했다.
