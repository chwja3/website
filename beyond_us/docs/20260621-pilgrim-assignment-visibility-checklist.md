# 2026-06-21 천로역정 랜덤 2스팟 표시 보강 체크리스트

- [x] 붉은 원 표시 누락 원인 확인.
- [x] `bu_ensure_pilgrim_assignment()`를 최신 SQL에 다시 포함.
- [x] `bu_photo_payload()`에서 배정을 보장하도록 수정.
- [x] 활성 유저 기존 누락 배정을 backfill.
- [x] 천로역정 탭과 `m3` 섹션 open 상태를 함께 보장.
- [x] SQL 문법과 정적 검증 실행.
- [x] 변경 범위만 커밋 및 푸시.
