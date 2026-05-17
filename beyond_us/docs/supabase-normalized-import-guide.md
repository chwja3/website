# Supabase normalized data import 가이드

## 목적

`legacy_sheet_rows` 적재가 끝난 뒤, 같은 JSON export 파일을 기준으로 Supabase 정규 테이블을 채운다. 이 단계는 앱이 실제로 읽게 될 `profiles`, `events`, `user_inventory`, `user_cards`, `raffle_tickets`, H&P, BBB, 공지, 문의 테이블을 만드는 1차 변환이다.

## 현재 범위

이번 변환기는 Supabase Auth 계정 생성과 BBB 사진 Storage 업로드는 수행하지 않는다. 기존 사용자는 `profiles.password_migration_required=true`로 들어가고, BBB 사진은 원본 base64를 DB에 넣지 않고 `legacy://BBBPhotos/<rowNumber>` 형태의 임시 경로만 저장한다.

## Dry Run

```powershell
node "beyond_us\tools\supabase_import\import_normalized_data.mjs" --file "C:\path\to\beyond_us_supabase_export_dev_YYYYMMDD_HHMMSS.json" --dry-run
```

확인할 항목은 `targetCounts`와 `issuePreview`다. DEV `20260517_223159` 기준으로 `duplicate_tab_key` 경고 2개는 `qt`, `pilgrim` 중복 row 때문에 발생한 것으로, 마지막 row 기준으로 이관한다.

## Apply

```powershell
$env:SUPABASE_URL="https://프로젝트-ref.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="Supabase service role key"
node "beyond_us\tools\supabase_import\import_normalized_data.mjs" --file "C:\path\to\beyond_us_supabase_export_dev_YYYYMMDD_HHMMSS.json" --apply
```

성공하면 출력에 `batchId`, `targetCounts`, `operations`가 표시된다.

## Supabase 확인 쿼리

```sql
select source_environment, source_snapshot_label, status, row_counts->'targets' as targets
from public.migration_batches
order by created_at desc
limit 5;

select count(*) as profiles from public.profiles;
select count(*) as events from public.events;
select count(*) as active_raffle_tickets from public.raffle_tickets where active = true;
select count(*) as user_inventory from public.user_inventory;
select count(*) as user_cards from public.user_cards;
select count(*) as hold_pray_entries from public.hold_pray_entries;
select count(*) as inquiries from public.inquiries;
```

## 알려진 보류

- Auth 계정 생성과 비밀번호 재설정 흐름.
- BBB 사진 base64를 Supabase Storage로 이동.
- `legacy_import_refs` 세부 연결 기록.
- `Collection`, `UserDashboard`, `MissionProgress`와 Supabase projection의 mismatch 검증 쿼리.
