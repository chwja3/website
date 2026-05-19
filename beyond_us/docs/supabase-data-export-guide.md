# Supabase 데이터 이관용 Sheet JSON export 가이드

## 목적

Google Sheet 데이터를 CSV가 아니라 JSON으로 export한다. 한글 깨짐을 피하고, 원본 시트명, 행 번호, 헤더, row hash를 함께 보존하기 위해서다.

## 실행 함수

DEV GAS에서는 아래 함수를 실행한다.

```text
exportSupabaseMigrationJsonDev
```

PROD GAS에서는 나중에 서버 점검 상태로 전환한 뒤 아래 함수를 실행한다.

```text
exportSupabaseMigrationJsonProd
```

두 함수 모두 Sheet나 Supabase 데이터를 변경하지 않는다. 현재 연결된 Google Sheet를 읽어서 Google Drive에 JSON 파일 하나를 만든다.

## 보안 주의

생성된 JSON에는 사용자 정보, 기존 비밀번호 해시, 문의 내용, BBB 사진 base64가 포함될 수 있다. 이 파일은 운영 데이터 원본 스냅샷이므로 외부에 공유하지 말고, Supabase 이관 검증이 끝날 때까지 Drive에서 보관한다.

## 출력 파일

파일명은 아래 형식이다.

```text
beyond_us_supabase_export_<dev|prod>_YYYYMMDD_HHMMSS.json
```

GAS 실행 결과에는 다음 값이 표시된다.

| field | 의미 |
|---|---|
| `fileName` | 생성된 JSON 파일 이름 |
| `fileId` | Google Drive 파일 ID |
| `fileUrl` | 파일을 열 수 있는 Google Drive URL |
| `rowCounts` | 시트별 export row 수 |
| `missingSheets` | export 대상인데 현재 Sheet에 없는 탭 |

## JSON 구조

```json
{
  "exportVersion": 1,
  "sourceEnvironment": "dev",
  "sourceSpreadsheetId": "...",
  "sourceSnapshotLabel": "dev_20260517_223000",
  "exportedAt": "2026-05-17T13:30:00.000Z",
  "sheets": [
    {
      "sheetName": "Users",
      "headerRow": 1,
      "dataStartRow": 2,
      "headers": ["nickname", "password", "..."],
      "rows": [
        {
          "rowNumber": 2,
          "rowKey": "Oh! New",
          "sourceHash": "...",
          "values": ["Oh! New", "..."],
          "object": { "nickname": "Oh! New" }
        }
      ]
    }
  ]
}
```

## DEV 확인 절차

1. DEV Apps Script에 최신 `Apps_Script`를 반영한다.
2. GAS 편집기 함수 선택에서 `exportSupabaseMigrationJsonDev`를 실행한다.
3. 실행 결과의 `ok`가 `true`인지 확인한다.
4. `fileUrl`을 열어 JSON 파일이 생성됐는지 확인한다.
5. `rowCounts.Users`, `rowCounts.Events`, `rowCounts.Collection`, `rowCounts.RaffleTickets`가 예상과 크게 다르지 않은지 확인한다.
6. `missingSheets`는 일부 legacy 탭이 실제로 없으면 나올 수 있다. 핵심 탭인 `Users`, `Events`, `Collection`, `RaffleTickets`가 빠지면 중단한다.

## PROD 적용 메모

PROD에서는 같은 함수를 쓰되 `exportSupabaseMigrationJsonProd`만 실행한다. 이 파일이 PROD 이관의 원본 스냅샷이 되므로, 생성된 Drive 파일은 삭제하지 않는다.
