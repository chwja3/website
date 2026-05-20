# 2026-05-21 main 반영 컨텍스트

## 확인 결과

- 현재 작업 브랜치는 `dev`다.
- `git cherry -v main dev` 기준 H&P 복구, H&P admin 작성, H&P 익명 정책 커밋은 main에 이미 동일 패치로 들어가 있다.
- main에 없는 신규 SQL은 `20260521000100_pilgrim_assignment_on_status_read.sql`와 `20260521000200_admin_bbb_pilgrim_status_restore.sql` 두 개다.
- `dev`에는 `beyond_us/supabase/verification/prod_20260520_hp_admin_combined.sql` 파일이 없지만, main에는 있으므로 merge 시 보존한다.

## 사용자가 직접 할 작업

- Supabase Storage 업로드는 사용자가 수동으로 한다.
- bucket은 `beyond-us-photos`, prefix는 `QT`, 파일명은 `YYMMDD.png`다.

## 주의

- Q.T. 앱 코드는 Storage URL을 우선 로드하고 local fallback을 유지한다.
- 새 BBB 사진 경로만 `BBB_missions` 하위로 바뀌며, 기존 DB에 저장된 옛 사진 경로는 계속 읽힌다.
