# 2026-06-14 카드 별칭 SQL 매핑 컨텍스트

## 배경

- 앱 사용자 화면은 덕목명 카드명을 사용한다.
- 관리자 화면은 별칭 카드명인 사모, 라라, 달래, 오참, 네헤, 더무, 고, 엔, 버터를 사용한다.
- SQL/RPC 결과는 아직 `cards.name`을 그대로 사용해서 5번이 자비, 6번이 양선으로 보일 수 있다.

## 결정

- DB의 `cards.name` 값은 변경하지 않는다.
- SQL 출력 전용 함수 `bu_card_alias(card_id)`로 별칭을 계산한다.
- 운영용 SQL view와 관리자 카드 통계 RPC에서는 별칭을 기본 표시명으로 사용하고, 덕목명은 `virtueName` 또는 `virtue_name`으로 별도 제공한다.

## 구현 기록

- `bu_card_alias(5)`는 `네헤`, `bu_card_alias(6)`은 `더무`를 반환한다.
- `admin_card_stats()`는 `cardName`을 별칭으로 내려주고 `virtueName`을 추가한다.
- `ops_cards`, `ops_events`, `ops_user_cards`, `ops_trades`, `ops_physical_card_receipts`는 카드 별칭을 표시명으로 사용한다.
- `prod_20260614_dev_to_main_combined.sql`에 `20260614000200_card_alias_sql_mapping.sql`을 포함했다.

## 검증 기록

- `git diff --check` 통과.
- 충돌 표식 검색 결과 없음.
- 통합 SQL source 블록 18개 확인.
- migration 안에서 `bu_card_alias(5) = 네헤`, `bu_card_alias(6) = 더무` 매핑 확인.
