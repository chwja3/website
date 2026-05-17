# Supabase 전환 컨텍스트

## 배경

현재 Beyond Us 앱은 `app.html`, `app.js`, `admin.html`이 GAS Web App을 호출하고, GAS가 Google Sheet를 데이터베이스처럼 사용한다. 최근 Events, Collection, UserDashboard, RaffleTickets, BBBPhotos, MissionProgress 같은 보조 시트가 늘어나면서 조회와 집계가 무거워졌다.

## 결정

- Supabase 전환은 단순 DB 교체가 아니라 GAS 서버 로직 제거까지 포함한다.
- 기존 HTML 구조와 디자인은 최대한 유지한다.
- 프론트에서 직접 테이블을 많이 읽는 방식보다, 보안과 집계를 위해 RPC 또는 Edge Function을 중심으로 둔다.
- 유저 화면은 `get_user_status` 같은 통합 API를 사용한다.
- 관리자 화면은 admin 전용 RPC와 view를 사용한다.
- 기존 GAS의 마이그레이션, cutover, Phase 2E 진단 action은 Supabase 이후 의미가 없어지므로 폐기 대상으로 둔다.
- 첫 migration은 `beyond_us/supabase/migrations/20260517000100_initial_schema.sql`에 작성했다.
- 첫 migration은 핵심 테이블, enum, 기본 seed, 인덱스, RLS 활성화까지 포함한다.
- 테이블과 주요 컬럼 설명은 `beyond_us/supabase/migrations/20260517000200_schema_comments.sql`에서 `COMMENT ON`으로 별도 관리한다.
- 실제 접근 정책은 다음 RLS migration에서 작성한다. 따라서 이 migration만 적용하면 service role 외 클라이언트 접근은 아직 막혀 있는 상태가 정상이다.

## 주요 리스크

- 기존 비밀번호 평문 또는 해시 방식에서 Supabase Auth로 넘어가는 계정 이관 전략이 필요하다.
- Google Sheet의 대소문자 민감 ID 문제를 Supabase에서는 `login_id` 유니크 정책으로 명확히 정해야 한다.
- 현재 앱은 `nickname`을 user id처럼 사용하므로, 내부 UUID와 표시용 아이디를 분리해야 한다.
- 사진 base64를 DB에 저장하면 성능과 비용이 악화되므로 Storage 이전이 필요하다.
- Events와 현재 상태 테이블의 동기화 규칙을 명확히 잡아야 한다.
