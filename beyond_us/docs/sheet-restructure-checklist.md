<!-- 구글 시트 구조 개편 작업 체크리스트 -->

# 시트 구조 개편 — Checklist

> 진행 상황 추적용. 완료한 항목은 `[x]` 로 체크. 작업 도중 새 항목 추가 가능.

---

## Phase 0 — 현재 스키마 파악

- [x] `Apps_Script` 전체 읽고 각 시트별 컬럼 인덱스 사용처 매핑
- [x] 시트별 현재 컬럼 헤더 정확히 파악 (GAS 코드의 `setValue` / `getValues` 호출에서 추론)
- [x] 영향받는 GAS 함수 목록화 (도메인별 분류)
- [x] `sheet-restructure-context.md` 의 "현재 스키마" 섹션에 표 저장
- [x] PROD/DEV 실제 Google Sheet 헤더와 로컬 `Apps_Script` 분석 결과 대조

---

## Phase 1 — GAS 코드 리팩토링 (이름 변경 사전 작업)

- [x] `SHEET_NAMES` 상수 객체 추가 (영문 key 탭명 유지)
- [x] `COLUMNS` / `SCHEMA` 상수 추가 (운영진 라벨과 machine header 분리)
- [x] `getColumns(sheet)` 헬퍼 함수 작성 (헤더명 → 인덱스 매핑)
- [x] `getSheetRows(schema)` 류 헬퍼 작성 (headerRow/dataStartRow 명시)
- [x] 모든 시트 접근을 `SHEET_NAMES.X` 로 통일
- [ ] 모든 컬럼 인덱스 (`r[2]`, `r[3]` 등) 를 `r[col.nickname]` 형태로 점진 전환
- [ ] `Users`, `config`, `raw_checkins`, `Collection`, `Trades` 우선 전환
  - [x] `Users` 인증/세션/이름 매핑 흐름 1차 전환
  - [ ] `config` 전환
  - [ ] `raw_checkins` 전환
  - [ ] `Collection` 전환
  - [ ] `Trades` 전환
- [x] DEV 스프레드시트 (`19-2XZ3...`) 존재 여부 확인 및 동작 테스트
- [x] `admin.html` dev/local 접속 시 바뀐 DEV GAS를 참조하도록 `API_BASE` 분기 반영 확인
- [ ] 동작 확인 후 dev 브랜치 커밋

---

## Phase 1.5 — 하드코딩 제거 준비

- [x] `SPREADSHEET_ID`, `ADMIN_PASSWORD` 를 Script Properties로 이동
  - [x] GAS 코드에서 민감값 상수 제거
  - [x] Script Properties 접근 헬퍼 추가
  - [x] 관리자 인증 비교를 헬퍼 기반으로 전환
  - [x] DEV Apps Script 프로젝트에 Properties 설정
  - [x] DEV 배포 URL 새 버전 반영 및 smoke 테스트
- [x] `DEV_SPREADSHEET_ID`, `_devMode`, `devMode=true` 요청 파라미터 제거
- [ ] 수동 GAS 반영 후 DEV Properties를 `SPREADSHEET_ID=DEV 시트 ID`, `ADMIN_PASSWORD=관리자 비밀번호`, `ALLOW_TEST_DRAWS=true`로 확인
- [ ] 수동 PROD 반영 시 PROD Properties를 `SPREADSHEET_ID=PROD 시트 ID`, `ADMIN_PASSWORD=관리자 비밀번호`로 확인
- [~] `Users` 비밀번호 평문 저장을 `passwordHash` / `passwordSalt` 구조로 전환하는 마이그레이션 설계 — **스킵 (이벤트용 비밀번호, 실익 없음)**
- [ ] `HOLD_PRAY_ENTRIES` 를 `HoldPray` 시트 원천 데이터로 전환
- [ ] `AppSettings` / `MissionDefinitions` 목표 스키마 샘플 작성
- [~] `CardDefinitions` 외부화 여부 결정 — **스킵 (10개 고정 카드, 이번 행사 내 변경 없음)**

---

## Phase 2 — 새 스키마 정의 + 마이그레이션 스크립트

- [ ] 영문 key 시트명 / 운영진 라벨 / machine header 명세 확정 (`sheet-restructure-context.md` 의 "최종 스키마" 섹션)
- [ ] 마이그레이션 함수 작성.
  - [ ] `migrateAddSheetMetadata()` — Row 1 운영진 라벨/설명 추가
  - [ ] `migrateNormalizeHeaders()` — machine header를 안정적인 영문 key로 정규화
  - [ ] `migrateMergeCardDrawsBonusDraws()` — 두 시트 통합 (`CardLedger` 생성 여부 결정 후)
  - [ ] `migrateSplitConfig()` — `config` → `AppSettings` + `MissionDefinitions`
  - [ ] `migrateSheetOrderAndColor()` — 시트 순서/색상 일괄 적용
- [ ] DEV 시트에서 마이그레이션 dry-run 실행
- [ ] DEV 시트에서 마이그레이션 본 실행 + 결과 검증
- [ ] GAS 코드의 `SHEET_NAMES` / 컬럼 헤더 새 값으로 갱신
- [ ] DEV 환경에서 전체 동작 테스트.
  - [ ] 로그인 / 회원가입 / 비밀번호 재설정
  - [ ] 미션 제출 / 새로고침
  - [ ] 카드 뽑기 / 컬렉션 조회 / 교환
  - [ ] H&P 카드 표시 / 정답 제출
  - [ ] BBB 매칭 / 메시지 / 사진
  - [ ] 공지사항 / 개발자 문의

---

## Phase 3 — PROD 적용

- [ ] 운영진에 사전 공지 (마이그레이션 시간대)
- [ ] PROD 스프레드시트 백업.
  - [ ] 모든 시트 복제 → `백업_YYYYMMDD_원본명`
- [ ] PROD 마이그레이션 함수 실행
- [ ] GAS 새 버전 배포 (기존 배포 편집 → URL 유지 시도)
- [ ] `app.js` + `admin.html` 의 DEV/PROD `API_BASE` 갱신 (URL 바뀐 경우만)
- [ ] `admin.html` dev/local 접속은 DEV GAS, PROD 접속은 PROD GAS를 참조하는지 확인
- [ ] 버전 bump (`YYYYMMDD?`) + `version.txt` + `sw.js` + `app.js` `APP_VERSION` 동기화
- [ ] `git push origin dev`
- [ ] 스모크 테스트 (실 사용자 계정으로 로그인 → 메인 → 미션 제출 → 카드 뽑기)
- [ ] 운영진에 완료 보고 + 변경 내역 가이드 전달
- [ ] 백업 시트 1주일 보관 후 제거

---

## 작업 후 정리

- [ ] `CLAUDE.md` 의 시트 구성표 갱신
- [ ] 본 체크리스트 + `sheet-restructure-context.md` 보관
- [ ] 다음 행사 재사용 시 참조용으로 정리
