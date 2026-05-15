# Performance Follow-up Plan

## 목표

H&P, B.B.B 미션, 천로역정 첫 진입 지연과 관리자 대시보드 강제 재계산 지연을 줄이고, GAS에 남은 미사용 수동 함수를 보수적으로 정리한다.

## 범위

1. H&P와 B.B.B 조회에 짧은 서버 캐시를 추가한다.
2. 관리자 대시보드의 일반 새로고침은 `DashboardStats` 캐시 경로를 사용하게 한다.
3. Events 기준 재계산 버튼은 projection 재생성 후 대시보드 캐시를 한 번 갱신하게 한다.
4. admin/app 호출이 없고 내부 대체 경로가 있는 GAS public wrapper만 주석 처리한다.

## 검증 기준

- H&P와 B.B.B 조회 함수가 캐시 wrapper를 거친다.
- H&P 정답 제출, 힌트 요청/답변, BBB 사진 업로드/삭제/승인/거절, BBB 매칭 변경 후 관련 캐시가 무효화된다.
- 관리자 대시보드 새로고침 버튼이 `force=1`을 보내지 않는다.
- Events 기준 재계산 후 대시보드가 캐시된 결과로 다시 표시된다.
- `node --check`와 `git diff --check`를 통과한다.
