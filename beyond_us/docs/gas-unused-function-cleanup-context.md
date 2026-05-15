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

## 보류 대상

코드 내부 참조가 없어도 `doGet`, `doPost`, `migrate*`, `prodCutover*`, `backupSpreadsheet`, `admin*`, `test*`, `debug*`, password migration 함수는 수동 실행 가능성이 있어서 보류한다.

정적 분석에서 선언 외 참조가 없는 public 함수 후보는 다음과 같다. 이 목록은 GAS 함수 드롭다운 정리 후보지만, 운영자가 수동 실행할 수 있어 이번 커밋에서는 보류했다.

- `setRequiredScriptProperties`
- `doGet`
- `doPost`
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
