# 2026-06-20 최신 조 엑셀 기준 BBB roster 보정 컨텍스트

- 사용자가 최신 파일 `C:\Users\jkjk9\Downloads\조별 데이터 정리 6_14 (1).xlsx` 기준으로 조를 업데이트해달라고 요청했다.
- 기존 `20260618000200_group_roster_import.sql`은 구버전 `조별 데이터 정리 6_14.xlsx` 기준이다.
- 최신 파일에는 `추가인원` 행과 대응되는 `조에서 제외` 행이 함께 남아 있는 사람이 있다.
- 실제 roster에는 `조에서 제외` 행을 넣으면 안 된다.
- `2차설문 추가 필요 명단`은 실제 조가 아니므로 roster에서 제외한다.
- 기존 BBB 매칭은 `retreat_group_roster.id`를 기준으로 저장되어 있으므로 전체 delete/reinsert 방식은 피한다.
- 이번 보정은 기존 row를 이름과 생년 기준으로 이동/갱신해 row id를 최대한 유지한다.
- 최신 엑셀에서 `조에서 제외`와 보조 명단을 제외한 실제 roster는 243명이다.
- 최신 엑셀의 실제 roster 안에서는 이름+생년 기준 중복이 0명이다.
- 보정 SQL은 `20260620000700_bbb_roster_latest_xlsx_patch.sql`이다.
- 보정 SQL은 기존 row를 이름+생년으로 찾아 재사용하고, 제거되는 row가 기존 care/secret link에 들어가 있으면 같은 이름+생년의 최신 row로 연결을 옮긴다.
- 제거되는 row는 `retreat_group_roster_removed`에 JSON snapshot으로 백업한다.
- `source_batch, roster_order` unique 충돌을 피하려고 기존 roster order를 임시 음수 영역으로 옮긴 뒤 최신 순서를 다시 부여한다.
- 2026-06-20 hotfix: update/insert 뒤에 최종 cleanup을 추가했다. 최신 명단의 `roster_order`, `group_no`, `name_norm`, `birth_year`와 정확히 일치하지 않는 잔여 row는 `retreat_group_roster_removed`에 백업 후 삭제한다. 김규리 12조, 권혁준 과거 조처럼 옛 row가 남는 문제를 막기 위한 방어다.
