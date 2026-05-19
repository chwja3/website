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
- admin 로그인은 staff로 체크된 사람의 앱 아이디와 비밀번호로 Supabase Auth에 로그인한다.
- 로그인한 Supabase Auth 유저가 `profiles.role in ('admin','dev')` 또는 `is_dev=true` 조건을 통과해야 admin 화면에 들어간다. Sheet 이관 시 `Users.isStaff=true`는 `profiles.role='admin'`으로 변환된다.
- 카드 수동 지급과 회수는 Supabase `user_cards`, `events`, `user_summary`에 반영된다.
- 파생 상태 재계산은 Supabase 테이블 기준으로 `user_summary`와 추첨권 정책 상태를 갱신한다.
- 관리자 비밀번호 초기화는 Supabase Auth Admin API로 처리되고 GAS로 쓰지 않는다.
- 주요 정본 테이블 변경 후 `user_summary`가 trigger로 자동 refresh된다.
- 카드 조건이 더 이상 충족되지 않으면 해당 조건 추첨권이 회수되고 번호가 재사용 가능 상태가 된다.
