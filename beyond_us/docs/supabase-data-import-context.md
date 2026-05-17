# Supabase 데이터 이관 컨텍스트

## 배경

사용자는 DEV 데이터를 먼저 Supabase로 가져와 검증하고, 이후 PROD 서버를 잠시 닫은 상태에서 같은 절차를 한 번에 수행하려고 한다. 기존 Sheet에는 현재 상태뿐 아니라 Events, hidden legacy 로그, 사진 base64, 문의와 공지 같은 운영 데이터가 섞여 있다.

## 결정

- 모든 Google Sheet row는 정규화 여부와 관계없이 `legacy_sheet_rows`에 보관한다.
- 정규 Supabase 테이블로 변환된 row는 `legacy_import_refs`로 원본 row와 연결한다.
- 이관 중 충돌과 누락은 `migration_issues`에 남긴다.
- DEV와 PROD는 같은 스크립트와 같은 검증 쿼리를 쓴다.
- `source_environment` 값은 `dev`와 `prod` 중 하나로 고정한다.
- `Collection`, `UserDashboard`, `MissionProgress`, `DashboardStats`는 projection 또는 cache 성격이므로 원본은 보관하지만 최종 상태는 재계산한다.
- `Events`는 원장으로 이관한다. 다만 hidden legacy 로그와 비교해 Events 누락이 확인되면 보강 이벤트를 만들고 issue에 기록한다.
- `BBBPhotos` base64는 Storage로 이동하고 DB에는 storage path만 저장한다. 원본 base64는 감사 row에 보관한다.
- 기존 사용자 비밀번호 해시는 가져오지 않고, Supabase Auth 계정은 임시 랜덤 비밀번호와 `password_migration_required=true`로 만든다.

## PROD에서 한 번에 해야 할 작업

1. 서버 점검 상태 전환.
2. PROD Sheet 사본 생성.
3. Supabase migration 적용 상태 확인.
4. 원본 row 전체 적재.
5. Auth와 profiles 생성.
6. 설정, Events, 도메인 데이터, 추첨권 이관.
7. 현재 상태 재계산.
8. 검증 쿼리 통과 확인.
9. 앱과 admin endpoint 전환.
10. smoke test.
11. 점검 해제.

## 다음 구현 후보

- Google Sheet export를 CSV 묶음으로 할지, Apps Script JSON export 함수로 할지 결정해야 한다.
- 현재 구조에서는 JSON export가 더 안전하다. 헤더 이름과 row number를 같이 보존할 수 있고, 한글 CSV 깨짐 문제를 피할 수 있기 때문이다.
- import 스크립트는 `tools/supabase_import` 아래에 Node 또는 Python으로 두는 방향이 좋다.
