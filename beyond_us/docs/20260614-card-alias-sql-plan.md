# 2026-06-14 카드 별칭 SQL 매핑 계획

## 목표

SQL/RPC 결과에서도 관리자 카드 별칭을 표준으로 사용한다.

## 성공 기준

- `card_id = 5`는 SQL 출력에서 `네헤`로 보인다.
- `card_id = 6`은 SQL 출력에서 `더무`로 보인다.
- 운영용 view와 관리자 카드 통계 RPC는 별칭을 기본 카드명으로 내려준다.
- 기존 덕목명은 별도 컬럼으로 보존한다.

## 구현 범위

- `public.bu_card_alias(integer)` 함수를 추가한다.
- `public.admin_card_stats()`의 `cardName`을 별칭으로 바꾼다.
- `ops_cards`, `ops_user_cards`, `ops_physical_card_receipts`, `ops_trades` view에 별칭과 덕목명을 반영한다.
