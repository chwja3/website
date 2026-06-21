# 카드 보유 수량과 실물 수령 탭 불일치 컨텍스트

- 사용자 앱 컬렉션은 `get_user_status()` 응답의 `collection`을 렌더링하며, 해당 값은 `user_cards`에서 만들어진다.
- admin 실물 카드 수령 탭은 `admin_card_stats()` 응답의 `users[].cards[]`를 렌더링한다.
- 운영상 화면에서 헷갈리면 안 되는 기준은 `보유 수량 = user_cards.quantity`, `수령 수량 = physical_card_receipts.received_qty`다.
- 불일치 원인은 `admin_card_stats()`가 `card_id between 1 and 9`만 읽어서, 사용자 컬렉션에 포함되는 10번 레어 카드 `BetWeEn`을 admin 실물 카드 수령 탭에서 제외한 것이다.
- admin UI의 “뽑기” 문구는 실제 의미와 다르게 보일 수 있어서 “보유” 기준으로 고쳤다.
- `20260621000700_admin_card_stats_include_rare.sql`은 `admin_card_stats()`와 `bu_card_alias()`를 다시 정의해 카드 1~10번을 같은 기준으로 내려준다.
