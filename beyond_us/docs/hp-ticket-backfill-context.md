# H&P 정답 보상 누락 보정 Context

2026-05-26. 운영 중 H&P 정답을 맞췄는데 뽑기권을 받지 못했다는 제보가 있었다. 제보자는 이미 한 명을 맞춘 상태였고, 한 장은 익명 카드였으며, 이후 다른 한 명을 추가로 맞췄다고 했다.

현재 `submit_hold_pray_guess`는 해당 제출이 `correct=true`일 때만 보상을 지급한다. 그러나 H&P 작성자 매칭 보정이나 `owner_name_input` 기준 정답 재계산으로 과거 응답이 나중에 정답이 될 수 있다. 이 경우 `hold_pray_guesses.correct`는 true가 되어도 `ticket.granted` 이벤트와 `user_inventory` 증가는 자동으로 생기지 않는다.

수정 방향은 H&P 보상 지급을 공통 helper로 분리하고, 정답 제출과 정답 재계산 모두 같은 helper를 호출하게 하는 것이다. helper는 같은 유저, 같은 주차의 H&P 보상이 이미 있으면 중복 지급하지 않는다.

구현 파일은 `20260526000200_hp_ticket_backfill.sql`이다. 이 파일은 `owner_name_input` 정답 판정, `get_hold_pray` 정답 표시 기준, `submit_hold_pray_guess` 보상 지급, `bu_recalculate_hold_pray_guesses` 누락 보상 backfill을 한 번에 덮어쓴다.
