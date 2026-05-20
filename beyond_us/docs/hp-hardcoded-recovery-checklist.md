# H&P 하드코딩 기도제목 복구 체크리스트

- [x] 예전 GAS `HOLD_PRAY_ENTRIES` 배열 위치 확인.
- [x] 배열 파싱 및 건수 확인.
- [x] 기도본문 중복 여부 확인.
- [x] Supabase 수동 복구 SQL 생성.
- [x] SQL 정적 검증.
- [x] 변경사항 커밋.
- [x] 변경사항 푸시.
- [ ] PROD Supabase SQL Editor에서 수동 실행.
- [ ] 실행 결과의 `unmatchedNamedRows`, `ambiguousNameRows`, `insertedRows` 확인.
- [ ] Admin H&P 기도제목 매칭 탭에서 미매칭 항목 후속 확인.
