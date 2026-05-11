<!-- 구글 시트 구조 개편 작업 체크리스트 -->

# 시트 구조 개편 — Checklist

> 진행 상황 추적용. 완료한 항목은 `[x]` 로 체크. 작업 도중 새 항목 추가 가능.

---

## Phase 0 — 현재 스키마 파악

- [ ] `Apps_Script` 전체 읽고 각 시트별 컬럼 인덱스 사용처 매핑
- [ ] 시트별 현재 컬럼 헤더 정확히 파악 (GAS 코드의 `setValue` / `getValues` 호출에서 추론)
- [ ] 영향받는 GAS 함수 목록화 (도메인별 분류)
- [ ] `context-notes` 의 "현재 스키마" 섹션에 표 저장

---

## Phase 1 — GAS 코드 리팩토링 (이름 변경 사전 작업)

- [ ] `SHEET_NAMES` 상수 객체 추가 (현재 영문 이름 → 변수화)
- [ ] `getColumns(sheet)` 헬퍼 함수 작성 (헤더명 → 인덱스 매핑)
- [ ] 모든 시트 접근을 `SHEET_NAMES.X` 로 통일
- [ ] 모든 컬럼 인덱스 (`r[2]`, `r[3]` 등) 를 `r[col.닉네임]` 형태로 점진 전환
- [ ] DEV 스프레드시트 (`19-2XZ3...`) 존재 여부 확인 및 동작 테스트
- [ ] 동작 확인 후 dev 브랜치 커밋

---

## Phase 2 — 새 스키마 정의 + 마이그레이션 스크립트

- [ ] 새 시트 이름 / 컬럼 헤더 명세 확정 (`context-notes` 의 "최종 스키마" 섹션)
- [ ] 마이그레이션 함수 작성.
  - [ ] `migrateRenameSheets()` — 시트 이름 일괄 변경
  - [ ] `migrateRenameColumns()` — 컬럼 헤더 일괄 변경
  - [ ] `migrateMergeCardDrawsBonusDraws()` — 두 시트 통합 (`카드_뽑기이력` 생성)
  - [ ] `migrateSplitConfig()` — `config` → `앱_설정` + `미션_정의`
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
- [ ] `app.js` + `admin.html` 의 `API_BASE` 갱신 (URL 바뀐 경우만)
- [ ] 버전 bump (`YYYYMMDD?`) + `version.txt` + `sw.js` + `app.js` `APP_VERSION` 동기화
- [ ] `git push origin dev`
- [ ] 스모크 테스트 (실 사용자 계정으로 로그인 → 메인 → 미션 제출 → 카드 뽑기)
- [ ] 운영진에 완료 보고 + 변경 내역 가이드 전달
- [ ] 백업 시트 1주일 보관 후 제거

---

## 작업 후 정리

- [ ] `CLAUDE.md` 의 시트 구성표 갱신
- [ ] 본 체크리스트 + `context-notes.md` 보관
- [ ] 다음 행사 재사용 시 참조용으로 정리
