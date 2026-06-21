# BBB 들킴 배지 오류 수정 체크리스트

- [x] 현재 `caughtByBuddy` 계산식이 잘못된 방향으로 잡힌 것을 확인한다.
- [x] `get_bbb_status` RPC를 내가 돌보는 대상 기준으로 수정한다.
- [x] TF 추가 케어버디도 들킴 판정 대상에 포함한다.
- [x] 문법과 diff 검사를 실행한다.
- [ ] PROD Supabase SQL Editor에서 새 마이그레이션을 실행한다.
- [ ] 문제가 나온 사용자로 BBB 탭을 새로 열어 배지가 사라지는지 확인한다.
