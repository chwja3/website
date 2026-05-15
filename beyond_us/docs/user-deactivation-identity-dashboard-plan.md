# 유저 비활성화, 대소문자 정규화, 대시보드 집계 계획

## 목표

admin에서 유저를 직접 삭제하지 않고 `inactive` 상태로 전환한다. 비활성 유저는 로그인, admin 일반 목록, 앱 통계, Collection/RaffleTickets 운영 데이터에서 제외한다. 단, `Events`는 복구 가능성을 위해 보존한다.

## 범위

1. `Users` 시트에 `inactive`, `inactiveAt` 컬럼을 추가한다.
2. admin 앱 가입자 탭에서 활성 유저와 삭제 유저를 분리해 보여준다.
3. 삭제 버튼은 유저를 inactive로 표시하고 세션을 제거하며, RaffleTickets 회수, Collection 행 삭제, 연결 운영 데이터 정리, 캐시 삭제를 수행한다.
4. 복구 버튼은 inactive를 해제하고 Events 기준으로 Collection을 재빌드하며 signup 추첨권을 보정한다.
5. 닉네임 비교는 대소문자 구분 없이 처리하되, 시트에 저장된 원래 표기 casing을 canonical 값으로 사용한다.
6. admin 대시보드의 이번 주 제출 수는 제출 이벤트 수가 아니라 해당 주차 참여 유저 수로 계산한다.

## 검증

- `node --check beyond_us/Apps_Script`.
- admin HTML 인라인 스크립트 파싱.
- `git diff --check`.
- Apps Script 수동 반영 뒤 DEV에서 유저 삭제, 복구, 로그인 차단, 통계 제외, 제출 수 계산을 확인한다.
