# 사용자 요약 audit mismatch 수정 체크리스트

- [x] summary 과집계 원인을 문서화한다.
- [x] 이벤트 기반 summary refresh trigger를 transaction 마지막에 실행되게 보정한다.
- [x] SQL 적용 시 현재 active 유저 summary를 재계산한다.
- [x] SQL shape 검사를 실행한다.
- [ ] main에 커밋/푸시한다.
- [ ] PROD SQL migration 적용 후 시스템 상태를 다시 확인한다.
