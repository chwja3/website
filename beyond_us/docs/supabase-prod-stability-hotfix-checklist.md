# Supabase PROD 안정화 핫픽스 체크리스트

- [x] H&P RPC 오류 가능 지점을 확인했다.
- [x] H&P 카드 선택 기준을 공통 helper로 통일했다.
- [x] H&P ticketCardIdx 변환을 안전한 숫자 변환으로 바꿨다.
- [x] H&P 초성 함수를 `chr()` 기반으로 바꿔 인코딩 영향을 줄였다.
- [x] summary와 raffle 관련 트리거를 deferred constraint trigger로 통일했다.
- [x] migration 적용 시 활성 유저 요약을 다시 계산하도록 했다.
- [x] 미션 제출 RPC의 `user_summary +1` 수동 증가를 제거했다.
- [x] 카드 뽑기 RPC의 `user_summary +1` 수동 증가를 제거했다.
- [x] H&P 카드 helper의 컬럼 alias를 명시해 런타임 ambiguity 가능성을 줄였다.
- [x] 관리자 유저별 H&P 현황 RPC도 앱 H&P helper를 재사용하도록 바꿨다.
- [ ] PROD Supabase SQL Editor에서 migration을 실행한다.
- [ ] 앱 H&P 탭을 실제 계정으로 확인한다.
- [ ] 관리자 유저별 H&P 현황 탭을 확인한다.
- [ ] 관리자 시스템 상태 audit을 다시 확인한다.
