# Supabase PROD 안정화 핫픽스 컨텍스트

2026-05-19. PROD 전환 후 관리자 시스템 상태 audit에서 일부 유저의 `missionCount`, `totalCards`가 원천 테이블 기준 기대값보다 1 크게 나오는 사례가 반복 보고되었다. 기존 RPC는 `mission_submissions` 또는 `user_cards`를 쓴 뒤 `events`를 쓰고, 마지막에 `user_summary`를 직접 `+1` 하는 구조였다. 동시에 source table trigger가 summary를 재계산하므로, trigger가 먼저 실행되고 RPC의 수동 증가가 마지막에 남으면 과집계가 생길 수 있다.

2026-05-19. 이전 보정은 `events` trigger만 deferred로 바꾸었다. 그러나 카드와 추첨권은 `user_cards`, `raffle_tickets` trigger도 함께 움직이므로 summary 관련 trigger를 트랜잭션 마지막에 실행되도록 통일하는 쪽이 더 안정적이다.

2026-05-19. H&P 서버 연결 오류는 프론트 fallback 문제가 아니라 Supabase RPC 런타임 오류 가능성이 높다. 특히 `ticketCardIdx`를 읽을 때 오래된 이벤트 payload에 숫자가 아닌 값이 들어 있으면 캐스팅 오류가 날 수 있어, 숫자 문자열일 때만 integer로 바꾸도록 보정했다.

2026-05-19. H&P 조회, 정답 제출, 힌트 요청은 모두 같은 3장 선택 기준을 공유해야 한다. 이를 위해 `bu_hold_pray_cards_for_profile` helper를 추가하고 세 RPC가 이 helper를 사용하도록 했다.

2026-05-19. 비밀번호 초기화 이후 미션을 제출한 사용자에게 mismatch가 반복된다는 보고가 있었다. 비밀번호 초기화 자체가 summary를 바꾸는 것은 아니지만, 초기화 후 정상 Supabase Auth 세션으로 미션 제출을 수행하면 `submit_pre_mission`의 기존 수동 `user_summary.mission_count + 1` 경로가 다시 실행된다. 원천 테이블 기준 재계산과 수동 증가가 섞이는 구조 자체가 위험하므로, 미션 제출과 카드 뽑기 RPC에서 수동 summary 증가를 제거하고 마지막에 `bu_refresh_profile_summary`만 호출하도록 보정했다.

2026-05-19. H&P 서버 오류가 계속될 가능성에 대비해 `bu_hold_pray_cards_for_profile`의 반환 컬럼과 내부 `picked_cards` 컬럼명이 겹치지 않도록 `pc.` alias를 명시했다. SQL 함수의 출력 컬럼명과 select 컬럼명이 겹칠 때 PostgreSQL에서 ambiguous column 오류가 날 수 있기 때문이다.
