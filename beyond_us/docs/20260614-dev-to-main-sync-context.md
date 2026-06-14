# 2026-06-14 dev to main 동기화 컨텍스트

## 확인한 차이

- dev에는 2026년 6월 6일부터 6월 14일까지의 신규 기능 커밋들이 있다.
- main에는 `fix(admin): 카드 뽑기권 수동 보상 조건 완화`, `fix(app): 교환 신청 최신 상태 재검증` 두 커밋이 dev에 없는 상태다.
- 따라서 dev를 main에 단순 덮어쓰기하지 않고 main 위에서 병합해야 한다.

## SQL 번들 원칙

- main에 없는 Supabase migration을 파일명 순서대로 합친다.
- 이미 main에 있는 `20260612000100_admin_card_pack_manual_override.sql`은 dev에서 `20260612000900_admin_card_pack_allow_unmet.sql`로 대체된 흐름이라, 최종 번들에는 dev 기준 신규 파일을 포함한다.
- 실제 Supabase 실행은 사용자가 수동으로 한다.

## 병합 기록

- `admin.html` 충돌은 dev의 뽑기권/추첨권 현황 UI를 유지하고, main의 카드 뽑기권 조건 미충족 수동 지급 안내를 합쳤다.
- `app.html` 충돌은 dev의 최신 캐시 버전 `20260614c`를 유지했다.
- 통합 SQL은 `beyond_us/supabase/verification/prod_20260614_dev_to_main_combined.sql`에 생성했다.
- dev의 오래된 `prod_20260609_main_pending_combined.sql`은 새 통합 SQL로 대체하므로 main 병합 결과에서 제외했다.

## 검증 기록

- `node --check beyond_us\app.js` 통과.
- `admin.html` 인라인 스크립트 파싱 통과.
- Git 충돌 표식 검색 결과 없음.
- `git diff --cached --check` 통과.
- 통합 SQL source 블록 17개 확인.
