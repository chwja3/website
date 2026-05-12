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
- [~] `HOLD_PRAY_ENTRIES` 를 `HoldPray` 시트 원천 데이터로 전환 — **설계 완료 (Phase 2.0 D). 실행은 migrate_step6 + Phase 2C 코드 전환**
- [x] `AppSettings` / `MissionDefinitions` 목표 스키마 샘플 작성
- [~] `CardDefinitions` 외부화 여부 결정 — **스킵 (10개 고정 카드, 이번 행사 내 변경 없음)**

---

## Phase 2 — 새 스키마 + Event Sourcing 도입 (DEV)

> Event Sourcing + Dual Projection 구조 도입.
> Events 시트가 단일 truth source. Collection은 pure projection. UserDashboard는 시트 함수 기반 검증 뷰.
> DEV는 활성 사용자가 없으므로 dual-write 모니터링 없이 big-bang으로 전환. PROD는 Phase 3에서 dual-write 안전 모드 유지.

### 2.0 사전 설계 (문서 작업)

- [x] Events 시트 스키마 확정 (`sheet-restructure-context.md` Phase 2.0 A 섹션)
  - [x] event type 카탈로그 (mission.submitted, ticket.granted, card.drawn, trade.*, hp.guessed, bbb.* 등)
  - [x] payload JSON 구조 명세 (하이브리드: refId/amount/weekKey 별도 컬럼 + payload JSON)
- [x] `AppSettings` 스키마 샘플 (Key-Value 행) — Phase 2.0 C
- [x] `MissionDefinitions` 스키마 샘플 (1행=1항목, denormalized 채택) — Phase 2.0 C
- [x] UserDashboard 컬럼 명세 + 시트 함수 초안 (COUNTIFS / SUMIFS / VLOOKUP) — Phase 2.0 E
- [x] 전체 영문 key 시트명 + 운영진 라벨 + machine header 명세 확정 (`sheet-restructure-context.md` F섹션 "최종 스키마")

### 2A — Events 시트 + DEV Big-Bang 백필

> DEV 시트 백업 후 기존 데이터를 Events로 한 번에 백필한다. 장기간 dual-write 모니터링은 생략.

- [x] 로컬 GAS에 `Events` 시트 생성 코드 추가 (Row 1 운영진 라벨 / Row 2 machine header / Row 3+ 데이터)
- [x] `Events_append(type, userId, options)` 헬퍼 작성
- [x] 기존 mutation 시트 데이터를 Events로 백필하는 함수 구현.
  - [x] `raw_checkins` → `mission.submitted`
  - [x] `raw_checkins.ticketEarned` → `ticket.granted` (reason=week_complete)
  - [x] `CardDraws` → `ticket.consumed` + `card.drawn`
  - [x] `BonusDraws` → `ticket.granted` (legacy source 기반 reason)
  - [x] `Trades` → `trade.requested` + terminal status + `trade.prayed`
  - [x] `HPGuesses` → `hp.guessed`
  - [x] `CardReceived` → `card.received`
  - [x] BBB 메시지/사진/공지/문의는 raw content라 Events 백필 제외
- [x] `migrate_step5_absorbToEvents_dryRun()` 구현
- [x] `migrate_verify()` 로 Events 백필 결과와 기존 시트 집계 비교 구현
- [x] 사용자가 DEV GAS 편집기에 로컬 `Apps_Script` 변경분 수동 반영
- [x] DEV 시트 사본 또는 DEV 시트에서 dry-run 실행
- [x] `migrate_step5_absorbToEvents()` 실제 실행
- [x] `migrate_verify()` 결과 `ok: true` 확인
- [x] 샘플 유저별 mission/draw/ticket/trade 집계 확인
- [x] dev 브랜치 커밋

### 2B — UserDashboard 시트 추가 [read-only]

> 앱 동작 경로 변경 없음. GAS에는 시트 생성용 setup 함수만 추가.

- [x] 로컬 GAS에 `setupUserDashboard(rowLimit)` 구현
- [x] `UserDashboard` 시트 생성 + 컬럼 헤더
- [x] Users 목록을 한 행씩 자동 펼치는 함수 (`UserDashboard` 3행 → `Users` 2행)
- [x] Events에서 계산되는 컬럼 (시트 함수)
  - [x] 미션 제출 수
  - [x] 누적 티켓 획득
  - [x] 카드 뽑은 수
  - [x] 남은 뽑기권
  - [x] 카드 종류별 보유 (Events 합산)
  - [x] 교환 진행중 건수
  - [x] 마지막 활동 timestamp
- [x] Collection 저장값과 비교하는 검증 컬럼 (✓/❌)
- [x] 조건부 서식 — ❌ 행 빨갛게
- [x] 사용자가 DEV GAS 편집기에 로컬 `Apps_Script` 변경분 수동 반영
- [x] `setupUserDashboard()` 실행
- [x] 모든 행이 ✓ 떨어지는지 확인 (Phase 2A big-bang 백필이 잘 됐다면)
- [x] 최종 구조에서 흡수될 legacy 시트 숨김 함수 구현 (`hideLegacyDevSheets`)
- [x] `hideLegacyDevSheets()` 실행 후 `config`, `raw_checkins`, `CardDraws`, `BonusDraws` 숨김 확인

### 2C — 스키마 정규화 + 마이그레이션

- [~] 마이그레이션 함수 작성 (모두 idempotent).
  - [x] `migrate_step1_backup()` — Drive 스프레드시트 백업 래퍼
  - [ ] `migrate_step2_addSheetMetadata()` — 1행 운영진 라벨/설명
  - [ ] `migrate_step3_normalizeHeaders()` — 2행 machine header 영문 key 정규화
  - [x] `migrate_step4_splitConfig()` — `config` → `AppSettings` + `MissionDefinitions` 복사 함수
  - [x] `migrate_step5_absorbToEvents()` — `raw_checkins` + `CardDraws` + `BonusDraws` + 관련 mutation 시트 → Events 백필 (Phase 2A에서 로컬 구현)
  - [ ] `migrate_step6_externalizeHoldPray()` — `HOLD_PRAY_ENTRIES` 하드코딩 → `HoldPray` 시트. **보류. 나중에 한 번에 처리**
  - [x] `migrate_step7_orderAndColor()` — 시트 순서/탭 색상 적용 함수 구현
  - [ ] `migrate_runAll()` / `migrate_verify()`
- [x] `SHEET_NAMES.APP_SETTINGS`, `SHEET_NAMES.MISSION_DEFINITIONS` 추가
- [x] `SCHEMA.APP_SETTINGS`, `SCHEMA.MISSION_DEFINITIONS` 추가 (Row 1 운영진 라벨 / Row 2 machine header)
- [x] `migrate_step4_splitConfig_dryRun()` 구현
- [x] `getAppSetting_()` / `setAppSetting_()` 헬퍼 구현
- [x] `getMissionConfigFromDefinitions_()` / `getAllWeekMeta_()` 헬퍼 구현
- [ ] DEV 시트 사본에서 dry-run
- [ ] DEV 시트 본 실행 + verify
- [x] 현행 앱 read path를 기존 `config`에서 새 시트 기반으로 전환 (fallback 유지)
  - [x] `getConfig()` → `AppSettings.current_week` + `MissionDefinitions`
  - [x] `getCurrentWeek` / `setCurrentWeek` → `AppSettings.current_week`
  - [x] `getMissionConfig` / `setMissionConfig` → `MissionDefinitions`
  - [x] `getAppOpenDate()` → `AppSettings.app_open_date`
  - [x] 티켓/Collection 재계산 threshold → `MissionDefinitions`
- [ ] HoldPray 시트 기반 read 경로 동작 확인
- [ ] AppSettings / MissionDefinitions 기반 read 경로 동작 확인
- [ ] `migrate_step7_orderAndColor()` DEV 실행 후 시트 순서/탭 색상 확인

### 2D — Read Path 전환 (Collection을 Projection으로)

> Collection 직접 mutation을 전부 제거하고, Events 기반 재계산으로 대체.

- [x] 2D-0 비교용 preview 함수 구현. 기존 Collection을 쓰기 전에 Events 기반 계산값과 비교
  - [x] `previewCollectionProjection(userId)` 구현. 인자 없으면 전체 후보 유저 비교
  - [x] `ticket.granted`, `ticket.consumed`, `card.drawn`, `trade.accepted` 반영
  - [x] 기존 Collection row와 projected row의 field별 diff 출력
- [x] `previewCollectionProjection()` DEV 실행 후 mismatch 원인 확인
  - [x] 사용자 확인 기준 `mismatchCount: 0`
- [x] `rebuildCollectionRow(userId)` 함수 작성 — Events에서 그 유저 row 통째로 재계산
  - [x] `rebuildCollectionRow_` 내부 헬퍼 분리. 이후 Lock을 이미 잡은 mutation 경로에서 재사용 가능
  - [x] `adminRebuildCollectionRow` 관리자 POST 액션 추가. UI 노출 없음
- [x] `rebuildCollectionRow(userId)` DEV 단건 실행 후 `diffCountBeforeWrite: 0` 확인. 사용자 확인 기준
- [x] mutation 경로에서 Collection 직접 setValue 제거.
  - [x] `saveCheckin` — `mission.submitted` + 조건부 `ticket.granted` 기록 후 row rebuild
  - [x] `drawCard` — `ticket.consumed` + `card.drawn` 기록 후 row rebuild
  - [x] `requestTrade` — `trade.requested` 기록
  - [x] `acceptTrade` — `trade.accepted` 기록 후 양쪽 row rebuild
  - [x] `submitHoldPrayGuess` / `uploadBBBPhoto` 보너스 지급 — `ticket.granted` 기록 후 row rebuild
  - [x] `adminGrantHiddenCard` — `card.granted` 기록 후 row rebuild
  - [~] `adminGrantHiddenCard` 수동 지급 검증은 보류. 구현은 완료, GAS 편집기에서 인자 없이 직접 실행하지 않음
  - [x] 기존 `updateCollectionSheet` / `updateTicketCols` 정의는 비상/호환용으로 보존
- [x] DEV 교환 테스트용 `adminGrantTestCard` 추가
  - [x] `ENABLE_TEST_ADMIN_TOOLS=true` Script Property가 있을 때만 동작
  - [x] `card.granted` 이벤트 기록 후 해당 유저 `Collection` row rebuild
- [x] admin `Events 관리` 패널 추가
  - [x] 카드 추가 이벤트 생성 (`card.granted`)
  - [x] 카드 삭제 이벤트 생성 (`card.removed`)
  - [x] Events 기준 Collection + UserDashboard 재계산
  - [x] admin 변경분 버전 bump (`version.txt` + `sw.js` + `app.js`)
- [x] 기존 `rebuildCollectionSheet` (전체) 는 검증/긴급 정비용으로 보존
- [x] `setupUserDashboard()` 재실행. `card.granted`를 반영하는 공식으로 갱신. 사용자 확인 기준
- [x] UserDashboard의 검증 컬럼이 ✓ 유지되는지 확인. 사용자 확인 기준
- [x] DEV 전체 동작 테스트. 사용자 확인 기준 전체 통과
  - [x] 로그인 / 회원가입 / 비밀번호 재설정
  - [x] 미션 제출 / 새로고침
  - [x] 카드 뽑기 / 컬렉션 조회 / 교환
  - [x] H&P 카드 표시 / 정답 제출
  - [x] BBB 매칭 / 메시지 / 사진
    - [x] M1 케어버디 사진 업로드 시 `BBBPhotos` 저장 확인
    - [x] M1 최초 업로드 시 `BonusDraws.bbb_photo` + `Events.ticket.granted` 생성 확인
    - [x] M1 재업로드 시 중복 뽑기권 지급 없음 확인
    - [x] BBB 매칭 표시와 메시지 송수신 확인
  - [x] 공지사항 / 개발자 문의
  - [x] 개발자 문의와 H&P 힌트 admin 분리 표시 확인
- [x] admin `Events 관리` 패널 end-to-end 확인.
  - [x] 카드 추가 이벤트 생성 후 `Events.card.granted` + 앱 컬렉션 증가 확인
  - [x] 카드 삭제 이벤트 생성 후 `Events.card.removed` + 앱 컬렉션 감소 확인
  - [x] Events 기준 재계산 후 `Collection` + `UserDashboard` 정합성 확인

### 2E — 속도 최적화

- [ ] Sheets API v4 (Advanced Service) 활성화
- [ ] `batchGet` / `batchUpdate` 도입 — 함수당 RPC 횟수 감소
- [ ] 캐시 키 정밀화 — 유저 단위로 무효화 (`clearHotCaches_` 광범위 invalidate 제거)
- [ ] 함수당 `getSpreadsheet()` 호출 1회로 통합
- [ ] 카드 뽑기 응답 시간 측정 — 2D 직후 vs 2E 후 비교
- [ ] DEV 스트레스 테스트 (연속 뽑기 등)

---

## Phase 3 — PROD 적용 (단계별 배포)

> Phase 2의 A→B→C→D→E 순으로 PROD에도 단계별 적용. 한 번에 다 안 옮김.

### 3.0 사전 공지

- [ ] 운영진에 단계별 마이그레이션 일정 안내
- [ ] 단계별 PROD 백업 정책 합의

### 3A — PROD Events 시트 + Dual-Write 배포

- [ ] PROD 시트에 `Events` 시트 생성
- [ ] PROD GAS에 dual-write 코드 배포 (기존 배포 편집 → URL 유지)
- [ ] 며칠 모니터링 — Events 채워지는지, 기존 시트와 불일치 없는지

### 3B — PROD UserDashboard 추가

- [ ] PROD 시트에 `UserDashboard` 추가 + 시트 함수
- [ ] 검증 컬럼 ✓ 떨어지는지 운영진과 함께 확인
- [ ] 불일치 발견 시 원인 추적

### 3C — PROD 스키마 마이그레이션

- [ ] PROD 시트 전체 백업 (백업 시트 + Drive 사본 1부)
- [ ] PROD GAS에서 `migrate_runAll()` 실행
- [ ] `migrate_verify()` 검증
- [ ] HoldPray / AppSettings / MissionDefinitions 동작 확인

### 3D — PROD Collection Projection 전환

- [ ] PROD GAS에 Phase 2D 코드 배포
- [ ] 카드 뽑기 / 미션 제출 스모크 테스트
- [ ] UserDashboard 검증 컬럼 ✓ 확인
- [ ] 1시간 활성 사용자 모니터링

### 3E — PROD 속도 최적화

- [ ] PROD GAS에 Phase 2E 코드 배포
- [ ] 응답 시간 개선 측정
- [ ] 사용자 체감 보고 수집

### 3.9 마무리

- [ ] `app.js` + `admin.html` 의 DEV/PROD `API_BASE` 갱신 (URL 바뀐 경우만)
- [ ] 버전 bump (`YYYYMMDD?`) + `version.txt` + `sw.js` + `app.js` `APP_VERSION` 동기화
- [ ] `git push origin dev` → main 머지
- [ ] 운영진에 완료 보고 + 변경 내역 가이드 전달
- [ ] 백업 시트 1주일 보관 후 제거

---

## 작업 후 정리

- [ ] `CLAUDE.md` 의 시트 구성표 갱신
- [ ] 본 체크리스트 + `sheet-restructure-context.md` 보관
- [ ] 다음 행사 재사용 시 참조용으로 정리
