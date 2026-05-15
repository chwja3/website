# 카드팩 Collection 반영 속도 개선 체크리스트

- [x] 카드팩 종료 후 중복 `userStatus` 새로고침 흐름 확인.
- [x] `switchSection('collection')` 호출 시 필요 없는 즉시 새로고침을 건너뛰게 수정.
- [x] 카드 뒷면 클릭 가능 전환 딜레이를 0.01초 수준으로 조정.
- [x] Collection 이미지에 lazy loading과 async decoding 힌트 추가.
- [x] 미사용 이미지 목록 산출.
- [x] 미사용 이미지를 `beyond_us/images/unused`로 이동.
- [x] WebP 변환 도구 사용 가능 여부 확인.
- [x] 프론트 버전 동기화.
- [x] 문법 검증과 diff 검토.
