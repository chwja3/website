# 2026-06-06 보이는 라디오 사연 컨텍스트

- 보이는 라디오 사연은 익명이며 공개 옵션이 없다.
- 사용자는 본인이 작성한 사연만 볼 수 있다.
- admin은 모든 사연을 모아보되 작성자 식별 정보는 받지 않는다.
- 상담 기능과 비슷하지만 답변 기능은 이번 범위에 포함하지 않는다.
- 탭 key는 DB에서 `visible_radio`, 앱 section에서는 `visibleRadio`를 사용한다. 앱에서는 두 key의 활성화와 상태 값을 모두 읽도록 처리했다.
- 검증은 `node --check beyond_us\app.js`, admin inline script 파싱, `git diff --check`, 충돌 마커 검색으로 진행했다.
