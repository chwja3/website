# 사용자 요약 audit mismatch 수정 계획

목표.

1. `user_summary`가 미션 제출 또는 카드 뽑기 후 1씩 과집계되는 원인을 제거한다.
2. 정본 테이블인 `mission_submissions`, `user_cards`, `raffle_tickets`, `trades`, `events` 기준으로 summary가 최종 정리되게 한다.
3. 현재 PROD에 남아 있는 summary mismatch를 SQL 적용 시 한 번 보정한다.
4. admin 시스템 상태의 audit가 다시 `ok: true`로 돌아오게 한다.
