# 사용자 요약 audit mismatch 수정 컨텍스트

2026-05-19. 시스템 상태 `audit`에서 `missionCount`와 `totalCards` mismatch가 보고됐다. mismatch 패턴은 `actual`이 `expected`보다 1 큰 형태였다.

2026-05-19. 원인은 정본 테이블이 아니라 `user_summary` 갱신 순서다. `submit_pre_mission`과 `draw_card`는 각각 `mission_submissions` 또는 `user_cards`를 변경하고 `events`를 쓴 뒤, 함수 끝에서 `user_summary`를 직접 `+1` 한다. 동시에 trigger도 정본 테이블 기준으로 summary를 다시 계산한다. trigger가 먼저 실행되고 함수 말미의 직접 `+1`이 마지막에 남으면 summary가 과집계된다.

2026-05-19. 큰 RPC를 다시 복사해 덮는 대신, `events`의 summary refresh trigger를 deferrable constraint trigger로 바꾼다. 미션 제출과 카드 뽑기는 모두 events를 남기므로 transaction 마지막에 정본 기준 재계산이 한 번 더 실행되어 직접 `+1`을 덮어쓴다.
