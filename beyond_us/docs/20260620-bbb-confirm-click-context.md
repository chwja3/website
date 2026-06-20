# BBB 확정 버튼 클릭 수정 컨텍스트

## 판단

- 문제 위치는 admin `B.B.B. 매칭` 화면의 `saveBBBMatchingRoster`를 호출하는 `확정` 버튼이다.
- 버튼은 `_bbbMatchingRows`를 기준으로 `innerHTML`로 다시 그려지는 동적 HTML 안에 있다.
- 동적 row의 클릭 버튼은 inline `onclick`보다 부모 컨테이너 click 위임이 안정적이다.

## 변경 방향

- `data-bbb-roster-confirm`을 확정 버튼에 부여한다.
- `data-bbb-care-save`를 케어버디 저장 버튼에 부여한다.
- `#bbbMatchBody`에 click listener를 붙여 버튼을 판별하고 기존 저장 함수를 호출한다.

## 검증

- `admin.html` inline script 파싱 결과 `parsed 1`을 확인했다.
- `node --check beyond_us/app.js`가 통과했다.
- `git diff --check`가 통과했다.
- `onclick="saveBBBMatching...` 패턴이 남아있지 않은 것을 확인했다.
