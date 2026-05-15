# GAS Unused Function Cleanup Context

## 결정

GAS에서는 코드 안에서 직접 호출되지 않아도 함수 드롭다운, 웹앱 entry point, 운영 수동 실행으로 사용되는 함수가 있다. 그래서 이번 정리는 내부 전용 함수 중 선언 외 참조가 없는 함수만 대상으로 한다.

## 주석처리 대상

정적 분석 기준은 top-level 함수 선언 440개 중 이름이 `_`로 끝나는 내부 함수이고, 선언 외 참조가 없는 함수다.

- `getUserActiveMap_`
- `getCollectionCardIndex_`
- `getMissionThresholdMap_`
- `findUserRow_`
- `clearHotCaches_`
- `getRaffleEligibilityFromParish_`

## public manual-only 비활성화 대상

다음 함수들은 admin/app 호출이 없고 GAS 내부 참조도 없어 주석처리했다.

- `setRequiredScriptProperties`
- `Events_append`
- `migrate_step4_splitConfig_dryRun`
- `migrate_step5_absorbToEvents_dryRun`
- `hideLegacyDevSheets`
- `migrateHoldPrayToSheet`
- `getBonusDrawCount`
- `fixHoldPrayBlankNames`
- `testDriveAuth`
- `migrateUserPasswordsToHashDryRun`
- `migrateUserPasswordsToHashApply`
- `adminNormalizeRaffleTicketColumn`
- `rebuildCollectionSheet`
- `addHoldPrayRows`
- `fixHoldPrayTypos`

## 유지 대상

`doGet`, `doPost`, 라우터 action으로 연결된 함수, admin UI에서 호출하는 함수, app UI에서 호출하는 함수는 유지한다.
