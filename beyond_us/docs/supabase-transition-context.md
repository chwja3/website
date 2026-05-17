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

## 주요 리스크

- 기존 비밀번호 평문 또는 해시 방식에서 Supabase Auth로 넘어가는 계정 이관 전략이 필요하다.
- Google Sheet의 대소문자 민감 ID 문제를 Supabase에서는 `login_id` 유니크 정책으로 명확히 정해야 한다.
- 현재 앱은 `nickname`을 user id처럼 사용하므로, 내부 UUID와 표시용 아이디를 분리해야 한다.
- 사진 base64를 DB에 저장하면 성능과 비용이 악화되므로 Storage 이전이 필요하다.
- Events와 현재 상태 테이블의 동기화 규칙을 명확히 잡아야 한다.
