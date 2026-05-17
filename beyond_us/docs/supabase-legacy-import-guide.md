# Supabase legacy row import 가이드

## 목적

GAS에서 생성한 JSON export 파일을 Supabase의 `migration_batches`와 `legacy_sheet_rows`에 적재한다. 이 단계는 원본 row 보관 단계이며, 아직 `profiles`, `events`, `user_cards` 같은 정규 테이블 변환은 수행하지 않는다.

## 준비물

- GAS에서 생성한 `beyond_us_supabase_export_dev_YYYYMMDD_HHMMSS.json` 파일.
- Supabase Project URL.
- Supabase service role key.

service role key는 절대 코드나 문서에 저장하지 않는다. PowerShell 세션 환경변수로만 넣는다.

## Dry Run

먼저 로컬에서 JSON 구조와 row count만 확인한다.

```powershell
node "beyond_us\tools\supabase_import\import_legacy_rows.mjs" --file "C:\path\to\beyond_us_supabase_export_dev_YYYYMMDD_HHMMSS.json" --dry-run
```

확인할 항목은 `sourceEnvironment`, `rowTotal`, `rowCounts`, `missingSheets`다.

## Apply

Supabase에 실제 적재할 때는 PowerShell에서 환경변수를 먼저 설정한다.

```powershell
$env:SUPABASE_URL="https://프로젝트-ref.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="Supabase service role key"
node "beyond_us\tools\supabase_import\import_legacy_rows.mjs" --file "C:\path\to\beyond_us_supabase_export_dev_YYYYMMDD_HHMMSS.json" --apply
```

성공하면 출력에 `batchId`, `imported`, `chunks`가 표시된다.

## Supabase 확인 쿼리

SQL Editor에서 아래를 실행한다.

```sql
select source_environment, source_snapshot_label, status, row_counts
from public.migration_batches
order by created_at desc
limit 5;

select source_environment, sheet_name, count(*) as rows
from public.legacy_sheet_rows
group by source_environment, sheet_name
order by sheet_name;
```

`legacy_sheet_rows`의 시트별 row 수가 export의 `rowCounts`와 맞으면 1차 적재가 완료된 것이다.

## 재실행 정책

`legacy_sheet_rows`는 `(source_environment, sheet_name, row_number)` 기준으로 upsert한다. 같은 DEV export를 다시 실행하면 같은 원본 row는 덮어쓴다. 단, 새 export 파일을 다시 만들었는데 같은 row number의 내용이 달라졌다면 `source_hash`와 `row_payload`가 최신 내용으로 갱신된다.

## 다음 단계

1차 적재가 끝나면 다음 구현에서 `legacy_sheet_rows`를 읽어 `profiles`, `events`, `raffle_tickets`, `mission_photo_submissions` 등 정규 테이블로 변환한다.
