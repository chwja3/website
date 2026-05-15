# Case Variant User Data Context

## 문제

`userIdKey_()`가 닉네임을 소문자로 접어 비교한다. 그래서 `Oh! New`와 `oh! New`처럼 대소문자만 다른 Users 행이 동시에 있으면 inactive 행의 Collection, RaffleTickets가 active 행에 섞일 수 있다.

## 결정

- Users 시트에 정확한 닉네임 행이 존재하면 그 행의 active/inactive 상태를 우선한다.
- 정확한 닉네임 행이 inactive이면 같은 lower-case key의 active 유저로 자동 fallback하지 않는다.
- Users에 정확한 닉네임 행이 없는 예전 이벤트나 시트 흔들림은 active canonical 유저로 보정한다.
- repair apply는 inactive exact userId의 active raffle ticket을 회수하고, 등록되지 않은 case drift userId는 active canonical userId로 정규화한다.

## 운영 절차

1. DEV GAS에 `Apps_Script`를 수동 반영한다.
2. `repairCaseVariantUserDataDryRun`을 실행해 `Oh! New` 관련 release/rename 계획을 확인한다.
3. 계획이 맞으면 `repairCaseVariantUserDataApply`를 실행한다.
4. `rebuildCollectionRowsFromEvents`는 repair apply 내부에서 같이 실행되므로 따로 한 번 더 실행하지 않아도 된다.
