# Supabase 추첨권 정책 컨텍스트

2026-05-18 확인 결과, Supabase에는 `raffle_tickets` 읽기 경로와 기존 이관 데이터는 있었지만 신규 발급 정책이 공통 쓰기 경로에 붙어 있지 않았다. `get_user_status()`는 `raffle_tickets`를 읽어 사용자 UI를 만들지만, `draw_card_pack()`는 `user_cards`를 갱신한 뒤 카드 3종, 5종, 10종 조건의 추첨권을 발급하지 않았다.

정책은 앱 가입, 카드 3종, 카드 5종, 카드 10종 보유 기준 최대 4장이다. 수련회 참석 추첨권은 정책에서 제외되었고, admin의 참석 체크는 운영 정보로만 유지한다.

이번 보강은 카드 뽑기 함수 본문에 직접 정책을 박는 대신 `profiles`와 `user_cards` 변경 트리거에 연결했다. 이렇게 하면 카드 뽑기, 관리자 카드 조정, 추후 교환 동기화처럼 `user_cards`를 바꾸는 경로가 늘어나도 같은 정책 함수가 실행된다.

발급 제외 유저나 비활성 유저는 `bu_sync_profile_raffle_tickets()`가 활성 추첨권을 모두 회수한다. 회수된 번호는 `active=false` 상태로 돌아가며, 다음 발급 시 가장 낮은 회수 번호부터 재사용한다.

기존 이관 데이터는 트리거가 과거 행을 자동으로 다시 훑지 않기 때문에 `backfill_raffle_tickets()`를 DEV와 PROD에서 각각 한 번 실행해야 한다.

2026-05-18. admin 추첨권 번호 탭에 `누락 검사/보정` 버튼을 추가했다. 이 버튼은 관리자 세션으로 `admin_backfill_raffle_tickets()` RPC를 호출하고, 내부에서 기존 `backfill_raffle_tickets()`를 실행한다. 일반 사용자에게 보정 RPC를 직접 열지 않기 위해 `admin_backfill_raffle_tickets()`는 `bu_admin_profile()`을 먼저 통과해야 한다.
