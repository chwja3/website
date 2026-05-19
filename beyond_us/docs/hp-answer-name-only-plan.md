# H&P 정답 실명 기준 고정 계획

## 목표

H&P 정답 판정을 사용자 아이디나 닉네임이 아니라 `profiles.name` 기준으로만 맞춘다. 힌트는 기존처럼 실명 초성만 보여준다.

## 범위

1. 현재 H&P RPC의 정답 판정 후보를 확인한다.
2. 정답 비교용 정규화 함수를 추가한다.
3. `get_hold_pray`의 `correctMap`을 실명 기준으로만 반환하게 한다.
4. `submit_hold_pray_guess`의 정답 판정을 실명 기준으로만 저장하게 한다.
5. 기존 `hold_pray_guesses.correct` 값을 실명 기준으로 재계산한다.
6. 변경을 `dev`에 커밋한 뒤 `main`으로 반영한다.

## 검증 기준

- SQL 마이그레이션에 `login_id` 또는 `display_name` 기반 정답 후보가 들어가지 않는다.
- `git diff --check`가 통과한다.
- `main` 브랜치가 `dev`의 H&P 패치를 포함한다.
