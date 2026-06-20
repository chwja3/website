# 2026-06-20 최신 조 엑셀 기준 BBB roster 보정 계획

## 목표

`조별 데이터 정리 6_14 (1).xlsx`를 기준으로 `retreat_group_roster`를 보정한다.
기존 BBB 케어버디와 시크릿버디 수동 매칭은 가능한 한 유지한다.

## 기준

- 실제 조 roster는 최신 엑셀의 `1~8조`, `9~16조` 시트만 사용한다.
- `특이사항`에 `조에서 제외` 또는 `조에서제외`가 있는 행은 roster에서 제외한다.
- `2차설문 추가 필요 명단`은 실제 조 배정 roster에 넣지 않는다.
- 기존 row id는 이름과 생년 기준으로 최대한 재사용한다.
- 새 엑셀에만 있는 사람은 새 row로 추가한다.
- 새 엑셀에서 빠진 기존 row는 삭제하지 않고 `retreat_group_roster_removed` 백업 테이블로 옮긴 뒤 roster에서 삭제한다.

## 검증

- 최신 엑셀 유효 row 수와 SQL 적용 후 roster row 수가 일치해야 한다.
- `조에서 제외` row가 남아 있지 않아야 한다.
- 보조 명단 row가 `group_no is null` 상태로 남아 있지 않아야 한다.
- 기존 care/secret roster link 중 살아남은 row끼리의 연결은 유지해야 한다.
