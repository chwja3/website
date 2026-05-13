# 특별 카드팩 체크리스트

- [x] 특별 카드팩 정책 결정사항 문서화.
- [x] admin 탭 활성화에 특별 카드팩 토글 추가.
- [x] 앱 카드팩 영역은 사용자 기준 단일 카드팩 버튼으로 통일.
- [x] 카드팩 배지는 `🎫 전체 카드팩 수`, `💜 특별 카드팩 수`로 표시.
- [x] 특별 카드팩 토글이 꺼져 있으면 기존 화면 유지.
- [x] 일반 카드팩이 없을 때만 단일 카드팩 버튼이 내부적으로 `drawSpecialCard` 액션을 호출하도록 연결.
- [x] `APP_VERSION`과 `version.txt` 동기화.
- [x] 로컬 정적 검증과 diff 검산.
- [x] GAS `TabSettings.specialPack` 응답과 저장 처리 추가.
- [x] GAS `userStatus.pendingSpecialPacks` 응답 추가.
- [x] GAS `drawSpecialCard` 액션 추가.
- [x] UserDashboard에 특별팩 획득·사용·잔여 수 컬럼 추가.
- [x] BBB MISSION 1, 2, 3 성공 시 각각 `special_pack.granted` 자동 지급 연결.
- [x] BBB 사용자 앱 문구에서는 “특별 카드팩” 표현을 제거하고 “카드팩”으로 통일.
