# BBB/천로역정 승인 화면 통합 계획

## 목표

관리자 `BBB/천로역정` 탭에서 BBB Mission 1, Mission 2 사진 승인과 천로역정 Mission 3 스팟 2개 승인을 유저별 한 카드에서 한 번에 확인하고 처리할 수 있게 한다.

## 범위

- `admin.html`의 BBB/천로역정 탭 UI를 정리한다.
- Supabase RPC는 기존 `admin_bbb_pilgrim_status()` 응답을 우선 활용한다.
- 사용자 앱 로직과 승인 RPC 동작은 바꾸지 않는다.

## 검증

- `admin.html` 인라인 스크립트 문법 검사를 통과한다.
- `git diff --check`를 통과한다.
- Mission 1, Mission 2, Mission 3 스팟 카드가 같은 유저 카드 안에 렌더링된다.
