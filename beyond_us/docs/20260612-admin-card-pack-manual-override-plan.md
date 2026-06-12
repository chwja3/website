# 2026-06-12 관리자 카드 뽑기권 수동 지급 계획

## 목표
- 앱 가입자 탭의 누락 보상 지급에서 카드 뽑기권은 조건 미충족이어도 관리자가 수동 지급할 수 있게 한다.
- 이미 같은 보상을 받은 경우에는 중복 지급을 막는다.
- 추첨권 보상은 기존처럼 조건 충족 여부를 유지한다.

## 구현 방향
- `admin_get_user_reward_opportunities`는 `card_pack` 항목의 `available`을 조건 충족이 아니라 미지급 여부 기준으로 내려준다.
- `admin_issue_user_missed_reward`는 사전미션과 H&P 카드 뽑기권에서 조건 미충족 오류를 내지 않고 직접 카드 뽑기권 1장을 지급한다.
- 지급 이벤트에는 `adminManualOverride`와 `conditionMet`을 payload에 남겨 나중에 감사할 수 있게 한다.
- admin 안내 문구는 “조건 미충족도 카드 뽑기권은 수동 지급 가능”으로 바꾼다.
