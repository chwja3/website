<!-- 구글 시트 구조 개편 — 전체 작업 계획 (Phase 0~3) -->

# 시트 구조 개편 — Full Plan

> Phase 0(현황 파악) → Phase 1(GAS 리팩토링) → Phase 2(스키마 정의 + 마이그레이션) → Phase 3(PROD 적용) 전체 로드맵.
> 진행 상황은 `sheet-restructure-checklist.md`, 결정 배경은 `sheet-restructure-context.md` 참조.

---

## 전제 — 환경 분리 (완료)

- DEV GAS 별도 배포 완료 — DEV 시트(`19-2XZ3...`)에 고정 연결
- PROD GAS는 기존 그대로 — PROD 시트(`1tlCoz...`)에 연결
- `app.js`의 `API_BASE`는 hostname 기반 자동 분기 (localhost/dev.* → DEV GAS, 그 외 → PROD GAS)
- `admin.html`도 hostname 기반으로 `API_BASE`를 분기해야 함. dev/local 관리자 페이지는 바뀐 DEV GAS를 참조하고, PROD 관리자 페이지는 PROD GAS를 참조해야 함.
- **이후 모든 GAS 코드 변경은 DEV GAS에서 먼저 검증 → PROD GAS에 반영**

---

## 전제 — 시트명 정책 (Phase 0에서 확정)

- 시트 탭 이름은 코드가 참조하기 쉬운 안정적인 영문 key로 유지.
- 운영진이 읽을 한글 라벨과 설명은 각 시트의 1행에 둠.
- 코드가 읽는 machine header는 2행에 두고, 실제 데이터는 3행부터 시작.
- 기존 시트는 가능한 한 즉시 rename하지 않고, 필요할 때만 DEV 마이그레이션에서 새 영문 key 시트로 분리.
- Phase 1 코드는 `headerRow`, `dataStartRow`, `columns`를 명시하는 `SCHEMA` 객체 기준으로 작성.

---

## Phase 0 — 현재 스키마 파악

**목표.** PROD에 손대기 전, 현재 코드가 시트의 어떤 컬럼을 어떻게 쓰는지 완전히 매핑.

### 0.1 GAS 코드 전수조사

- `Apps_Script` 전체 읽고 다음을 추출.
  - 시트 이름 사용처 (`getSheetByName('xxx')` 모두)
  - 컬럼 인덱스 사용처 (`r[N]`, `getRange(_, N)`, `setValue` 위치 등)
  - 헤더 행을 어떻게 처리하는지 (`getRange(1, 1, 1, N).getValues()` 등)

### 0.2 시트별 컬럼 명세 작성

각 시트에 대해 다음 표를 `sheet-restructure-context.md` "현재 스키마" 섹션에 채워넣음.

```
[시트명]
| col | 헤더 | GAS 코드에서의 인덱스 | 사용처 |
|-----|------|----------------------|--------|
| A   | ID   | r[0]                 | ...    |
| B   | ...  | r[1]                 | ...    |
```

### 0.3 영향받는 함수 목록화

도메인별 분류.

- 인증 (`login`, `register`, `resetPassword`, `findNickname`)
- 미션 (`submit`, `userStatus`, `dashboard`)
- 카드 (`drawCard`, `getCollection`, `getPublicCollection`)
- 교환 (`requestTrade`, `acceptTrade`, ...)
- H&P (`getHoldPray`, `submitHoldPrayGuess`)
- BBB (`getBBB`, `sendBBBMessage`, `uploadBBBPhoto`, ...)
- 공지/문의 (`getNotices`, `postNotice`, `getInquiries`, ...)
- 어드민 (`adminLogin`, `adminGet*`, `adminSet*`)

### 0.4 산출물

- `sheet-restructure-context.md` 의 "현재 스키마" 섹션 채워짐
- 향후 리팩토링·마이그레이션 작성의 정확한 기준점 확보

---

## Phase 1 — GAS 코드 리팩토링 (안전 그물 만들기)

**목표.** 시트 이름, 헤더 행, 데이터 시작 행, 컬럼 인덱스를 **상수/헬퍼로 추상화**해서, Phase 2의 헤더·행 위치·시트 분리 변경이 코드를 깨뜨리지 않게 만듦.

> 이 단계까지는 **시트 자체는 손대지 않음**. 코드만 정리.

### 1.1 SHEET_NAMES 상수 도입

GAS 최상단에.

```js
const SHEET_NAMES = {
  USERS:        'Users',
  CONFIG:       'config',
  RAW:          'raw_checkins',
  CARD_DRAWS:   'CardDraws',
  BONUS_DRAWS:  'BonusDraws',
  COLLECTION:   'Collection',
  CARD_RECEIVED:'CardReceived',
  TRADES:       'Trades',
  HOLD_PRAY:    'HoldPray',
  HP_GUESSES:   'HPGuesses',
  TAB_SETTINGS: 'TabSettings',
  BBB_SETTINGS: 'BBBSettings',
  BBB:          'BBB',
  BBB_MESSAGES: 'BBBMessages',
  BBB_PHOTOS:   'BBBPhotos',
  NOTICES:      'Notices',
  INQUIRIES:    'Inquiries',
};
```

모든 `getSheetByName('xxx')` → `getSheetByName(SHEET_NAMES.XXX)` 로 치환.

### 1.2 SCHEMA와 getColumns 헬퍼

```js
const SCHEMA = {
  USERS: {
    sheetName: SHEET_NAMES.USERS,
    headerRow: 1,
    dataStartRow: 2,
    columns: {
      nickname: 'nickname',
      password: 'password',
      name: 'name',
      parish: 'parish',
    },
  },
};

function getColumns(sheet, headerRow) {
  const headers = sheet.getRange(headerRow, 1, 1, sheet.getLastColumn()).getValues()[0];
  const map = {};
  headers.forEach((h, i) => { map[String(h).trim()] = i; });
  return map;
}
```

사용 예.
```js
const sheet = getSpreadsheet().getSheetByName(SHEET_NAMES.USERS);
const schema = SCHEMA.USERS;
const col = getColumns(sheet, schema.headerRow);
const nickname = row[col[schema.columns.nickname]];  // 인덱스가 바뀌어도 안 깨짐
```

### 1.3 점진적 인덱스 치환

핫스팟부터.
- `Users` 접근하는 함수 전부
- `raw_checkins` 접근하는 함수 전부
- 그 외 시트는 Phase 2 직전까지 점진 전환

`r[2]`, `r[3]` 같은 매직 넘버를 전부 `r[col[schema.columns.nickname]]` 형태로.

### 1.4 DEV 테스트

- DEV GAS에 1.1~1.3 반영
- DEV 환경(localhost)에서 전체 동작 확인.
  - 로그인 / 회원가입 / 비밀번호 찾기
  - 미션 제출 / 새로고침
  - 카드 뽑기 / 컬렉션 / 교환
  - H&P / BBB / 공지 / 문의
  - `admin.html` dev/local 접속 시 DEV GAS로 요청되는지 확인
- 동작 확인 후 dev 브랜치 커밋

### 1.5 PROD 반영

- DEV 검증 통과한 GAS 코드를 PROD GAS에 그대로 복사 → 새 버전 배포
- 동작 확인 (스모크 테스트)
- 시트는 안 바뀌었으므로 안전

### 1.6 산출물

- GAS 코드의 모든 시트/컬럼 접근이 상수·헬퍼 기반으로 추상화됨
- Phase 2에서 헤더 행과 데이터 시작 행이 바뀌어도 코드는 안 깨지는 상태

---

## Phase 1.5 — 하드코딩 제거 준비

**목표.** 시트 스키마 정리와 별개로 남아 있는 민감값·행사 데이터 하드코딩을 제거할 준비를 함.

### 1.5.1 Script Properties 분리

- `SPREADSHEET_ID`, `ADMIN_PASSWORD`는 Apps Script Properties로 이동.
- DEV와 PROD는 모두 같은 `SPREADSHEET_ID` key를 쓰되, 각 GAS 프로젝트의 Property 값만 다르게 설정.
- DEV에서 뽑기권 제한 없는 테스트가 필요하면 선택 Property `ALLOW_TEST_DRAWS=true`를 DEV GAS에만 설정.
- GAS 코드에는 `PropertiesService.getScriptProperties().getProperty('KEY')` 형태의 접근 함수만 남김.
- 코드 안에는 민감값 fallback을 남기지 않고, Properties 누락 시 명시적인 설정 오류를 반환.
- `devMode` 요청 파라미터와 `DEV_SPREADSHEET_ID`는 제거하고, DEV/PROD 구분은 배포 URL과 Script Properties가 담당.
- DEV 수동 반영 시 Properties를 먼저 확인한 뒤 DEV 배포 URL만 새 버전으로 갱신.
- PROD Apps Script 프로젝트의 Properties 설정과 배포는 모든 Phase 완료 후 Phase 3에서 수동 진행.

### 1.5.2 비밀번호 저장 구조 개선

- `Users.password` 평문 저장은 `passwordHash`, `passwordSalt`, `passwordUpdatedAt` 구조로 전환.
- 기존 사용자는 첫 로그인 또는 별도 마이그레이션에서 hash 값으로 승격.
- Phase 1.5에서는 설계와 migration 함수 초안만 만들고, 실제 적용은 DEV 검증 후 진행.

### 1.5.3 행사 데이터 외부화

- `HOLD_PRAY_ENTRIES` 하드코딩 배열은 `HoldPray` 시트를 원천 데이터로 삼도록 전환.
- 미션 정의는 `config` 블록에서 `MissionDefinitions` 후보 시트로 분리.
- 앱 오픈일, 현재 주차, 탭 상태 같은 단일 설정은 `AppSettings` 후보 시트로 분리.
- 카드 정의는 `CardDefinitions`로 외부화할지 결정. 카드 종류가 고정이면 이번 Phase에서는 보류 가능.

---

## Phase 2 — 새 스키마 정의 + 마이그레이션 스크립트

**목표.** 영문 key 시트명, 1행 운영진 라벨, 2행 machine header 구조를 DEV에서 완전히 검증.

### 2.1 새 스키마 확정

`sheet-restructure-context.md` 의 "최종 스키마" 섹션을 시트별 컬럼 헤더까지 완전히 채움.

특히 미해결 항목 결정.
- `MissionDefinitions` row 구조 — 1행=1주차 (가로 펼침) vs 1행=1항목 (세로 누적)
- `AppSettings` 표현 방식 — Key-Value 행 N개 (`bbb_message_open | TRUE`) 채택
- `CardLedger` 생성 여부 — `CardDraws`와 `BonusDraws`를 통합할지 결정.

### 2.2 마이그레이션 함수 작성

GAS에 마이그레이션 전용 함수 추가. 각 함수는 idempotent(여러 번 실행해도 같은 결과).

```js
function migrate_step1_backup()           { /* 모든 시트 복제 → 백업_YYYYMMDD_원본 */ }
function migrate_step2_addSheetMetadata() { /* 1행 운영진 라벨/설명 추가 */ }
function migrate_step3_normalizeHeaders() { /* 2행 machine header 정규화 */ }
function migrate_step4_mergeCardDraws()   { /* CardDraws + BonusDraws → CardLedger 후보 */ }
function migrate_step5_splitConfig()      { /* config → AppSettings + MissionDefinitions */ }
function migrate_step6_orderAndColor()    { /* 시트 순서/탭 색상 적용 */ }

function migrate_runAll()                  { /* 위 함수 순서대로 실행 */ }
function migrate_verify()                  { /* 마이그레이션 후 검증 (행 수 일치, 데이터 유실 X) */ }
```

### 2.3 DEV 시트에서 dry-run

- DEV 시트의 사본 만들어서 거기서 먼저 실행 (안전 차원)
- `migrate_runAll()` 실행 → 결과 시각 확인
- `migrate_verify()` 로 검증

### 2.4 DEV 시트에서 본 실행

- `migrate_step1_backup()` 실행 → 백업 시트 생성됨
- `migrate_runAll()` 실행
- 결과 검증

### 2.5 GAS 코드 갱신

- `SHEET_NAMES` 상수는 안정적인 영문 key 값을 유지.
  ```js
  USERS: 'Users',
  APP_SETTINGS: 'AppSettings',
  MISSION_DEFINITIONS: 'MissionDefinitions',
  MISSION_SUBMISSIONS: 'MissionSubmissions',
  CARD_LEDGER: 'CardLedger',
  ```
- `SCHEMA`의 `headerRow`는 2, `dataStartRow`는 3으로 갱신.
- `getColumns` 기반 코드는 machine header key로 참조하도록 유지.
- CardDraws/BonusDraws 통합 시 비즈니스 로직 조정. 적립/사용 구분 컬럼은 `type` 또는 `source`로 둠.
- config 분리로 인한 로직 조정. `AppSettings`는 Key-Value 조회, `MissionDefinitions`는 별도 조회.

### 2.6 DEV 전체 동작 테스트

체크리스트 Phase 2 마지막 항목과 동일.

- 로그인 / 회원가입 / 비밀번호 재설정
- 미션 제출 / 새로고침
- 카드 뽑기 / 컬렉션 조회 / 교환
- H&P 카드 표시 / 정답 제출
- BBB 매칭 / 메시지 / 사진
- 공지사항 / 개발자 문의

### 2.7 산출물

- DEV 환경에서 새 스키마 + 새 GAS 코드가 완전히 동작
- 마이그레이션 함수가 idempotent하게 검증됨
- PROD 적용을 위한 모든 준비 완료

---

## Phase 3 — PROD 적용

**목표.** 라이브 서비스를 최소 다운타임으로 새 스키마로 전환.

### 3.1 사전 준비

- 운영진에 사전 공지 — 마이그레이션 시간대(새벽 권장) 안내
- 마이그레이션 윈도우 결정 — 사용자 적은 시간대 (새벽 2~4시)
- 작업 전 PROD GAS의 현재 상태 확인 (배포 버전 메모)

### 3.2 PROD 시트 백업

- PROD GAS에서 `migrate_step1_backup()` 실행
- 백업 시트 생성 확인 (`백업_YYYYMMDD_원본명` 모든 시트)
- 별도로 Google Drive에서 스프레드시트 전체 복제(`사본`) 1부 추가 보관

### 3.3 마이그레이션 실행

- PROD GAS에서 `migrate_runAll()` 실행
- `migrate_verify()` 로 결과 검증 (행 수·필수 컬럼 존재)

### 3.4 GAS 새 코드 배포

- DEV에서 검증된 GAS 코드를 PROD GAS에 복사
- **배포 → 배포 관리 → 기존 배포 편집 → 새 버전**으로 동일 URL 유지
- URL이 바뀐 경우 `app.js`와 `admin.html` 의 DEV/PROD `API_BASE` 동시 갱신
- `admin.html`은 dev/local hostname에서 바뀐 DEV GAS를 참조하고, 일반 배포 hostname에서는 PROD GAS를 참조하는지 확인

### 3.5 클라이언트 버전 동기화 + 배포

- 버전 bump (`YYYYMMDD?`) 세 곳 동시 변경.
  - `version.txt`
  - `app.js` 의 `APP_VERSION`
  - `sw.js` 의 `CACHE`
- dev 브랜치 커밋 → `git push origin dev`
- main 머지 + GitHub Pages 배포

### 3.6 스모크 테스트

실 사용자 계정으로 PROD 환경에서.
- 로그인 → 메인 → 미션 제출 → 카드 뽑기 → H&P → BBB → 공지/문의 → 로그아웃
- admin.html PROD 진입 → 주차 변경 / 탭 설정 / BBB 메시지 토글 확인
- admin.html dev/local 진입 → 같은 작업이 DEV GAS와 DEV 시트에만 반영되는지 확인

### 3.7 모니터링

- 첫 1시간 — 활성 사용자 행동 모니터링 (콘솔 에러, GAS 로그)
- 문제 발견 시 즉시 롤백 (3.8 참조)

### 3.8 롤백 절차 (문제 발생 시)

1. 백업 시트들을 원래 이름으로 되돌림 (수동 또는 `migrate_rollback()` 함수)
2. PROD GAS 이전 배포 버전으로 되돌리기 (배포 관리 → 이전 버전 활성화)
3. 클라이언트 버전 이전 값으로 되돌리고 재배포
4. 운영진에 상황 공지

### 3.9 후속 정리

- 백업 시트 1주일 보관 후 제거
- 운영진에 변경 내역 가이드 1장 전달 (어느 시트가 뭐 담고 있는지)
- `CLAUDE.md` 의 "시트 구성" 표 갱신
- 본 계획서 + 체크리스트 + `sheet-restructure-context.md` 보관

---

## 리스크 매트릭스 (요약)

| 리스크 | 영향 | 확률 | 완화책 |
|---|---|---|---|
| 마이그레이션 중 데이터 손실 | 치명 | 낮음 | Phase 3.2 백업 + Drive 사본 1부 |
| GAS URL 변경으로 클라이언트 끊김 | 높음 | 중간 | "기존 배포 편집" 사용 + URL 변경 시 즉시 클라이언트 갱신 |
| 컬럼 인덱스 코드가 새 헤더로 깨짐 | 높음 | 낮음 | Phase 1의 `getColumns` 헬퍼로 추상화 |
| 운영진이 변경 모름 | 중간 | 높음 | Phase 3.9 가이드 전달 |
| Phase 2 마이그레이션 함수 버그 | 중간 | 중간 | DEV 사본에서 dry-run + verify 함수 |

---

## 일정 가이드 (러프 추정)

| Phase | 예상 작업 시간 | 비고 |
|---|---|---|
| Phase 0 | 0.5~1일 | GAS 코드 전수조사 + 명세 작성 |
| Phase 1 | 1~2일 | 리팩토링 + DEV 테스트 + PROD 반영 |
| Phase 2 | 2~3일 | 스키마 확정 + 마이그레이션 함수 + DEV 검증 |
| Phase 3 | 0.5일 | PROD 적용 (실제 다운타임은 30분 이내 목표) |

**전체 권장 기한.** 수련회(6/22) 최소 1주 전인 6/15까지 완료. 그 이후는 행사 운영에 집중.
