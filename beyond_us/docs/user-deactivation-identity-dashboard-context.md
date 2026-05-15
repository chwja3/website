# 유저 비활성화, 대소문자 정규화, 대시보드 집계 컨텍스트

## 결정

유저 삭제는 하드 삭제가 아니라 `inactive=true` soft delete로 처리한다. 복구 가능성을 위해 `Events`는 보존한다. `Collection`은 projection이므로 삭제해도 복구 시 Events 기준으로 다시 만들 수 있다. `RaffleTickets`는 운영 번호 풀이라 삭제 시 회수하고, 복구 시 현재 조건 기준으로 다시 발급한다.

## 삭제 시 처리

- `Users.inactive=true`, `Users.inactiveAt=현재 시각`.
- `sessionToken`, `sessionUpdatedAt` 제거로 기존 로그인 세션 차단.
- 활성 RaffleTickets는 번호 풀로 회수.
- Collection 행 삭제.
- RetreatAttendance, CardReceived, HPGuesses, BBBPhotos, BBB, BBBMessages, Trades, Inquiries 같은 연결 운영 데이터는 admin/앱 표시와 통계에서 빠지도록 정리한다.
- Events는 남긴다.

## 대소문자 정책

닉네임은 시트에 저장된 표기를 canonical 값으로 사용한다. 비교는 대소문자 구분 없이 한다. 새 이벤트와 projection은 가능한 한 canonical 닉네임으로 기록한다. 기존 mixed-case 데이터는 진단 함수로 확인하고, 필요하면 별도 apply 함수로 정규화한다.

## 대시보드 제출 수 정책

admin 대시보드의 “이번 주 제출 수”는 클릭 횟수가 아니라 해당 주차에 mission.submitted 이벤트를 1개 이상 가진 active 유저 수다. 항목별 체크 수는 기존처럼 해당 항목을 체크한 수를 보여주되 inactive 유저는 제외한다.

## 구현 메모

- admin 앱 가입자 탭은 active 유저 목록과 삭제 유저 목록을 분리한다.
- 삭제 버튼은 `adminDeactivateUser`를 호출한다. 이 함수는 `Users` 행을 inactive로 표시하고 세션을 제거한 뒤, 추첨권을 회수하고 Collection 및 연결 운영 시트 행을 삭제한다.
- 복구 버튼은 `adminRestoreUser`를 호출한다. 복구 시 `Events` 기준으로 Collection을 재빌드하고 현재 조건 기준으로 추첨권을 다시 발급한다. BBB 사진, 문의, H&P 제출처럼 삭제 시 행이 제거된 운영 데이터는 자동 복원하지 않는다.
- `auditUserIdCaseConsistency`를 GAS 편집기에서 직접 실행하면 Users 중복, 시트별 대소문자 불일치, 알 수 없는 유저 참조를 확인할 수 있다.
- 로컬 검증으로 `node --check beyond_us/Apps_Script`와 admin inline script 문법 검사를 통과했다.
