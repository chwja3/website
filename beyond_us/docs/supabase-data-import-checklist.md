# Supabase 데이터 이관 체크리스트

## 설계

- [x] Sheet별 Supabase 대상 테이블 분류.
- [x] DEV 선검증 후 PROD 일괄 전환 순서 확정.
- [x] 원본 row 보관용 감사 테이블 migration 작성.
- [x] Sheet export 방식 확정.
- [x] import 스크립트 실행 방식 확정.
- [x] DEV 검증 쿼리 작성.
- [ ] PROD 전환 runbook 최종 잠금.

## DEV

- [x] DEV Supabase에 `001`부터 최신 migration까지 적용.
- [x] DEV GAS에서 `exportSupabaseMigrationJsonDev` 실행.
- [x] DEV export JSON dry-run 확인.
- [x] DEV Sheet 전체 row를 `legacy_sheet_rows`에 적재.
- [x] DEV 정규 테이블 변환 dry-run 확인.
- [x] DEV `Users`를 `profiles`로 이관.
- [x] DEV 설정, Events, 도메인 시트, 추첨권 이관.
- [ ] DEV Supabase Auth 계정 생성 전략 확정.
- [ ] DEV 현재 상태 테이블 재계산.
- [ ] DEV 원본 projection과 Supabase 결과 비교.
- [ ] DEV 앱을 Supabase API로 연결해 기능 검증.

## PROD

- [ ] PROD 전환 전 서버 점검 상태 전환.
- [ ] PROD Google Sheet 전체 사본 생성.
- [ ] PROD Supabase migration 적용 확인.
- [ ] PROD Sheet export와 import 실행.
- [ ] PROD row count와 핵심 집계 검증.
- [ ] 앱과 admin API endpoint 전환.
- [ ] smoke test 통과.
- [ ] maintenance 해제.
- [ ] Google Sheet와 GAS 읽기 전용 백업 보관.
