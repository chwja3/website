# 2026-06-21 BBB/천로역정 오픈 설정 핫픽스 계획

## 목표

안성재 계정에서 BBB 미션 제출과 천로역정 2스팟 표시가 막히는 원인을 확인하고, PROD 설정에서 천로역정이 Coming Soon으로 해석되는 문제를 보정한다.

## 성공 기준

1. `bbb_settings`에 `m1`, `m2`, `m3`, `careBuddy`, `secretBuddy`, `msgOpen` 오픈 상태가 모두 명시된다.
2. `tab_settings`에서 `secret`과 `pilgrim`이 `enabled=true`, `status=open`으로 유지된다.
3. 앱은 `m3.open=true`를 받아 천로역정 배정 스팟 2개를 표시할 수 있다.
4. BBB 제출이 계속 실패하면 설정 문제가 아니라 업로드/RPC 오류 메시지로 다음 원인을 좁힐 수 있다.
