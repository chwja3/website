# H&P 랜덤 노출과 자동 초성 힌트 컨텍스트

2026-05-19. PROD Supabase 전환 후 H&P 탭에서 사용자별 3명이 아니라 모든 기도제목이 보이는 문제가 보고됐다. 원인은 `get_hold_pray` RPC가 visible H&P entries 전체를 반환하고 있었기 때문이다.

2026-05-19. 수정 방향은 프론트 필터링이 아니라 서버 RPC 수정이다. 전체 기도제목을 브라우저로 내려보내지 않도록 `get_hold_pray`에서 본인 제외 3장만 반환한다.

2026-05-19. `submit_hold_pray_guess`, `post_hold_pray_hint`도 같은 card index 기준을 써야 하므로 세 RPC가 같은 deterministic random ordering을 공유해야 한다. 정렬 seed는 `profile_id + week_key + hold_pray_entry_id`를 사용한다.

2026-05-19. 기존 “힌트 요청 접수/운영진 대기” 흐름은 중단하고, `post_hold_pray_hint`가 작성자 이름 초성을 즉시 반환하도록 한다. 신규 힌트 요청은 `Inquiries`에 남기지 않는다.

2026-05-19. `20260519000100_hp_random_cards_auto_hints.sql`을 추가했다. `get_hold_pray`, `submit_hold_pray_guess`, `post_hold_pray_hint`는 모두 같은 deterministic 3장 선택 기준을 사용한다.

2026-05-19. 앱 버전은 `20260519h`로 올렸다. H&P 캐시에 `clientVersion`을 넣어 이전 전체 목록 캐시를 폐기하고, 힌트 요청 성공 시 `hintText`를 즉시 화면과 캐시에 반영한다.

2026-05-19. 힌트 row에 `hold_pray_entry_id`를 추가했다. 기존 구조는 `card_index`만 저장해서 랜덤 3장 기준이 바뀌면 오래된 힌트가 다른 카드에 붙을 수 있었기 때문이다. 새 `get_hold_pray`는 같은 entry id에 붙은 힌트만 재사용한다.
