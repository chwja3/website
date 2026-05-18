# Supabase Admin 전환 계획

## 목표

admin 화면에서 운영자가 변경한 데이터가 Google Sheet가 아니라 Supabase에 저장되도록 전환한다. 단, 이미 폐기 예정인 cutover 함수와 재설계 예정 기능은 분리해서 다룬다.

## 우선순위

1. 공지 등록, 수정, 삭제를 Supabase로 고정한다.
2. admin에서 Supabase 지원 action이 GAS fallback으로 조용히 빠지지 않게 한다.
3. 남은 GAS 의존 action을 지원됨, 미구현, 폐기 예정으로 나눠 추적한다.
4. admin 로그인 자체를 Supabase Auth 기반으로 바꾼다.

## 성공 기준

- 공지 작성 시 `public.notices`에 row가 생긴다.
- 공지 이미지가 `beyond-us-photos/notices/...` Storage 경로에 올라간다.
- 사용자 앱이 Supabase read 모드에서 `get_notices()`로 공지를 읽는다.
- Supabase 관리자 세션이 없을 때 공지 쓰기가 GAS로 빠지지 않고 명시적 오류를 낸다.
- admin 로그인은 관리자 전용 비밀번호로 Supabase Auth에 로그인한다. 관리자 ID를 비워두면 공용 `admin` 계정을 사용한다.
- 로그인한 Supabase Auth 유저가 `profiles.role in ('admin','dev')` 또는 `is_dev=true` 조건을 통과해야 admin 화면에 들어간다.
