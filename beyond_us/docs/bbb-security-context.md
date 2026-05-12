# BBB 미션 보상 보안 패치 컨텍스트

## 문제

- `uploadBBBPhoto` 엔드포인트가 UI의 Coming Soon 상태와 별개로 직접 호출될 수 있었다.
- 기존 서버 로직은 사진 저장 후 `ticket.granted` 이벤트를 생성할 때 BBB 섹션 오픈 상태와 BBB 매칭 여부를 확인하지 않았다.
- `missionType`도 명시적으로 허용값을 제한하지 않아 `m3_0` 계열 외 값이 사진 저장 경로를 통과할 수 있었다.

## 결정

- 서버가 최종 권한 경계가 되도록 `uploadBBBPhoto`에서 직접 검증한다.
- 허용되는 `missionType`은 `m1`, `m2`, `m3_0`부터 `m3_6`까지로 제한한다.
- `m3_*` 요청은 BBBSettings의 `m3` 섹션 오픈 여부를 확인한다.
- 모든 BBB 사진 업로드 보상은 BBB 매칭 row와 `careBuddyId`가 있는 사용자에게만 허용한다.
- 이미 생성된 의심 보상은 이벤트를 삭제하지 않고, 음수 `ticket.granted` 보정 이벤트로 회수할 수 있게 한다.

## 한계

- 현재 BBBSettings에는 구조화된 `openAt` 날짜 컬럼이 없다.
- 따라서 날짜 가드는 하드코딩하지 않고 관리자 오픈 토글을 서버 권한으로 사용한다.
- 추후 날짜 자동 오픈이 필요하면 `BBBSettings`에 `openAt` 컬럼을 추가하는 방식이 더 안전하다.
