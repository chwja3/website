# BBB 확정 버튼 클릭 수정 계획

## 목표

admin의 B.B.B. 매칭 화면에서 이름 중복 확인 대상의 `확정` 버튼이 안정적으로 동작하게 한다.

## 범위

- 동적으로 렌더링되는 BBB 매칭 row의 `확정` 버튼을 inline `onclick` 의존에서 delegated click 처리로 바꾼다.
- 같은 영역의 케어버디 `저장` 버튼도 같은 방식으로 맞춰 클릭 안정성을 높인다.
- 기존 Supabase RPC와 데이터 구조는 변경하지 않는다.

## 검증

- `admin.html` inline script 파싱을 실행한다.
- `node --check beyond_us/app.js`를 실행한다.
- `git diff --check`를 실행한다.
