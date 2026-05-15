# GAS Unused Function Cleanup Plan

## 목표

`Apps_Script` 안에 남아 있는 미사용 내부 함수를 정리해 GAS 유지보수 부담을 줄인다.

## 구현 방향

1. top-level `function name()` 선언을 기준으로 참조 횟수를 확인한다.
2. 이름이 `_`로 끝나는 내부 함수 중 선언 외 참조가 없는 함수만 주석처리한다.
3. `doGet`, `doPost`, migration, backup, security, admin helper처럼 GAS에서 수동 실행될 수 있는 public 함수는 보류한다.
4. 정리 후 `node --check`와 `git diff --check`를 실행한다.

## 검증 기준

- 주석처리 후 `Apps_Script` 문법 검사가 통과한다.
- public entry point와 수동 실행 함수는 남아 있다.
- 주석처리 대상 함수 목록이 문서에 남아 있다.
