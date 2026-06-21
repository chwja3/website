# BBB 들킴 배지 오류 수정 컨텍스트

- 현재 `caughtByBuddy`는 `other_assignment.care_buddy_id = 현재 사용자`와 `other_assignment.secret_revealed = true`를 기준으로 계산한다.
- 이 조건은 “나를 케어버디로 둔 사람이 자신의 시크릿버디를 맞췄는지”를 보는 구조라서, 내가 돌보는 상대가 나를 맞췄는지와 방향이 다르다.
- 올바른 조건은 “내가 돌보는 대상의 assignment가 `secret_revealed = true`이고, 그 대상의 `secret_buddy_id`가 나인지”다.
- TF가 여러 명을 추가 케어버디로 맡는 경우도 있으므로 `bbb_extra_care_roster_links`에 연결된 대상까지 함께 본다.
- 프론트는 `caughtByBuddy` 값을 표시만 하므로 이번 수정은 SQL RPC에서 해결한다.
