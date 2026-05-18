# Supabase 추첨권 정책 체크리스트

- [x] 현재 Supabase 마이그레이션에서 추첨권 읽기 경로를 확인한다.
- [x] 신규 발급 경로가 빠져 있는지 확인한다.
- [x] 공통 발급 함수와 회수 함수를 추가한다.
- [x] `profiles` 변경 트리거를 추가한다.
- [x] `user_cards` 변경 트리거를 추가한다.
- [x] 기존 데이터 보정용 `backfill_raffle_tickets()`를 추가한다.
- [ ] DEV Supabase SQL Editor에서 마이그레이션을 실행한다.
- [ ] `select public.backfill_raffle_tickets();` 결과를 확인한다.
- [ ] 앱 가입, 카드 3종, 5종, 10종 조건별 보유 수를 SQL로 확인한다.
- [ ] 사용자 앱 컬렉션 화면의 추첨권 UI가 같은 값을 보여주는지 확인한다.
