# Supabase 전환 계획

## 목표

Google Sheet와 GAS 기반의 데이터 저장, 집계, 서버 로직을 Supabase Postgres와 Supabase Auth, Edge Functions 또는 RPC 기반으로 이전한다.

## 전환 원칙

- 화면 HTML/CSS는 최대한 유지한다.
- `app.js`와 `admin.html`의 GAS 호출부는 `apiClient` 계층을 통해 단계적으로 교체한다.
- 데이터는 유저 중심으로 조회할 수 있게 만들되, 물리 테이블은 기능별로 분리한다.
- `events`는 원장으로 유지하고, `user_cards`, `user_inventory`, `user_summary`는 빠른 조회용 현재 상태 테이블로 둔다.
- 사진과 PDF 같은 파일은 Postgres 셀에 base64로 넣지 않고 Supabase Storage에 저장한다.
- 비밀번호는 별도 컬럼에 저장하지 않고 Supabase Auth로 이전한다.
- 사용자는 계속 아이디와 비밀번호로 로그인하지만, 내부 Auth 식별자는 `login_id`에서 만든 synthetic email을 사용한다.
- `login_id`는 대소문자를 구분한다.

## 1차 범위

1. 현재 GAS action 전체 목록과 호출 지점을 정리한다.
2. action별로 기존 Sheet, Events, 캐시 역할을 Supabase 테이블과 RPC로 번역한다.
3. Supabase 스키마 초안을 만든다.
4. 기존 프론트와 관리자 페이지가 호출할 API map을 만든다.

## 권장 구현 순서

1. Supabase 프로젝트 생성과 Auth 정책 확정.
2. `profiles`, `events`, `user_inventory`, `user_cards`, `raffle_tickets`부터 migration 작성.
3. Auth 가입, 로그인, 비밀번호 재설정 Edge Function을 작성한다.
4. Storage bucket 생성.
5. `get_user_status`, `submit_mission`, `draw_card_pack`부터 RPC 또는 Edge Function 구현.
6. `app.js`에 GAS와 Supabase를 교체 가능한 `apiClient` 계층 추가.
7. DEV에서 Supabase API만 연결해 기능 검증.
8. Sheet 데이터를 Supabase로 이관.
9. 관리자 기능을 Supabase 기준으로 전환.
10. PROD 전환 전 GAS와 Sheet는 읽기 전용 백업으로 유지.
