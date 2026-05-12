<!-- 구글 시트 구조 개편 — 전체 작업 계획 (Phase 0~3) -->

# 시트 구조 개편 — Full Plan

> Phase 0(현황 파악) → Phase 1(GAS 리팩토링) → Phase 1.5(하드코딩 제거) → **Phase 2(스키마 + Event Sourcing 도입, 2A~2E)** → **Phase 3(PROD 단계 적용, 3A~3E)** 전체 로드맵.
> 진행 상황은 `sheet-restructure-checklist.md`, 결정 배경은 `sheet-restructure-context.md` 참조.
>
> **Phase 2부터의 아키텍처 변경 요지.** Events 시트가 단일 truth source. `Collection`은 Events에서 도출되는 pure projection (앱 성능용 캐시). `UserDashboard`는 시트 함수 기반 검증 뷰. 둘이 같은 Events에서 두 방식으로 도출되므로 어긋나면 즉시 정합성 버그 노출.

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

## Phase 2 — 새 스키마 + Event Sourcing 도입 (DEV)

**목표.** Events 시트 단일 truth source 구축 + Collection을 pure projection으로 전환 + UserDashboard 검증 뷰 + 속도 최적화. DEV에서 완전히 검증.

> DEV는 활성 사용자가 없으므로 dual-write 모니터링 없이 big-bang으로 전환한다. 단, 작업 산출물은 2A~2E로 나눠 검증한다.
> PROD는 활성 사용자 데이터가 있으므로 Phase 3에서 dual-write 안전 모드를 유지한다.

### 2.0 사전 설계 (문서)

먼저 `sheet-restructure-context.md` 에 다음을 명세.

**Events 시트 스키마.**

| col | 헤더 | 설명 |
|-----|------|------|
| A | eventId | UUID (`Utilities.getUuid()`) |
| B | timestamp | ISO 8601 |
| C | userId | 닉네임 |
| D | type | event type (점 표기 — `card.drawn`, `ticket.granted` 등) |
| E | payload | JSON 문자열 |
| F | source | `web` / `admin` / `migration` / `server` |

**Event type 카탈로그.**

| type | payload 예시 | 발생 시점 |
|------|------------|----------|
| `mission.submitted` | `{weekKey,items,dateKey}` | 미션 제출 |
| `ticket.granted` | `{reason,amount,weekKey?}` | 주차 완료, H&P 정답, 관리자 지급 |
| `ticket.consumed` | `{amount:1}` | 카드 뽑기 시 |
| `card.drawn` | `{cardId,isNew}` | 카드 뽑기 |
| `card.granted` | `{cardId,reason}` | 관리자 히든 카드 지급처럼 뽑기권 소모가 없는 카드 지급 |
| `card.removed` | `{cardId,reason}` | 관리자 테스트/정정용 카드 차감 |
| `trade.requested` | `{tradeId,target,reqCard,tgtCard}` | 교환 요청 |
| `trade.accepted` / `rejected` / `cancelled` | `{tradeId}` | 교환 상태 변경 |
| `trade.prayed` | `{tradeId}` | 응원 |
| `hp.guessed` | `{hpRowId,correct}` | H&P 정답 제출 |
| `bbb.guessed` | `{correct}` | BBB 추측 |
| `bbb.message_sent` | `{toUserId}` | BBB 메시지 |
| `bbb.photo_uploaded` | `{driveFileId}` | BBB 사진 |

**AppSettings 스키마 (Key-Value).**

```
| key                  | value         | note          |
| current_week         | 3             |               |
| app_open_date        | 2026-05-10    |               |
| bbb_message_open     | TRUE          |               |
| chat_open            | TRUE          |               |
| tab_settings         | {...}         | JSON          |
```

**MissionDefinitions 스키마 (1행=1항목).**

```
| weekKey | weekTitle | itemNo | itemText | scoreWeight |
| w1      | 주간1     | 1      | ...      | 1           |
| w1      | 주간1     | 2      | ...      | 1           |
| ...
```

**UserDashboard 컬럼 (모두 시트 함수).**

| col | 헤더 | 수식 예시 |
|-----|------|----------|
| A | userId | `=IF(Users!A2="","",Users!A2)` |
| B | 이름 | `=IFERROR(VLOOKUP(A3,Users!A:C,3,0),"")` |
| C | 교구 | `=IFERROR(VLOOKUP(A3,Users!A:D,4,0),"")` |
| D | 미션수 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"mission.submitted")` |
| E | 티켓획득 | `=SUMIFS(Events!F3:F,Events!C3:C,A3,Events!D3:D,"ticket.granted")` |
| F | 티켓사용 | `=SUMIFS(Events!F3:F,Events!C3:C,A3,Events!D3:D,"ticket.consumed")` |
| G | 남은권 | `=E3-F3` |
| H | 뽑은수 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"card.drawn")` |
| U | 마지막활동 | `=IFERROR(INDEX(SORT(FILTER(Events!B3:B5000,Events!C3:C5000=A3),1,FALSE),1),"")` |
| Y~AA | 일치? | `=IF(A3="","",IF(...,"✓","❌"))` |

---

### 2A — Events 시트 + DEV Big-Bang 백필

> DEV에서는 기존 시트와 장기간 dual-write하지 않는다. 백업 후 Events 시트를 만들고, 기존 데이터를 한 번에 Events로 백필한다.

**작업.**
- DEV 시트에 `Events` 시트 추가 + Row 1 운영진 라벨 + Row 2 machine header + 프리징.
- `Events_append(type, userId, options)` 헬퍼 작성. UUID + timestamp 자동 생성. `LockService`로 동시성 보호.
- `migrate_step5_absorbToEvents()` 로 기존 mutation 시트 데이터를 Events에 백필.
  ```js
  Events_append('mission.submitted', userId, {
    weekKey,
    payload: { items, dateKey },
    source: 'migration',
  });
  ```
- 이후 새 mutation 경로는 Events 기록을 기본으로 삼도록 Phase 2C~2D에서 전환.

**검증.**
- DEV 시트 사본에서 dry-run.
- `migrate_verify()` 로 기존 시트 row 수와 Events 백필 결과 비교.
- 샘플 유저별 mission/draw/ticket/trade 집계가 기존 Collection 및 원본 시트와 맞는지 확인.

**산출.**
- DEV Events 시트가 과거 데이터까지 포함한 truth source 후보가 됨.
- PROD용 dual-write 코드는 Phase 3A에서 별도로 적용.

---

### 2B — UserDashboard 시트 추가 [read-only]

> 시트 함수 기반 뷰. 앱 동작 경로 변경 없음. GAS에는 시트 생성용 setup 함수만 추가.

**작업.**
- `UserDashboard` 시트 생성. 헤더 + 첫 행 수식 작성 후 250행으로 fill-down.
- 조건부 서식 — `J` 열 ❌ 인 행을 빨갛게.

**검증.**
- 모든 행이 ✓ 인지 확인. ❌ 가 있다면 Phase 2A 백필 또는 집계 규칙에 누락 있음 → 추적해서 수정.
- 운영진이 매일 한 시트만 보면 정합성 확인 가능한지 사용성 점검.

**산출.**
- 250명 상태를 한눈에 보는 검증 도구. 이후 단계에서도 ✓ 유지가 정합성의 자명한 증거.

---

### 2C — 스키마 정규화 + 마이그레이션

> 시트 분리 / 헤더 정규화 / 하드코딩 외부화. DEV Events는 2A big-bang 백필로 이미 채워진 상태에서 진행.

**마이그레이션 함수 (모두 idempotent).**

```js
function migrate_step1_backup()              { /* 모든 시트 백업 사본 */ }
function migrate_step2_addSheetMetadata()    { /* 1행 운영진 라벨/설명 */ }
function migrate_step3_normalizeHeaders()    { /* 2행 machine header 정규화 */ }
function migrate_step4_splitConfig()         { /* config → AppSettings + MissionDefinitions */ }
function migrate_step5_absorbToEvents()      { /* 과거 raw_checkins/CardDraws/BonusDraws → Events 백필 */ }
function migrate_step6_externalizeHoldPray() { /* HOLD_PRAY_ENTRIES 하드코딩 → HoldPray 시트 */ }
function migrate_step7_orderAndColor()       { /* 시트 순서/탭 색상 */ }

function migrate_runAll() / migrate_verify()
```

**중요.** `migrate_step5_absorbToEvents`는 과거 데이터를 Events에 backfill하는 1회성 작업. DEV에서는 2A big-bang으로 실행하고, eventId는 새로 부여하되 source는 `migration`.

**HoldPray 처리.** `migrate_step6_externalizeHoldPray()`는 사용자가 나중에 한 번에 처리하기로 결정했으므로, Phase 2C 진행 중에는 보류한다. H&P read path와 `HOLD_PRAY_ENTRIES` 제거는 별도 묶음으로 다룬다.

**2C 적용 순서.** 첫 조각은 `migrate_step1_backup()` + `migrate_step4_splitConfig(_dryRun)` 로 제한한다. 즉 `AppSettings` / `MissionDefinitions` 시트를 만들고 기존 `config` 값을 복사하되, 앱의 read path는 아직 `config`에 둔다. DEV dry-run과 본 실행 결과를 확인한 뒤 `config` 읽기 함수를 새 시트 기반으로 전환한다.

**2C-2 read path 전환 기준.** `AppSettings` / `MissionDefinitions`가 있으면 새 시트를 우선 사용하고, 없거나 비어 있으면 기존 `config`를 fallback으로 사용한다. admin 쓰기 경로는 새 시트에 쓰되 legacy `config`도 함께 동기화해서 DEV 검증 중 즉시 rollback 할 수 있게 둔다.

**GAS 코드 갱신.**
- `SHEET_NAMES`에 새 시트 추가 (`APP_SETTINGS`, `MISSION_DEFINITIONS`, `EVENTS`).
- `SCHEMA` 의 `headerRow=2`, `dataStartRow=3` 으로 갱신 (Row 1은 운영진 라벨).
- `config` 읽는 코드 → `AppSettings` / `MissionDefinitions` 로 분기.
- `HOLD_PRAY_ENTRIES` 참조 → `HoldPray` 시트 read 로 전환.

**검증.**
- DEV 시트 사본에서 dry-run.
- 본 실행 + `migrate_verify()`.
- UserDashboard ✓ 유지.

---

### 2D — Read Path 전환 (Collection을 Projection으로)

> Collection 직접 setValue 제거. Events 기반 재계산만 사용. 코어 mutation 경로 변경 — 가장 신중하게.

**작업.**
- 먼저 `previewCollectionProjection(userId)`로 기존 Collection row와 Events 기반 계산값을 비교한다. 이 단계에서는 어떤 row도 쓰지 않는다.
- `rebuildCollectionRow(userId)` 함수 작성.
  ```js
  function rebuildCollectionRow(userId) {
    const events = Events.readByUser(userId);
    const granted = sumPayloadAmount(events, 'ticket.granted');
    const consumed = events.filter(e => e.type === 'ticket.consumed').length;
    const drawn = events.filter(e => e.type === 'card.drawn').length;
    const cardCounts = countCardsFromEvents(events);
    const tradeAdjust = computeTradeAdjustments(events);
    // ... 합산 후 Collection row 통째로 setValues
  }
  ```
- 현재 구현은 공개 함수 `rebuildCollectionRow(userId)`가 Lock을 잡고, 내부 헬퍼 `rebuildCollectionRow_(userId)`가 실제 upsert를 수행하는 구조다. 다음 단계에서 이미 Lock을 잡고 있는 mutation 함수들은 내부 헬퍼를 호출한다.
- DEV 검증 편의를 위해 `adminRebuildCollectionRow` POST 액션도 추가한다. UI에는 노출하지 않고 수동 검증용으로만 사용한다.
- `Events_append()`는 기존 공개 함수 형태를 유지하되, Lock 내부 mutation에서 재사용할 수 있도록 내부 헬퍼 `Events_append_()`를 분리한다.
- mutation 경로에서 `updateCollectionSheet` / `updateTicketCols` 등의 직접 +1/-1 setValue 제거.
  - 패턴 통일.
    ```js
    Events.append(type, userId, payload, source);
    rebuildCollectionRow(userId);
    ```
- 관리자 히든 카드 지급은 `card.drawn`이 아니라 `card.granted`로 기록한다. `card.granted`는 보유 카드 수와 총카드수에는 반영하지만, 실제 뽑은 개수에는 반영하지 않는다.
- DEV 교환 테스트용 `adminGrantTestCard`는 `ENABLE_TEST_ADMIN_TOOLS=true` Script Property가 있을 때만 동작한다. 테스트 카드 지급도 `Collection` 직접 수정 없이 `card.granted` 이벤트와 `rebuildCollectionRow_()`만 사용한다.
- admin `Events 관리` 패널에서 `card.granted`/`card.removed` 이벤트를 생성하고, Events 기준으로 `Collection` + `UserDashboard`를 다시 계산할 수 있게 한다.
- 기존 `rebuildCollectionSheet`(전체)는 검증/긴급 정비용으로 보존.

**검증.**
- DEV 전체 시나리오 테스트 (로그인부터 BBB까지).
- UserDashboard 검증 컬럼 ✓ 유지.
- 카드 뽑기 응답 시간 측정 (2E 전 기준점).

**현재 확인된 DEV 상태.**
- `previewCollectionProjection()`은 사용자 확인 기준 `mismatchCount: 0`.
- `setupUserDashboard()` 재실행 후 검증 컬럼 ✓ 유지.
- BBB M1 케어버디 사진 업로드는 `BBBPhotos` 저장, `BonusDraws.bbb_photo`, `Events.ticket.granted`, `Collection` row rebuild까지 확인.
- BBB M1 재업로드는 중복 뽑기권을 지급하지 않는 것으로 확인.
- `adminGrantHiddenCard` 구현은 완료했지만 수동 지급 검증은 당장 보류. 필요 시 admin action 또는 인자 있는 래퍼로만 실행한다.
- H&P 하드코딩 제거(`migrate_step6_externalizeHoldPray`)는 나중에 한 번에 처리하기로 보류.

**다음 확인.**
- admin `Events 관리` 패널에서 카드 추가와 삭제 event를 각각 생성하고 앱 컬렉션 반영 확인 완료.
- admin `Events 기준 재계산`으로 `Collection`과 `UserDashboard` 정합성 확인 완료.
- 로그인, 회원가입, 비밀번호 재설정, 미션 제출, 카드 뽑기, 교환, H&P, BBB, 공지, 개발자 문의까지 DEV 전체 회귀 테스트 완료.
- 다음 작업은 Phase 2E 속도 최적화 또는 PROD Phase 3 적용 전 최종 정리.

---

### 2E — 속도 최적화

> 단계별 코드 변경이 GAS RPC 호출을 늘렸을 수 있으므로 마지막에 정리. 안정성 우선 원칙에 따라 이 단계에서 시트를 바로 삭제하지 않는다. 먼저 legacy 참조를 줄이고, 삭제 후보 탭을 숨긴 상태로 회귀 테스트한 뒤, 전체 Phase 완료 후 삭제한다.

**작업.**
- legacy 참조 감사.
  - `Collection`은 Events 기반 projection cache라 유지.
  - `Trades`는 진행 중 교환 UI 상태를 담고 있어 유지.
  - `CardDraws`, `BonusDraws`, `raw_checkins`, `config`는 삭제 후보지만 코드 참조 제거 전 삭제 금지.
- 위험 낮은 read path부터 Events 기준으로 전환.
  - `getUserStatus()`의 이번 주 카드 뽑기 여부는 `Events.card.drawn`으로 전환.
  - `BonusDraws` 중복 지급 체크는 Events 우선 + legacy fallback 구조로 단계 전환.
- Sheets API v4 Advanced Service 활성화.
- `Sheets.Spreadsheets.Values.batchGet` / `batchUpdate` 도입 — 함수당 RPC 횟수 감소.
- 캐시 키 정밀화.
  ```js
  // 변경 전 — 전체 무효화
  clearHotCaches_();
  // 변경 후 — 유저별
  clearUserCache_(userId);
  ```
- 함수당 `getSpreadsheet()` 호출 1회로 통합.
- 카드 뽑기 응답 시간 측정. 2D 후 ~1000ms → 2E 후 ~500ms 목표.

---

### 2.7 산출물

- DEV 환경에서 Event Sourcing + Dual Projection이 완전히 동작
- UserDashboard 검증 컬럼 전부 ✓
- 카드 뽑기 응답 ~500ms 이하
- PROD 단계별 배포 준비 완료

---

## Phase 3 — PROD 단계별 적용 (3A~3E)

**목표.** PROD를 Phase 2와 같은 순서로 단계별 전환. 각 단계 사이에 모니터링.

> 한 번에 다 옮기지 않음. 2A→3A, 2B→3B 식으로 짝지어 며칠 간격으로 적용.

### 3.0 사전 준비

- 운영진에 단계별 일정 안내.
- 각 단계는 가능하면 사용자 적은 시간대 (새벽 2~4시) 배포.
- 배포 직전 PROD GAS 현재 배포 버전 메모 (롤백용).

### 3A — PROD Events 시트 + Dual-Write 배포

- PROD 시트에 `Events` 시트 생성.
- PROD GAS에 2A 코드 배포 — **기존 배포 편집 → 새 버전** (URL 유지).
- 며칠 모니터링 — `verifyDualWrite()` 정기 실행.

### 3B — PROD UserDashboard 추가

- PROD 시트에 `UserDashboard` 시트 + 시트 함수.
- 운영진과 함께 ✓ 떨어지는지 1차 확인.
- ❌ 발견 시 dual-write 누락 추적 후 패치.

### 3C — PROD 스키마 마이그레이션

- PROD 시트 전체 백업.
  - `migrate_step1_backup()` 실행 → `백업_YYYYMMDD_*` 시트 생성.
  - Google Drive에서 스프레드시트 전체 사본 1부 추가 보관.
- PROD GAS에서 `migrate_runAll()` 실행.
- `migrate_verify()` 검증.
- HoldPray / AppSettings / MissionDefinitions 동작 확인.
- 사용자 영향 — 마이그레이션 중 ~10~15분 GAS 응답 지연 가능. 사전 공지 필요.

### 3D — PROD Collection Projection 전환

- PROD GAS에 2D 코드 배포.
- 즉시 스모크 테스트 — 로그인 / 미션 제출 / 카드 뽑기 / 컬렉션 확인.
- UserDashboard ✓ 유지 확인.
- 1시간 활성 사용자 모니터링. ❌ 나오면 즉시 롤백.

### 3E — PROD 속도 최적화

- PROD GAS에 2E 코드 배포.
- 응답 시간 개선 측정.
- 운영진 / 일부 사용자 체감 보고 수집.

### 3.9 마무리

- `app.js` + `admin.html` 의 `API_BASE` 갱신 (URL 바뀐 경우만).
- 버전 bump 세 곳 동시 변경 — `version.txt`, `app.js` `APP_VERSION`, `sw.js` `CACHE`.
- dev 브랜치 커밋 → main 머지 → GitHub Pages 배포.
- 운영진에 완료 보고 + 변경 내역 가이드 (어느 시트가 뭐 담고 있는지).
- `CLAUDE.md` 의 "시트 구성" 표 갱신 (Events / UserDashboard / AppSettings / MissionDefinitions 추가, 흡수된 시트 표시).
- 백업 시트 1주일 보관 후 제거.

### 3.X 롤백 절차

각 단계별로 다름.

- **3A 롤백.** GAS 이전 배포 버전 활성화. Events 시트는 그대로 두거나 비움.
- **3B 롤백.** UserDashboard 시트 숨김 또는 삭제. GAS 영향 없음.
- **3C 롤백.** 백업 시트로 수동 복원 또는 `migrate_rollback()` 함수. GAS 이전 배포 활성화.
- **3D 롤백.** GAS 이전 배포 활성화. Events는 그대로 (다음 시도 시 재사용). Collection은 마지막 정상 상태 유지.
- **3E 롤백.** GAS 이전 배포 활성화. 단순 성능 변경이라 위험 낮음.

---

## 리스크 매트릭스 (요약)

| 리스크 | 단계 | 영향 | 확률 | 완화책 |
|---|---|---|---|---|
| Events.append 실패로 mutation 손실 | 2A/3A | 높음 | 낮음 | DEV는 dry-run + verify로 검증. PROD는 Phase 3A dual-write라 기존 시트엔 남음 |
| 마이그레이션 중 데이터 손실 | 2C/3C | 치명 | 낮음 | 3C 백업 + Drive 사본 1부 |
| Collection projection 버그 | 2D/3D | 높음 | 중간 | UserDashboard ✓ 자동 검증. ❌ 발견 즉시 롤백 |
| GAS URL 변경으로 클라이언트 끊김 | 3* | 높음 | 중간 | "기존 배포 편집" 사용 + URL 변경 시 즉시 클라이언트 갱신 |
| 컬럼 인덱스 코드가 새 헤더로 깨짐 | 2C/3C | 높음 | 낮음 | Phase 1 `getColumns` 헬퍼로 추상화 완료 |
| 운영진이 변경 모름 | 3.9 | 중간 | 높음 | 단계별 사전 공지 + 완료 시 가이드 |
| 마이그레이션 함수 버그 | 2C | 중간 | 중간 | DEV 사본 dry-run + `migrate_verify` |
| 속도 최적화로 캐시 정합성 깨짐 | 2E/3E | 중간 | 낮음 | 캐시 키 좁히는 변경이라 위험 낮음. UserDashboard로 사후 검증 |

---

## 일정 가이드 (러프 추정)

| Phase | 예상 작업 시간 | 비고 |
|---|---|---|
| Phase 0 | 완료 | GAS 코드 전수조사 + 명세 |
| Phase 1 | 완료 | SHEET_NAMES + SCHEMA + getColumns 헬퍼 |
| Phase 1.5 | 거의 완료 | Script Properties + 일부 HIGH 버그 수정 |
| Phase 2.0 (설계) | 0.5~1일 | Events 스키마 + AppSettings + MissionDefinitions 명세 |
| Phase 2A | 1~2일 | DEV Events 시트 생성 + big-bang 백필. dry-run 필수 |
| Phase 2B | 0.5일 | 시트 함수만. 위험 없음 |
| Phase 2C | 2~3일 + 검증 | 마이그레이션 함수 + GAS 코드 갱신 |
| Phase 2D | 2~3일 | Collection projection 전환. 신중 |
| Phase 2E | 1~2일 | batchGet 도입 + 캐시 정밀화 |
| Phase 3 (전체) | 1~2주 (단계별 며칠 간격) | PROD 단계별 배포 |

**전체 권장 기한.** 수련회(6/20~22) 최소 1주 전인 6/13까지 완료. Phase 3가 단계별이라 여유 있게 시작.

**오늘(5/12) 기준 권장 시작.**
- 5/12~5/14 — Phase 2.0 설계 문서
- 5/15~5/17 — Phase 2A DEV big-bang 백필 + 검증
- 5/18~5/20 — Phase 2B UserDashboard
- 5/21~5/25 — Phase 2C 마이그레이션
- 5/26~5/29 — Phase 2D Collection projection
- 5/30~6/1 — Phase 2E 속도 최적화
- 6/2~6/13 — Phase 3 PROD 단계별 적용
- 6/14~6/19 — 행사 운영 준비 집중
