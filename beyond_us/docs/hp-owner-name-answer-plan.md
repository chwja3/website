# H&P owner_name_input 정답 판정 Plan

## 목적

H&P 기도제목이 실제 유저 프로필과 연결되어 있지 않아도, 관리자 매칭에서 남긴 `owner_name_input`과 사용자가 입력한 이름이 같으면 정답으로 처리한다.

## 범위

1. H&P 정답 이름을 `profiles.name` 우선, 없으면 `hold_pray_entries.owner_name_input`으로 계산한다.
2. `submit_hold_pray_guess`의 정답 판정을 새 기준으로 바꾼다.
3. `get_hold_pray`의 `correctMap`도 새 기준으로 맞춘다.
4. 기존 응답 재계산 함수도 같은 기준을 쓰게 한다.
5. 익명 카드 제출 차단 정책은 그대로 유지한다.

## 검증 기준

- SQL 파일에 문법상 끊긴 dollar quote가 없어야 한다.
- `owner_name_input`만 있는 비익명 H&P 엔트리도 이름이 맞으면 `correct=true`가 된다.
- 프로필이 연결된 기존 엔트리는 기존처럼 실명 기준으로 정답 처리된다.
