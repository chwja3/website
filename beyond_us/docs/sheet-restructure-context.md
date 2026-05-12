<!-- 구글 시트 구조 개편 — 결정 사항 및 배경 노트 -->

# 시트 구조 개편 — Context Notes

> 작업하면서 내린 결정과 배경을 누적 기록. 다음 세션(나든 다른 사람이든)이 이 노트만 봐도 의사결정 맥락을 복원할 수 있어야 함.

---

## 작업 목적

- 운영진이 시트 보고 뭐가 뭔지 모름 (네이밍 직관성 부족)
- 데이터가 시트 사이에 흩어져 추적 어려움 (그룹화 / 외래키 일관성 부족)
- (간접 목표) 다음 행사 재사용 시 코드 견고함 확보 — 컬럼 추가/변경에도 안 깨지는 구조

## 제약 조건

- **라이브 서비스 운영 중** — 약 250명 사용자 활성. 다운타임 최소화 필수
- 수련회 일정 ~6/22. 그 전 마무리 권장
- 백엔드 교체 (Firestore 등) 는 6/22 이후 별도 작업. 지금은 시트 구조만 정리

---

## Phase 0 조사 결과 — 현재 스키마

조사 기준. `Apps_Script` 로컬 소스의 `getSheetByName`, `insertSheet`, `appendRow`, `getRange`, `setValues`, `getValues` 사용처를 기준으로 복원했다. 실제 운영 시트에 수동 추가된 컬럼이 있을 수 있으므로 PROD 적용 전 Google Sheet의 실제 헤더와 1회 대조가 필요하다.

### 현재 시트 목록

| 시트명 | 생성/접근 함수 | 역할 |
|---|---|---|
| `Users` | `getUsersSheet_`, `registerUser`, `loginUser`, `setupBBBMatching` | 회원, 인증, 운영진/DEV/BBB 대상 플래그 |
| `config` | `getConfig`, `getAppOpenDate`, `getMissionConfig`, `setMissionConfig`, `getTabSettings` | 현재 주차, 앱 오픈일, 미션 정의, 과거 탭/BBB 설정 |
| `raw_checkins` | `saveCheckin`, `getDashboardData`, `getUserStatus`, `updateTicketCols` | 미션 제출 이력과 주차 누적 점수 |
| `CardDraws` | `getOrCreateDrawSheet`, `drawCard`, `getUserStatus`, `rebuildCollectionSheet` | 카드 뽑기 사용 이력 |
| `BonusDraws` | `getOrCreateBonusDrawsSheet`, `submitHoldPrayGuess`, `uploadBBBPhoto` | 보너스 뽑기권 적립 이력 |
| `Collection` | `getOrCreateCollectionSheet`, `updateCollectionSheet`, `updateTicketCols`, `rebuildCollectionSheet` | 카드 보유 현황과 뽑기권 캐시 |
| `CardReceived` | `getOrCreateCardReceivedSheet`, `setCardReceivedQty`, `getCardStats` | 실물 카드 수령 수량 |
| `Trades` | `getOrCreateTradesSheet`, `requestTrade`, `acceptTrade`, `getTrades` | 카드 교환 요청과 처리 결과 |
| `HoldPray` | `getOrCreateHoldPraySheet`, `migrateHoldPrayToSheet`, `getYouthHpEntries` | H&P 기도제목 원천 시트 후보 |
| `HPGuesses` | `getOrCreateHPGuessesSheet`, `submitHoldPrayGuess`, `getHoldPray` | H&P 정답 제출 이력 |
| `TabSettings` | `getOrCreateTabSettingsSheet`, `getTabSettings`, `setTabSettings` | 주요 탭 오픈 여부 |
| `BBBSettings` | `getOrCreateBBBSettingsSheet`, `getTabSettings`, `setTabSettings` | BBB 섹션 오픈 여부와 안내문 |
| `BBB` | `getOrCreateBBBSheet`, `setupBBBMatching`, `getBBB`, `adminGetBBB` | BBB 매칭 관계 |
| `BBBMessages` | `getOrCreateBBBMessagesSheet`, `sendBBBMessage`, `getBBBMessages` | BBB 익명 메시지 |
| `BBBPhotos` | `getOrCreateBBBPhotosSheet`, `uploadBBBPhoto`, `deleteBBBPhoto`, `getBBB` | BBB 사진 업로드 |
| `Notices` | `getOrCreateNoticeSheet`, `getNotices`, `postNotice`, `editNotice` | 공지사항 |
| `Inquiries` | `getOrCreateInquirySheet`, `postInquiry`, `replyInquiry`, `postHpHint` | 개발자 문의와 H&P 힌트 요청 |

### `Users`

| col | 현재 헤더/의미 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `nickname` | `row[0]` | 로그인 ID, 사용자 식별자, BBB userId |
| B | `password` | `row[1]` | 로그인/비밀번호 재설정. 현재 평문 저장 |
| C | `name` | `row[2]` | 본명, 닉네임 찾기, BBB 표시명 |
| D | `parish` | `row[3]` | 교구, 사용자 표시, `migrateParishJangnyeon` |
| E | `createdAt` | `row[4]` | 회원 생성일 |
| F | `isStaff` | `row[5]` | 운영진 여부, 오픈 전 앱 진입 |
| G | `isDev` 또는 `isTFRetreat` | `row[6]` | DEV 표시와 BBB 매칭 대상. 의미가 코드 주석에서 혼재 |
| H | `sessionToken` | `row[7]`, `SESSION_TOKEN_COL = 8` | 세션 토큰 배열 저장 |
| I | `sessionUpdatedAt` | `row[8]`, `SESSION_UPDATED_AT_COL = 9` | 세션 갱신 시각 |

리스크. B열 비밀번호가 평문이고, G열 의미가 `isDev`와 `isTFRetreat`로 혼재되어 있다.

### `config`

| 위치 | 현재 의미 | 사용처 |
|---|---|---|
| A1 | `current_week` 라벨 | `setupAllWeeks` |
| B1 | 현재 주차 번호 | `getConfig`, `getCurrentWeek`, `setCurrentWeek`, `updateTicketCols` |
| C1 | 구버전 BBB 메시지 오픈 여부 | `isBBBMessageOpen`, `adminSetBBBMessageOpen` fallback |
| B2 | 구버전 Hold & Pray 탭 오픈 여부 | `getOrCreateTabSettingsSheet`, `getTabSettings` fallback |
| B3 | 구버전 현장미션 탭 오픈 여부 | `getOrCreateTabSettingsSheet`, `getTabSettings` fallback |
| B4 | 앱 오픈일 | `getAppOpenDate` |
| D1 | 구버전 채팅방 탭 오픈 여부 | `getOrCreateTabSettingsSheet`, `getTabSettings` fallback |
| D2 | 구버전 BBB 섹션 JSON | `getOrCreateBBBSettingsSheet` 최초 마이그레이션 |
| 주차 block | `startRow = (week - 1) * 8 + 5` | `getConfig`, `setupAllWeeks`, `getMissionConfig`, `setMissionConfig` |
| block row 1, B | 주차 제목 | `weekTitle` |
| block row 1, C | 뽑기 기준 점수 | `drawThreshold` |
| block rows 2~7, A | 미션 텍스트 | `items` |
| block rows 2~7, B | 미션 점수 | `scores` |
| block rows 2~7, C | 미션 카테고리 | `cats` |

리스크. 단일 설정과 반복 미션 정의가 같은 시트에 섞여 있고, 셀 주소 기반 접근이 많다.

### `raw_checkins`

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `timestamp` | `row[0]` | 제출 시각 |
| B | `weekTitle` | `row[1]` | 주차별 집계 기준 |
| C | `items_json` | `row[2]` | 제출한 미션 텍스트 배열 |
| D | `userId` | `row[3]` | 닉네임 |
| E | `weekKey` | `row[4]` | 클라이언트 주차 key |
| F | `dateKey` | `row[5]` | 날짜별 중복 제출 방지 |
| G | `score` | `row[6]` | 제출 점수 |
| H | `indices_json` | `row[7]` | 미션 텍스트 변경 후에도 제출 상태 유지 |
| I | `weekCumScore` | `row[8]` | 주차 누적 점수 |
| J | `ticketEarned` | `row[9]` | threshold 최초 달성 여부 |

### `CardDraws`

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `userId` | `row[0]` | 닉네임 |
| B | `weekKey` | `row[1]` | 주차별 뽑기 여부 |
| C | `cardId` | `row[2]` | 카드 ID |
| D | `cardName` | `row[3]` | 카드명 |
| E | `drawnAt` | `row[4]` | 뽑은 시각 |
| F | `received` | `row[5]` | 과거 실물 수령 체크. 현재는 `CardReceived`가 주된 수령 수량 시트 |

### `BonusDraws`

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `userId` | `row[0]` | 닉네임 |
| B | `source` | `row[1]` | `hp_w3`, `hp_w6`, `bbb_photo`, `bbb_m2`, `bbb_m3` 등 보상 원인 |
| C | `awardedAt` | `row[2]` | 지급 시각 |

### `Collection`

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `userId` | `row[0]` | 닉네임 |
| B | `누적뽑기권` | `row[1]` | 총 획득 뽑기권 |
| C | `실제뽑은개수` | `row[2]` | 실제 카드 뽑기 횟수 |
| D | `남은개수` | `row[3]` | 현재 사용 가능 뽑기권 |
| E | `사랑` | `row[4]` | 카드 1 보유 수 |
| F | `희락` | `row[5]` | 카드 2 보유 수 |
| G | `화평` | `row[6]` | 카드 3 보유 수 |
| H | `오래참음` | `row[7]` | 카드 4 보유 수 |
| I | `자비` | `row[8]` | 카드 5 보유 수 |
| J | `양선` | `row[9]` | 카드 6 보유 수 |
| K | `충성` | `row[10]` | 카드 7 보유 수 |
| L | `온유` | `row[11]` | 카드 8 보유 수 |
| M | `절제` | `row[12]` | 카드 9 보유 수 |
| N | `총카드수` | `row[13]` | 총 보유 카드 수 |
| O | `히든` | `row[14]` | 히든 카드 보유 수 |

리스크. E~O열이 카드 정의와 강하게 결합되어 있어 카드 추가 시 코드와 시트가 동시에 바뀐다.

### `CardReceived`

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `nickname` | `row[0]` | 닉네임 |
| B | `cardId` | `row[1]` | 카드 ID |
| C | `receivedQty` | `row[2]` | 실물 수령 수량 |
| D | `updatedAt` | `row[3]` | 갱신 시각 |

### `Trades`

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `id` | `row[0]` | 교환 요청 ID |
| B | `requester` | `row[1]` | 요청자 닉네임 |
| C | `requesterCardId` | `row[2]` | 요청자가 줄 카드 ID |
| D | `requesterCardName` | `row[3]` | 요청자가 줄 카드명 |
| E | `target` | `row[4]` | 대상자 닉네임 |
| F | `targetCardId` | `row[5]` | 대상자가 줄 카드 ID |
| G | `targetCardName` | `row[6]` | 대상자가 줄 카드명 |
| H | `status` | `row[7]` | `pending`, `accepted`, 실패 사유 문자열 |
| I | `createdAt` | `row[8]` | 생성 시각 |
| J | `resolvedAt` | `row[9]` | 처리 시각 |
| K | `requesterPrayed` | `row[10]` | 요청자 기도 확인 시각 |
| L | `targetPrayed` | `row[11]` | 대상자 기도 확인 시각 |

### H&P 관련 시트

`HoldPray`.

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `이름(n)` | `row[0]` | 정답 이름 |
| B | `교구(p)` | `row[1]` | 교구 |
| C | `기도제목(c)` | `row[2]` | 기도제목 본문 |
| D | `익명(a)` | `row[3]` | 익명 여부 |
| E | `닉네임(nick)` | `row[4]` | 계정 닉네임 |

`HPGuesses`.

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `nickname` | `row[0]` | 제출자 닉네임 |
| B | `weekKey` | `row[1]` | 주차 key |
| C | `cardIndex` | `row[2]` | H&P 카드 인덱스 |
| D | `guessedName` | `row[3]` | 제출한 이름 |
| E | `answeredAt` | `row[4]` | 제출 시각 |

리스크. 현재 `HOLD_PRAY_ENTRIES` 하드코딩 배열이 여전히 원천 데이터로 남아 있고, `migrateHoldPrayToSheet`가 1회 이전용으로 존재한다.

### 설정 분리 후보 시트

`TabSettings`.

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `tab_key` | `row[0]` | `holdpray`, `secret`, `chat` |
| B | `label` | `row[1]` | 관리자 표시명 |
| C | `enabled` | `row[2]` | 탭 활성화 여부 |

`BBBSettings`.

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `key` | `row[0]` | `careBuddy`, `m1`, `m2`, `m3`, `secretBuddy`, `msgOpen` |
| B | `open` | `row[1]` | 섹션 오픈 여부 |
| C | `text` | `row[2]` | Coming Soon 안내문 |

### BBB 관련 시트

`BBB`.

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `userId` | `row[0]` | 닉네임 |
| B | `careBuddyId` | `row[1]` | 내가 챙기는 사람 닉네임 |
| C | `careBuddyName` | `row[2]` | 내가 챙기는 사람 이름 |
| D | `secretRevealed` | `row[3]` | 내 시크릿버디를 맞혔는지 |
| E | `secretBuddyId` | `row[4]` | 나를 챙기는 사람 닉네임 |
| F | `secretBuddyName` | `row[5]` | 나를 챙기는 사람 이름 |

`BBBMessages`.

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `msgId` | `row[0]` | 메시지 ID |
| B | `fromUserId` | `row[1]` | 발신자 닉네임 |
| C | `toUserId` | `row[2]` | 수신자 닉네임 |
| D | `message` | `row[3]` | 메시지 본문 |
| E | `createdAt` | `row[4]` | 생성 시각 |

`BBBPhotos`.

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `userId` | `row[0]` | 닉네임 |
| B | `photoBase64` | `row[1]` | 사진 base64 |
| C | `uploadedAt` | `row[2]` | 업로드 시각 |
| D | `missionType` | `row[3]` | `m1`, `m2`, `m3_0` 등 |

리스크. 문서에는 `BBB_Messages`, `BBB_Photos`가 나오지만 실제 GAS 시트명은 `BBBMessages`, `BBBPhotos`다.

### 공지와 문의

`Notices`.

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `id` | `row[0]` | 공지 ID |
| B | `title` | `row[1]` | 제목 |
| C | `content` | `row[2]` | 본문 |
| D | `createdAt` | `row[3]` | 생성 시각 |
| E | `imageUrl` | `row[4]` | 단일 URL 또는 JSON URL 배열 |
| F | `updatedAt` | `row[5]` | 수정 시각 |

`Inquiries`.

| col | 헤더 | GAS 인덱스 | 사용처 |
|---|---|---|---|
| A | `id` | `row[0]` | 문의 ID |
| B | `nickname` | `row[1]` | 작성자 닉네임 |
| C | `content` | `row[2]` | 문의 본문 또는 H&P 힌트 요청 |
| D | `createdAt` | `row[3]` | 생성 시각 |
| E | `reply` | `row[4]` | 답변 |
| F | `repliedAt` | `row[5]` | 답변 시각 |

### 영향받는 GAS 함수 목록

| 도메인 | 함수 |
|---|---|
| 공통/환경 | `doGet`, `doPost`, `getSpreadsheet`, `cacheKey_`, `clearHotCaches_` |
| 인증/회원 | `getUsersSheet_`, `findUserRow_`, `issueSessionToken_`, `clearSessionToken_`, `touchSessionToken_`, `verifySession`, `registerUser`, `loginUser`, `resetPassword`, `getUsers`, `findNickname`, `adminResetPassword`, `verifyUserPassword`, `migrateParishJangnyeon` |
| 미션/config | `getConfig`, `saveCheckin`, `setupRawCheckinsHeader`, `backfillRawCheckinsCols`, `getDashboardData`, `getUserStatus`, `setupAllWeeks`, `fixConfigSheetConflict`, `getMissionConfig`, `setMissionConfig`, `getAppOpenDate` |
| 카드/뽑기권 | `getOrCreateBonusDrawsSheet`, `getBonusDrawCount`, `getOrCreateDrawSheet`, `drawCard`, `getOrCreateCollectionSheet`, `getUserCollection`, `getCollectionTickets`, `getTicketStats`, `updateCollectionSheet`, `updateTicketCols`, `rebuildCollectionSheet`, `adminRebuildCollection`, `migrateCardDrawsToCollection`, `getOrCreateCardReceivedSheet`, `setCardReceivedQty`, `setDrawReceived`, `getCardStats`, `adminGrantHiddenCard` |
| 교환 | `getOrCreateTradesSheet`, `requestTrade`, `acceptTrade`, `rejectTrade`, `cancelTrade`, `_expireOldTrades`, `getTrades`, `prayForTrade`, `getAdminTrades` |
| H&P | `getOrCreateHoldPraySheet`, `migrateHoldPrayToSheet`, `getYouthHpEntries`, `fixHoldPrayBlankNames`, `getHoldPray`, `getOrCreateHPGuessesSheet`, `submitHoldPrayGuess`, `postHpHint`, `addHoldPrayRows`, `fixHoldPrayTypos` |
| 탭/BBB 설정 | `getOrCreateTabSettingsSheet`, `getOrCreateBBBSettingsSheet`, `isBBBMessageOpen`, `getTabSettings`, `setTabSettings`, `adminSetBBBMessageOpen` |
| BBB | `getOrCreateBBBSheet`, `getOrCreateBBBMessagesSheet`, `getOrCreateBBBPhotosSheet`, `uploadBBBPhoto`, `deleteBBBPhoto`, `adminWriteBBBRows`, `setupBBBMatching`, `getBBB`, `guessBBBSecret`, `sendBBBMessage`, `getBBBMessages`, `adminGetBBB` |
| 공지/문의 | `getOrCreateNoticeSheet`, `getNoticeFolder`, `uploadNoticeToDrive`, `uploadMultipleImages`, `getNotices`, `postNotice`, `deleteNotice`, `deleteDriveImages`, `editNotice`, `getOrCreateInquirySheet`, `getInquiries`, `postInquiry`, `editInquiry`, `deleteInquiry`, `replyInquiry` |
| 백업 | `backupSpreadsheet`, `_cleanOldBackups` |

### Phase 0 결론

- 현재 GAS는 탭 이름과 컬럼 위치에 강하게 묶여 있다.
- `getOrCreate*Sheet` 계열은 헤더를 생성하므로 스키마 복원이 비교적 명확하다.
- `Users`, `config`, `raw_checkins`, `Collection`, `Trades`는 Phase 1에서 가장 먼저 상수와 row mapper를 적용해야 한다.
- 한글 탭명으로 바꾸기보다 영문 key 탭명을 유지하고, 사람이 보는 라벨과 설명을 별도 메타데이터로 두는 방향이 더 안전하다.
- 하드코딩 제거는 시트 구조 개편과 같이 추적하되, 실행은 별도 Phase 1.5로 분리하는 편이 안전하다.

---

## 최종 스키마 (목표)

### 시트 이름 정책

**결정. 시트 탭 이름은 영문 key를 유지한다.** 운영진용 한글 라벨과 설명은 각 시트의 메타 영역 또는 별도 `SheetCatalog` 시트에 둔다. 이렇게 하면 코드와 관리자 문서가 같은 의미를 공유하면서도, 탭명 변경으로 GAS가 깨질 위험을 줄일 수 있다.

추천 구조.

- 탭 이름. 안정적인 영문 key 유지. 예. `Users`, `MissionSubmissions`, `CardDraws`.
- Row 1. 운영진용 한글 라벨과 설명. 예. `label=회원`, `description=참가자 계정과 권한`.
- Row 2. 코드가 참조하는 machine header. 예. `nickname`, `passwordHash`, `parish`.
- 데이터 시작 행. Row 3.
- Phase 1에서 `SCHEMA.SHEETS.USERS.headerRow = 2`, `dataStartRow = 3`처럼 명시한다.

### 목표 시트 목록

| 도메인 | 목표 영문 key | 현재 시트 | 운영진 라벨 | 비고 |
|---|---|---|---|
| 회원 | `Users` | `Users` | 회원 | 유지 |
| 설정 | `AppSettings` | `config` 일부 | 앱 설정 | Key-Value 형태 |
| 설정 | `MissionDefinitions` | `config` 일부 | 미션 정의 | 1행 1미션 권장 |
| 미션 | `MissionSubmissions` | `raw_checkins` | 미션 제출이력 | 이름 변경은 마이그레이션 때만 검토 |
| 카드 | `CardLedger` | `CardDraws` + `BonusDraws` | 카드 뽑기권 이력 | 적립/사용 ledger로 통합 후보 |
| 카드 | `Collection` | `Collection` | 카드 보유현황 | 캐시 역할 유지 |
| 카드 | `CardReceived` | `CardReceived` | 실물 카드 수령 | 유지 |
| 카드 | `Trades` | `Trades` | 카드 교환 | 유지 |
| H&P | `HoldPray` | `HoldPray` | H&P 기도제목 | 하드코딩 제거 후 원천 시트 |
| H&P | `HPGuesses` | `HPGuesses` | H&P 정답 이력 | 유지 |
| BBB | `BBB` | `BBB` | BBB 매칭 | 유지 |
| BBB | `BBBMessages` | `BBBMessages` | BBB 메시지 | 실제 코드명 기준 |
| BBB | `BBBPhotos` | `BBBPhotos` | BBB 사진 | 실제 코드명 기준 |
| 설정 | `TabSettings` | `TabSettings` | 탭 설정 | 유지 |
| 설정 | `BBBSettings` | `BBBSettings` | BBB 설정 | 유지 |
| 소통 | `Notices` | `Notices` | 공지사항 | 유지 |
| 소통 | `Inquiries` | `Inquiries` | 개발자문의 | 유지 |

### 컬럼 표준화 원칙

- machine header는 영문 key를 사용한다. 예. `nickname`, `createdAt`, `updatedAt`.
- 운영진이 보는 한글 컬럼명은 Row 1 라벨 또는 별도 설명 영역에 둔다. 예. `닉네임`, `생성일시`, `수정일시`.
- 사용자 식별자 machine header는 가능하면 `nickname`으로 통일한다. 기존 `userId`, `userName`은 mapper에서 흡수한다.
- 생성 시각은 `createdAt`, 수정 시각은 `updatedAt`, row 고유 ID는 `id`로 통일한다.

---

## Phase 2.0 — Event Sourcing 상세 설계

> 새 아키텍처의 핵심. Events 시트가 단일 truth source. Collection은 Events에서 도출되는 pure projection. UserDashboard는 시트 함수 기반 검증 뷰.
> 이 섹션은 (A) Events 시트 스키마 + event type 카탈로그를 명세한다. (B) 과거 데이터 변환 규칙, (C) AppSettings/MissionDefinitions, (D) HoldPray, (E) UserDashboard는 후속 섹션.

### A.1 Events 시트 컬럼 구조 (하이브리드)

| col | machine header | 타입 | 필수 | 설명 |
|---|---|---|---|---|
| A | `eventId` | string | ✓ | `Utilities.getUuid()` 생성 |
| B | `timestamp` | ISO 8601 string | ✓ | 발생 시각 (`new Date().toISOString()`) |
| C | `userId` | string | ✓ | 닉네임. 시스템 이벤트는 빈 문자열 가능 |
| D | `type` | string | ✓ | 점 표기 event type (예: `card.drawn`) |
| E | `refId` | string | optional | 이벤트가 가리키는 대상 ID. type에 따라 의미 다름 |
| F | `amount` | number | optional | 수량. 티켓 ±, 카드 수령 수량 등 |
| G | `weekKey` | string | optional | 주차 키 (`w1`~`w6`). 미션/티켓 관련 시 자주 채워짐 |
| H | `payload` | JSON string | optional | 위 컬럼으로 못 담는 부수 정보 |
| I | `source` | enum | ✓ | `web` / `admin` / `server` / `migration` |

**원칙.**
- `Events`는 **append-only**. 수정/삭제 금지. 정정은 새 이벤트로 (예: `trade.cancelled`).
- 자주 쓰는 4개 필드(`refId`, `amount`, `weekKey`, `userId`)는 별도 컬럼이라 시트 함수 통계 쉬움.
- 나머지 부수 정보는 `payload` JSON에. 새 type 추가 시 컬럼 안 늘림.
- Row 1은 운영진용 라벨 (`이벤트ID`, `발생시각`, `사용자`, `유형`, `참조ID`, `수량`, `주차`, `상세`, `출처`), Row 2가 machine header, Row 3부터 데이터.

### A.2 Event Type 카탈로그

#### 미션 도메인

| type | refId | amount | weekKey | payload 필드 | 발생 시점 |
|---|---|---|---|---|---|
| `mission.submitted` | — | — | ✓ | `items` (제출 항목 배열), `dateKey`, `score`, `indices` (선택), `weekTitle` (선택) | `submit` action |

#### 티켓 도메인

| type | refId | amount | weekKey | payload | 발생 시점 |
|---|---|---|---|---|---|
| `ticket.granted` | — | ✓ (+) | optional | `reason` (`week_complete` / `hp_correct` / `bbb_photo` / `bbb_m2` / `bbb_m3` / `admin`) | 주차 threshold 달성, H&P 정답, BBB 보상, 관리자 지급 |
| `ticket.consumed` | — | ✓ (−) | optional | — | `drawCard` 시 |

`amount`는 발급은 양수, 소모는 음수로 저장. 잔여 = `SUMIFS(amount, type IN [granted, consumed])`.

#### 카드 도메인

| type | refId | amount | weekKey | payload | 발생 시점 |
|---|---|---|---|---|---|
| `card.drawn` | cardId (`1`~`9`, `hidden`) | — | optional | `cardName`, `isNew` (boolean) | `drawCard` |
| `card.received` | cardId | ✓ (수령 수량) | — | — | `setCardReceivedQty` (admin) |

`card.received`는 실물 카드 수령. 기존 `CardReceived` 시트 데이터의 후계. amount가 누적 수량(현재 row의 절대값)인지 증분인지는 마이그레이션 규칙에서 결정 (현재는 절대값으로 갱신하는 패턴 → 매번 새 이벤트가 최신값).

#### 교환 도메인

| type | refId | amount | weekKey | payload | 발생 시점 |
|---|---|---|---|---|---|
| `trade.requested` | tradeId | — | — | `target`, `reqCardId`, `reqCardName`, `tgtCardId`, `tgtCardName` | `requestTrade` |
| `trade.accepted` | tradeId | — | — | — | `acceptTrade` |
| `trade.rejected` | tradeId | — | — | `reason` (optional) | `rejectTrade` |
| `trade.cancelled` | tradeId | — | — | — | `cancelTrade` |
| `trade.expired` | tradeId | — | — | — | `_expireOldTrades` (server) |
| `trade.prayed` | tradeId | — | — | `side` (`requester` / `target`) | `prayForTrade` |

교환 상태는 마지막 이벤트로 판단. 카드 보유 보정은 `trade.accepted` 시점에 양쪽 사용자에게 효과 (요청자: 줄 카드 −1, 받을 카드 +1 / 대상자: 반대).

#### H&P 도메인

| type | refId | amount | weekKey | payload | 발생 시점 |
|---|---|---|---|---|---|
| `hp.guessed` | hpRowId | — | ✓ | `cardIndex` (0/1/2), `guessedName`, `correct` (boolean) | `submitHoldPrayGuess` |

#### BBB 도메인

| type | refId | amount | weekKey | payload | 발생 시점 |
|---|---|---|---|---|---|
| `bbb.guessed` | — | — | — | `correct`, `guessedSecretBuddyId` (optional) | `guessBBBSecret` |
| `bbb.message_sent` | msgId | — | — | `toUserId` | `sendBBBMessage` |
| `bbb.photo_uploaded` | driveFileId | — | — | `missionType` (`m1` / `m2` / `m3_0` 등) | `uploadBBBPhoto` |
| `bbb.photo_deleted` | driveFileId | — | — | — | `deleteBBBPhoto` |

### A.3 refId 의미 매핑 (요약)

`refId`는 type마다 의미가 달라서 별도 명세 필수.

| type 군 | refId 의미 |
|---|---|
| `card.drawn`, `card.received` | cardId (`1`~`9` 또는 `hidden`) |
| `trade.*` | tradeId |
| `hp.guessed` | HoldPray 시트의 row ID |
| `bbb.message_sent` | msgId |
| `bbb.photo_uploaded`, `bbb.photo_deleted` | Drive file ID |
| 그 외 | 빈 문자열 |

### A.4 Source 카탈로그

| source | 의미 | 예시 |
|---|---|---|
| `web` | 사용자가 앱에서 직접 트리거 | 미션 제출, 카드 뽑기 |
| `admin` | 관리자 페이지 또는 admin GAS 함수 | `adminGrantHiddenCard`, 어드민 티켓 지급 |
| `server` | 서버 자동 발급 | 주차 threshold 달성 시 `ticket.granted`, `trade.expired` |
| `migration` | 1회성 마이그레이션 백필 | 과거 `raw_checkins` → `mission.submitted` 이벤트 복원 |

### A.5 Append 헬퍼 설계

```js
// 모든 mutation은 이 헬퍼만 사용. 직접 sheet.appendRow 금지.
function Events_append(type, userId, opts) {
  // opts = { refId, amount, weekKey, payload, source, timestamp? }
  const sheet = getSpreadsheet().getSheetByName(SHEET_NAMES.EVENTS);
  const lock = LockService.getScriptLock();
  lock.waitLock(5000);
  try {
    sheet.appendRow([
      Utilities.getUuid(),
      opts && opts.timestamp ? opts.timestamp : new Date().toISOString(),
      userId || '',
      type,
      opts && opts.refId != null ? String(opts.refId) : '',
      opts && opts.amount != null ? Number(opts.amount) : '',
      opts && opts.weekKey ? opts.weekKey : '',
      opts && opts.payload ? JSON.stringify(opts.payload) : '',
      opts && opts.source ? opts.source : 'server',
    ]);
  } finally {
    lock.releaseLock();
  }
}
```

- `LockService`로 동시 append 충돌 방지.
- `timestamp` 인자는 마이그레이션 백필 시 과거 시각 지정용. 일반 호출은 자동.

### A.6 자주 쓰는 조회 패턴

| 질문 | 시트 함수 |
|---|---|
| 홍길동 카드 뽑은 수 | `=COUNTIFS(C:C, "홍길동", D:D, "card.drawn")` |
| 홍길동 누적 티켓 발급 | `=SUMIFS(F:F, C:C, "홍길동", D:D, "ticket.granted")` |
| 홍길동 누적 티켓 소모 | `=-SUMIFS(F:F, C:C, "홍길동", D:D, "ticket.consumed")` |
| 홍길동 잔여 티켓 | granted − consumed |
| 홍길동 사랑카드(id=1) 보유 | `=COUNTIFS(C:C, "홍길동", D:D, "card.drawn", E:E, "1")` − trade로 나간 1번 + trade로 받은 1번 |
| 이번 주(w3) 미션 제출 인원 | `=COUNTIFS(D:D, "mission.submitted", G:G, "w3")` |
| 홍길동 마지막 활동 | `=MAXIFS(B:B, C:C, "홍길동")` |

코드 측에서는 `Events_readByUser(userId)` 같은 헬퍼로 캐시 후 forEach.

### A.7 운영진 시각 (Events 시트 보기)

Row 1 라벨이 한글이라 운영진이 펼쳐 보면.

```
| 이벤트ID | 발생시각          | 사용자  | 유형              | 참조ID | 수량 | 주차 | 상세                    | 출처   |
| uuid-1   | 2026-05-12 14:23 | 홍길동  | mission.submitted | -      | -    | w3   | {"items":["1","3"],...} | web    |
| uuid-2   | 2026-05-12 14:25 | 홍길동  | ticket.granted    | -      | 1    | w3   | {"reason":"week_..."}   | server |
| uuid-3   | 2026-05-12 14:30 | 홍길동  | ticket.consumed   | -      | -1   | -    | -                       | web    |
| uuid-4   | 2026-05-12 14:30 | 홍길동  | card.drawn        | 5      | -    | -    | {"cardName":"자비","isNew":true} | web |
```

한 사용자 행만 필터(`사용자` 컬럼 필터링) 하면 시계열로 무슨 일이 있었는지 한눈에 보임.

### A.8 결정된 사항 요약

| 항목 | 결정 |
|---|---|
| 컬럼 구조 | 하이브리드 (`refId`/`amount`/`weekKey` 별도 컬럼 + `payload` JSON) |
| 시트 이름 | `Events` (영문 key) |
| Row 1 | 운영진 한글 라벨 |
| Row 2 | machine header |
| dataStartRow | 3 |
| timestamp 포맷 | ISO 8601 문자열 |
| 동시성 | `LockService.getScriptLock()` 5초 |
| 변경 정책 | append-only. 정정은 새 이벤트로 |
| `amount` 부호 | granted = 양수, consumed = 음수. 합산으로 잔액 계산 |
| trade 카드 효과 | `trade.accepted` 발생 시점에 카드 카운트 보정 (projection 단계에서 처리) |

### A.9 미해결 — B 섹션에서 결정

(B.5 / B.6 / B.7 에서 결정. 아래 B 섹션 참조.)

---

## Phase 2.0 — (B) 과거 데이터 → Events 변환 규칙

> PROD의 현재 시트 데이터를 Events로 backfill 할 때의 변환 규칙. `source='migration'` 으로 마킹.
> Events에 들어가지 않는 도메인 시트(`BBBMessages`, `BBBPhotos`, `Notices`, `Inquiries`)는 그대로 복사. `Users` 도 그대로 유지.

### B.0 변환 원칙

| 원칙 | 내용 |
|---|---|
| **truth-source 분리** | Events는 *상태 변경 mutation* 만 담는다. 메시지 본문/사진 URL/공지 콘텐츠 같은 *원자료(document)* 는 도메인 시트에 그대로 둔다 |
| **`source='migration'`** | 모든 backfill 이벤트의 출처 |
| **timestamp 보존** | 원본 시각을 그대로 사용. 부족하면 추정 (B.2 참조) |
| **`eventId` 새로 부여** | UUID 새로 생성. 원본 id는 `refId` 또는 `payload`에 보존 |
| **idempotent** | 마이그레이션 함수는 여러 번 돌려도 같은 결과. 실행 전 `WHERE source='migration'` 으로 기존 backfill 이벤트 클리어 |

### B.1 시트별 변환 매트릭스

| 원본 시트 | 생성되는 Events | 도메인 시트 처리 |
|---|---|---|
| `raw_checkins` | `mission.submitted` + (조건부) `ticket.granted` | 원본 시트는 마이그레이션 후 제거 |
| `CardDraws` | `ticket.consumed` + `card.drawn` (쌍) | 원본 시트는 마이그레이션 후 제거 |
| `BonusDraws` | `ticket.granted` | 원본 시트는 마이그레이션 후 제거 |
| `Trades` | `trade.requested` + 종료 이벤트 + `trade.prayed` × N | 원본 시트는 마이그레이션 후 제거 |
| `HPGuesses` | `hp.guessed` | 원본 시트는 마이그레이션 후 제거 |
| `CardReceived` | `card.received` | 원본 시트는 마이그레이션 후 제거 |
| `Collection` | **변환 없음**. Events에서 projection으로 재계산 | 원본 시트는 헤더만 리셋 후 projection 결과로 채움 |
| `BBBMessages` | (없음) | 그대로 복사 — Events 적재 안 함 |
| `BBBPhotos` | (없음) | 그대로 복사 |
| `Notices`, `Inquiries` | (없음) | 그대로 복사 |
| `Users`, `BBB` | (없음) | 그대로 복사 |
| `HoldPray` | (없음) | 그대로 복사. 하드코딩 제거는 D 섹션에서 |
| `config` | (없음) | 분리 후 폐기. C 섹션 참조 |

**결정.** BBB 메시지/사진은 Events에 안 넣음. 이유는 derived aggregation에 영향 없는 raw content라서. 같은 이유로 Notices/Inquiries도 standalone 유지.

### B.2 `raw_checkins` → `mission.submitted` + `ticket.granted`

원본 컬럼 (Phase 0 조사 기준).

```
A:timestamp | B:weekTitle | C:items_json | D:userId | E:weekKey
F:dateKey | G:score | H:indices_json | I:weekCumScore | J:ticketEarned
```

각 row에 대해.

**1) `mission.submitted` 이벤트 1건.**

| 컬럼 | 값 |
|---|---|
| timestamp | `A` (그대로) |
| userId | `D` |
| type | `mission.submitted` |
| refId | (비움) |
| amount | (비움) |
| weekKey | `E` |
| payload | `{ "items": <C 파싱>, "dateKey": F, "score": G, "weekTitle": B, "indices": <H 파싱 or null> }` |
| source | `migration` |

**2) 조건부 `ticket.granted` 이벤트 1건.**

`J === true` 이면 (이 제출이 처음으로 threshold 넘긴 row 라면).

| 컬럼 | 값 |
|---|---|
| timestamp | `A + 1ms` (mission.submitted 직후) |
| userId | `D` |
| type | `ticket.granted` |
| amount | `1` |
| weekKey | `E` |
| payload | `{ "reason": "week_complete" }` |
| source | `migration` |

**`mission.submitted.score` 신뢰성.** 클라이언트가 계산한 값이지만 J(ticketEarned)는 서버가 계산한 값이라 ticket 발급 자체는 신뢰 가능. score는 통계 참고용으로만 payload에 보존.

### B.3 `CardDraws` → `ticket.consumed` + `card.drawn`

원본.

```
A:userId | B:weekKey | C:cardId | D:cardName | E:drawnAt | F:received(legacy)
```

각 row 당 이벤트 2건 생성.

**1) `ticket.consumed`.**

| 컬럼 | 값 |
|---|---|
| timestamp | `E` |
| userId | `A` |
| type | `ticket.consumed` |
| amount | `-1` |
| weekKey | `B` |
| payload | (비움) |
| source | `migration` |

**2) `card.drawn` (직후).**

| 컬럼 | 값 |
|---|---|
| timestamp | `E + 1ms` |
| userId | `A` |
| type | `card.drawn` |
| refId | `C` (cardId) |
| weekKey | `B` |
| payload | `{ "cardName": D, "isNew": null }` |
| source | `migration` |

**`isNew` 처리.** backfill에서는 `null`. 이유. 과거 데이터에서 isNew 복원하려면 사용자별 시계열 추적 필요한데, UI에서 backfill 결과를 다시 재생할 일 없음. 실시간 뽑기부터는 정확한 boolean.

**`F:received(legacy)` 처리.** 무시. 실물 수령은 `CardReceived` 가 truth source.

### B.4 `BonusDraws` → `ticket.granted`

원본.

```
A:userId | B:source | C:awardedAt
```

각 row 당 `ticket.granted` 1건.

**source → reason 매핑.**

| 원본 `B:source` 값 | `payload.reason` | `weekKey` (있으면 채움) |
|---|---|---|
| `hp_w3` | `hp_correct` | `w3` |
| `hp_w6` | `hp_correct` | `w6` |
| `bbb_photo` | `bbb_photo` | (비움) |
| `bbb_m2` | `bbb_m2` | (비움) |
| `bbb_m3` | `bbb_m3` | (비움) |
| 그 외 | 원본 문자열 그대로 | (비움) |

| 컬럼 | 값 |
|---|---|
| timestamp | `C` |
| userId | `A` |
| type | `ticket.granted` |
| amount | `1` |
| weekKey | 위 표 |
| payload | `{ "reason": <매핑>, "legacySource": B }` |
| source | `migration` |

**원본 source 문자열을 `legacySource`로 보존.** 매핑 표가 향후 누락된 케이스 발견 시 추적 가능.

### B.5 `Trades` → 최대 4개 이벤트

원본.

```
A:id | B:requester | C:requesterCardId | D:requesterCardName
E:target | F:targetCardId | G:targetCardName | H:status
I:createdAt | J:resolvedAt | K:requesterPrayed | L:targetPrayed
```

각 row 당 다음 이벤트들을 조건부 생성.

**1) `trade.requested` (항상).**

| 컬럼 | 값 |
|---|---|
| timestamp | `I` |
| userId | `B` (requester) |
| type | `trade.requested` |
| refId | `A` (tradeId) |
| payload | `{ "target": E, "reqCardId": C, "reqCardName": D, "tgtCardId": F, "tgtCardName": G }` |
| source | `migration` |

**2) 종료 이벤트 (`J:resolvedAt` 있고 `H:status !== 'pending'` 일 때).**

`H:status` 분기 (임의 문자열 케이스 포함).

| status 값 | event type | payload |
|---|---|---|
| `accepted` | `trade.accepted` | `{}` |
| `rejected` | `trade.rejected` | `{ "reason": null }` |
| `cancelled` | `trade.cancelled` | `{}` |
| `expired` | `trade.expired` | `{}` |
| **그 외 임의 문자열** | `trade.rejected` | `{ "reason": <status 원본 문자열>, "legacyStatus": true }` |

**임의 문자열 케이스 결정.** 과거 운영 중 status에 거절 사유 등이 텍스트로 저장된 경우가 있었음 → `trade.rejected.payload.reason` 으로 변환하고 `legacyStatus: true` 마킹. 정확한 분류는 운영 후 분석으로 가능.

| 컬럼 | 값 |
|---|---|
| timestamp | `J` |
| userId | `B` (이벤트 주체는 requester로 통일) |
| type | 위 표 |
| refId | `A` |
| payload | 위 표 |
| source | `migration` |

**3) `trade.prayed` (조건부).**

`K:requesterPrayed` 가 timestamp이면 1건.

| 컬럼 | 값 |
|---|---|
| timestamp | `K` |
| userId | `B` |
| type | `trade.prayed` |
| refId | `A` |
| payload | `{ "side": "requester" }` |
| source | `migration` |

`L:targetPrayed` 가 timestamp이면 1건.

| 컬럼 | 값 |
|---|---|
| timestamp | `L` |
| userId | `E` |
| type | `trade.prayed` |
| refId | `A` |
| payload | `{ "side": "target" }` |
| source | `migration` |

### B.6 `HPGuesses` → `hp.guessed`

원본.

```
A:nickname | B:weekKey | C:cardIndex | D:guessedName | E:answeredAt
```

각 row 당 1건.

| 컬럼 | 값 |
|---|---|
| timestamp | `E` |
| userId | `A` |
| type | `hp.guessed` |
| refId | (비움 — 원본에 hpRowId 없음) |
| weekKey | `B` |
| payload | `{ "cardIndex": C, "guessedName": D, "correct": null }` |
| source | `migration` |

**`correct` 처리.** backfill 시 `null`. 이유. HPGuesses에 정답 여부가 저장 안 돼 있고, 정답 매칭은 HoldPray + nickname 조인이 필요해 복잡. 실시간 hp.guessed부터는 boolean 채움. 과거 정답 통계는 `BonusDraws.hp_w*` 카운트로 대체.

**`refId` 처리.** backfill 시 비움. 실시간부터는 HoldPray 시트 row ID 채움 (HoldPray에 row ID 컬럼 필요 — D 섹션에서 결정).

### B.7 `CardReceived` → `card.received`

원본.

```
A:nickname | B:cardId | C:receivedQty | D:updatedAt
```

각 row 당 1건. **누적 절대값 단일 이벤트** 패턴 유지.

| 컬럼 | 값 |
|---|---|
| timestamp | `D` |
| userId | `A` |
| type | `card.received` |
| refId | `B` (cardId) |
| amount | `C` (절대값 수령 수량) |
| payload | (비움) |
| source | `migration` |

**증분 아니라 절대값 결정 이유.** 현재 코드 패턴이 `setCardReceivedQty(nickname, cardId, qty)` — qty를 절대값으로 갱신. 증분 이벤트로 분해하면 과거 변경 이력을 복원 불가능 (최종값만 시트에 남음). 따라서 단일 이벤트 = 마지막 절대값. projection 단계에서 `(userId, cardId)` 별 가장 최근 `card.received.amount` 를 사용.

### B.8 `Collection` 처리

**변환 없음.** Collection은 Events에서 도출되는 projection. 마이그레이션 후.

1. `Collection` 시트 헤더만 리셋 (또는 그대로).
2. 모든 사용자에 대해 `rebuildCollectionRow(userId)` 실행 → Events 합산 결과로 채움.
3. UserDashboard 검증 컬럼이 ✓ 떨어지는지 확인.

### B.9 정렬 및 후처리

**모든 이벤트 생성 후.**

1. Events 시트를 `timestamp` 오름차순으로 정렬.
2. `mission.submitted` 와 같은 timestamp에 발급된 `ticket.granted` 는 +1ms 보정 (B.2)으로 자연스럽게 mission 뒤로 정렬됨.
3. `ticket.consumed` 와 `card.drawn` 도 같은 방식으로 쌍 보존 (B.3).

### B.10 idempotent 마이그레이션 함수 구조

```js
function migrate_step5_absorbToEvents() {
  // 1. 기존 source='migration' 이벤트 전부 제거 (재실행 안전)
  clearMigrationEvents_();

  // 2. 각 시트 변환
  convertRawCheckins_();   // → mission.submitted + ticket.granted
  convertCardDraws_();      // → ticket.consumed + card.drawn
  convertBonusDraws_();     // → ticket.granted
  convertTrades_();         // → trade.requested + terminal + prayed
  convertHPGuesses_();      // → hp.guessed
  convertCardReceived_();   // → card.received

  // 3. 정렬
  sortEventsByTimestamp_();

  // 4. 검증
  return verifyMigration_();
}
```

`verifyMigration_()` 체크 항목.
- `mission.submitted` 이벤트 수 === 원본 `raw_checkins` 행 수
- `card.drawn` 이벤트 수 === 원본 `CardDraws` 행 수
- `ticket.granted` 이벤트의 (사용자별 합) >= `BonusDraws` + 주차 완료 횟수
- 모든 이벤트의 `userId` 가 `Users` 시트에 존재 (orphan 체크)
- 모든 `trade.*` 이벤트의 `refId` 가 원본 `Trades.id` 와 1:N 매칭

### B.11 결정 사항 요약 (A.9 해소)

| A.9 미해결 항목 | 결정 |
|---|---|
| `BonusDraws.source` 매핑 | B.4 표대로. 알려진 5개는 영문 reason 매핑, 그 외는 원본 문자열 유지 + `legacySource` 보존 |
| `Trades.status` 임의 문자열 | B.5. 알려진 4개(`accepted`/`rejected`/`cancelled`/`expired`)는 정상 매핑, 그 외는 `trade.rejected` + `legacyStatus: true` |
| `CardReceived` 누적 vs 증분 | B.7. 절대값 단일 이벤트 (현재 코드 패턴 유지) |
| `mission.submitted.score` 신뢰성 | B.2. 통계 참고용으로 payload에 보존. 티켓 발급은 `J:ticketEarned` (서버 계산값) 기준이므로 무관 |

### B.12 BBB 도메인 처리 (정정)

**A.2의 BBB 이벤트 타입 (`bbb.message_sent`, `bbb.photo_uploaded`, `bbb.photo_deleted`) 은 Events에 적재 안 함.**

이유.
- raw content (메시지 본문, 사진 URL) 라서 derived aggregation에 영향 없음.
- `BBBMessages`, `BBBPhotos` 시트가 이미 단일 source — 이중화 불필요.

**유지하는 BBB 이벤트.** `bbb.guessed` 만. 이건 "secret 추측 시도" 라는 상태 변경이라 audit 가치 있음.

**A.2 카탈로그 정정.**

```
~~bbb.message_sent~~  (제외)
~~bbb.photo_uploaded~~ (제외)
~~bbb.photo_deleted~~  (제외)
bbb.guessed  (유지)
```

`BBBMessages`, `BBBPhotos`, `Notices`, `Inquiries` 는 도메인 시트로 standalone 유지. 마이그레이션 시 그대로 복사만.

---

## Phase 2.0 — (C) AppSettings + MissionDefinitions 스키마

### C.0 분리 배경

현재 `config` 시트에는 성격이 전혀 다른 두 가지가 섞여 있다.

1. **단일값 설정** — `B1` 현재 주차, `B4` 앱 오픈일, `C1` BBB 메시지 토글 등. 어드민이 수시로 바꾸는 값.
2. **주차별 미션 정의** — 8행 단위 블록 × 6주차 = 48행. 기획 단계에서 세팅하고 거의 바꾸지 않는 값.

이 두 가지를 `AppSettings`(Key-Value 단순 설정)와 `MissionDefinitions`(1행 1미션 항목)으로 분리한다.  
분리 후에는 "BBB 메시지 입력창 켜려면?" → AppSettings에서 `bbb_message_open` 행만 찾으면 끝.  
"2주차 미션 항목 수정?" → MissionDefinitions에서 `weekKey=w2` 필터면 끝.

---

### C.1 AppSettings 스키마

**시트명 (machine key)**: `AppSettings`  
**운영진 라벨**: `앱 설정 (Key-Value)`  
**헤더 구조**: Row 1 = 운영진 라벨, Row 2 = machine header, Row 3+ = 데이터  

| 컬럼 (machine header) | 운영진 라벨 | 타입 | 설명 |
|---|---|---|---|
| `key` | 설정 키 | string | 고유 식별자. GAS 코드에서 직접 참조 |
| `value` | 값 | any | 설정값 (문자열로 저장, 코드에서 캐스팅) |
| `type` | 타입 힌트 | string | `number` / `string` / `boolean` / `date`. 운영진용 메모 |
| `note` | 설명 | string | 이 설정이 뭘 하는지 한 줄 설명 |

**초기 데이터 행:**

| key | value | type | note |
|---|---|---|---|
| `current_week` | `3` | `number` | 현재 진행 주차. 어드민 패널 "주차 변경"으로 수정 |
| `app_open_date` | `2026-05-10` | `date` | 앱 정식 오픈일. 이 날 이후 비운영진도 앱 진입 가능 |
| `bbb_message_open` | `FALSE` | `boolean` | BBB 익명 메시지 입력창 공개 여부. 어드민 토글 |
| `allow_test_draws` | `FALSE` | `boolean` | 뽑기권 없어도 뽑기 허용 (DEV Scripts Property 기반으로 대체 가능) |

> `TabSettings`, `BBBSettings` 시트에서 관리하는 값(탭 활성화, BBB 섹션 공개)은 현재 구조 유지.  
> 향후 이 시트들도 AppSettings로 통합 가능하지만 이번 마이그레이션 범위에서 제외.

**GAS 헬퍼 (읽기/쓰기):**

```js
/**
 * AppSettings 시트에서 key에 해당하는 value를 반환한다.
 * 없으면 defaultValue를 반환.
 */
function getAppSetting_(key, defaultValue) {
  const sheet = getSpreadsheet().getSheetByName(SHEET_NAMES.APP_SETTINGS);
  if (!sheet) return defaultValue;
  const rows = sheet.getDataRange().getValues().slice(2); // header 2행 건너뜀
  const row = rows.find(r => r[0] === key);
  return row ? row[1] : defaultValue;
}

/**
 * AppSettings 시트의 key 행을 value로 업데이트한다.
 * 해당 key가 없으면 새 행을 추가한다 (upsert).
 */
function setAppSetting_(key, value) {
  const sheet = getSpreadsheet().getSheetByName(SHEET_NAMES.APP_SETTINGS);
  const all = sheet.getDataRange().getValues();
  // Row 1, 2는 헤더 → idx 2부터 탐색
  for (let i = 2; i < all.length; i++) {
    if (all[i][0] === key) {
      sheet.getRange(i + 1, 2).setValue(value); // +1: 1-based
      return;
    }
  }
  sheet.appendRow([key, value, '', '']);
}
```

**이전 코드 치환 대응:**

| 기존 | 신규 |
|---|---|
| `getConfig().B1` → 현재 주차 | `getAppSetting_('current_week', 1)` |
| `getConfig().B4` → 앱 오픈일 | `getAppSetting_('app_open_date', '')` |
| `BBBSettings` 시트 `bbb_message_open` 열 | `getAppSetting_('bbb_message_open', false)` (단계적 전환) |

---

### C.2 MissionDefinitions 스키마

**시트명 (machine key)**: `MissionDefinitions`  
**운영진 라벨**: `주차별 미션 항목 정의`  
**헤더 구조**: Row 1 = 운영진 라벨, Row 2 = machine header, Row 3+ = 데이터  
**정렬 기준**: `weekOrder` ASC → `itemNo` ASC

| 컬럼 (machine header) | 운영진 라벨 | 타입 | 설명 |
|---|---|---|---|
| `weekKey` | 주차 키 | string | `w1`~`w6`. raw_checkins의 weekKey와 동일 |
| `weekOrder` | 주차 순서 | number | 1~6. 정렬용 |
| `weekTitle` | 주차 제목 | string | 예. `1주차: 나는 누구인가?` |
| `weekStartDate` | 주차 시작일 | date | `YYYY-MM-DD`. 캘린더 표시용 |
| `weekEndDate` | 주차 종료일 | date | `YYYY-MM-DD`. 캘린더 표시용 |
| `drawThreshold` | 뽑기권 발급 기준 점수 | number | 이 점수 이상 달성 시 주차 완료 → 뽑기권 1장 |
| `itemNo` | 항목 번호 | number | 해당 주차 내 순서. 1~6 |
| `itemText` | 항목 내용 | string | 미션 항목 텍스트 |
| `scoreWeight` | 배점 | number | 제출 시 획득 점수 (현재 모두 1) |
| `category` | 분류 | string | `bible` / `pray` / `share` / `act` 등 (미래 확장용) |
| `enabled` | 활성화 | boolean | `FALSE`면 해당 항목 앱에서 숨김 |

**예시 데이터 (w1 기준):**

| weekKey | weekOrder | weekTitle | weekStartDate | weekEndDate | drawThreshold | itemNo | itemText | scoreWeight | category | enabled |
|---|---|---|---|---|---|---|---|---|---|---|
| w1 | 1 | 1주차: 나는 누구인가? | 2026-05-10 | 2026-05-16 | 6 | 1 | 말씀 묵상 (갈라디아서 5:22-23) | 1 | bible | TRUE |
| w1 | 1 | 1주차: 나는 누구인가? | 2026-05-10 | 2026-05-16 | 6 | 2 | 기도 (성령의 열매를 위한 기도) | 1 | pray | TRUE |
| … | … | … | … | … | … | … | … | … | … | … |

> `weekTitle`, `weekStartDate`, `weekEndDate`, `drawThreshold`는 주차 내 모든 항목 행에 반복된다 (denormalized).  
> 이렇게 하면 GAS 단일 FILTER 쿼리로 주차 메타 + 항목 전체를 한 번에 읽을 수 있다.  
> 정규화(별도 WeekMeta 테이블)의 이득이 없는 규모(6주 × 6항목 = 36행)이므로 denormalized로 채택.

**GAS 헬퍼:**

```js
/**
 * weekKey에 해당하는 미션 항목 배열을 반환한다.
 * 반환값: [{ weekKey, weekTitle, weekStartDate, weekEndDate, drawThreshold,
 *            itemNo, itemText, scoreWeight, category, enabled }, ...]
 */
function getMissionItems_(weekKey) {
  const sheet = getSpreadsheet().getSheetByName(SHEET_NAMES.MISSION_DEFINITIONS);
  if (!sheet) return [];
  const all = sheet.getDataRange().getValues();
  const headers = all[1]; // Row 2 = machine header (0-indexed: index 1)
  const col = Object.fromEntries(headers.map((h, i) => [h, i]));
  return all.slice(2) // Row 3부터 데이터
    .filter(r => r[col.weekKey] === weekKey && r[col.enabled] !== false && r[col.enabled] !== 'FALSE')
    .map(r => ({
      weekKey:        r[col.weekKey],
      weekTitle:      r[col.weekTitle],
      weekStartDate:  r[col.weekStartDate],
      weekEndDate:    r[col.weekEndDate],
      drawThreshold:  Number(r[col.drawThreshold]),
      itemNo:         Number(r[col.itemNo]),
      itemText:       r[col.itemText],
      scoreWeight:    Number(r[col.scoreWeight]),
      category:       r[col.category],
    }))
    .sort((a, b) => a.itemNo - b.itemNo);
}

/**
 * 전체 주차 메타 정보 배열을 반환한다 (항목 중복 제거).
 * 반환값: [{ weekKey, weekOrder, weekTitle, weekStartDate, weekEndDate, drawThreshold }, ...]
 */
function getAllWeekMeta_() {
  const sheet = getSpreadsheet().getSheetByName(SHEET_NAMES.MISSION_DEFINITIONS);
  if (!sheet) return [];
  const all = sheet.getDataRange().getValues();
  const headers = all[1];
  const col = Object.fromEntries(headers.map((h, i) => [h, i]));
  const seen = new Set();
  const result = [];
  for (const r of all.slice(2)) {
    const wk = r[col.weekKey];
    if (!seen.has(wk)) {
      seen.add(wk);
      result.push({
        weekKey:       wk,
        weekOrder:     Number(r[col.weekOrder]),
        weekTitle:     r[col.weekTitle],
        weekStartDate: r[col.weekStartDate],
        weekEndDate:   r[col.weekEndDate],
        drawThreshold: Number(r[col.drawThreshold]),
      });
    }
  }
  return result.sort((a, b) => a.weekOrder - b.weekOrder);
}
```

---

### C.3 migrate_step4_splitConfig() 구조

```js
/**
 * config 시트의 단일값 설정과 8행 단위 미션 블록을
 * AppSettings + MissionDefinitions 두 시트로 분리한다.
 * idempotent: 시트가 이미 존재하면 데이터만 갱신.
 */
function migrate_step4_splitConfig() {
  const ss = getSpreadsheet();
  const config = ss.getSheetByName(SHEET_NAMES.CONFIG); // 기존 config 시트

  // ── AppSettings 시트 ──────────────────────────────────
  let appSettingsSheet = ss.getSheetByName(SHEET_NAMES.APP_SETTINGS);
  if (!appSettingsSheet) appSettingsSheet = ss.insertSheet(SHEET_NAMES.APP_SETTINGS);
  appSettingsSheet.clearContents();
  // Row 1: 운영진 라벨
  appSettingsSheet.getRange(1, 1, 1, 4).setValues([['앱 설정 (Key-Value)', '', '', '']]);
  // Row 2: machine header
  appSettingsSheet.getRange(2, 1, 1, 4).setValues([['key', 'value', 'type', 'note']]);
  // Row 3+: 데이터 (config에서 읽어옴)
  const currentWeek  = config.getRange('B1').getValue();
  const appOpenDate  = config.getRange('B4').getValue();
  const rows = [
    ['current_week',     currentWeek,  'number',  '현재 진행 주차. 어드민 패널에서 수정.'],
    ['app_open_date',    appOpenDate,  'date',    '앱 정식 오픈일. YYYY-MM-DD.'],
    ['bbb_message_open', 'FALSE',      'boolean', 'BBB 익명 메시지 입력창 공개 여부.'],
    ['allow_test_draws', 'FALSE',      'boolean', '테스트용 뽑기권 bypass (PROD은 항상 FALSE).'],
  ];
  appSettingsSheet.getRange(3, 1, rows.length, 4).setValues(rows);

  // ── MissionDefinitions 시트 ───────────────────────────
  let mdefSheet = ss.getSheetByName(SHEET_NAMES.MISSION_DEFINITIONS);
  if (!mdefSheet) mdefSheet = ss.insertSheet(SHEET_NAMES.MISSION_DEFINITIONS);
  mdefSheet.clearContents();
  // Row 1: 운영진 라벨
  const mdefHeaders = ['weekKey','weekOrder','weekTitle','weekStartDate','weekEndDate',
                       'drawThreshold','itemNo','itemText','scoreWeight','category','enabled'];
  const mdefLabels  = ['주차 키','주차 순서','주차 제목','시작일','종료일',
                       '뽑기권 기준점수','항목 번호','항목 내용','배점','분류','활성화'];
  mdefSheet.getRange(1, 1, 1, mdefHeaders.length).setValues([mdefLabels]);
  // Row 2: machine header
  mdefSheet.getRange(2, 1, 1, mdefHeaders.length).setValues([mdefHeaders]);
  // Row 3+: config 8행 블록 파싱 (기존 getMissionConfig() 로직 재활용)
  const allMdef = [];
  const NUM_WEEKS = 6;
  const ITEMS_PER_WEEK = 6;
  // config 시트 기존 구조: startRow = (week-1)*8 + 5 (1-based)
  // 블록 레이아웃 추정: row1=weekTitle, row2=startDate, row3=endDate, row4=drawThreshold,
  //                    row5~row8(혹은 +5~+10)=미션항목 — 실제 구조는 GAS getMissionConfig 참조
  const configVals = config.getDataRange().getValues();
  for (let w = 1; w <= NUM_WEEKS; w++) {
    const base = (w - 1) * 8;          // 0-based row index 내 블록 시작
    const weekKey        = `w${w}`;
    const weekTitle      = configVals[base]     ? configVals[base][1]     : '';
    const weekStartDate  = configVals[base + 1] ? configVals[base + 1][1] : '';
    const weekEndDate    = configVals[base + 2] ? configVals[base + 2][1] : '';
    const drawThreshold  = configVals[base + 3] ? configVals[base + 3][1] : 6;
    for (let i = 0; i < ITEMS_PER_WEEK; i++) {
      const itemRow = configVals[base + 4 + i];
      if (!itemRow) continue;
      allMdef.push([
        weekKey, w, weekTitle, weekStartDate, weekEndDate, drawThreshold,
        i + 1,             // itemNo
        itemRow[1] || '',  // itemText (B열)
        itemRow[2] || 1,   // scoreWeight (C열) — 없으면 1
        itemRow[3] || '',  // category (D열)
        true,              // enabled
      ]);
    }
  }
  if (allMdef.length > 0) {
    mdefSheet.getRange(3, 1, allMdef.length, mdefHeaders.length).setValues(allMdef);
  }

  Logger.log(`migrate_step4_splitConfig 완료. AppSettings ${rows.length}행, MissionDefinitions ${allMdef.length}행.`);
}
```

> **주의.** config 시트의 실제 블록 레이아웃(행 오프셋)은 GAS `getMissionConfig` 함수를 기준으로 파싱 오프셋을 조정해야 한다.  
> migrate_step4를 실행하기 전에 DEV 시트에서 `Logger.log(JSON.stringify(allMdef.slice(0, 6)))` 으로 파싱 결과를 먼저 검증한다.

---

### C.4 SHEET_NAMES + SCHEMA 상수 추가 항목

```js
// SHEET_NAMES에 추가
const SHEET_NAMES = {
  // ... 기존 항목들 ...
  APP_SETTINGS:        'AppSettings',
  MISSION_DEFINITIONS: 'MissionDefinitions',
};

// SCHEMA에 추가 (헤더 참조용)
const SCHEMA = {
  // ... 기존 항목들 ...
  APP_SETTINGS: {
    operatorLabel: '앱 설정 (Key-Value)',
    headerRow: 2,
    dataStartRow: 3,
    columns: { key: 0, value: 1, type: 2, note: 3 },
  },
  MISSION_DEFINITIONS: {
    operatorLabel: '주차별 미션 항목 정의',
    headerRow: 2,
    dataStartRow: 3,
    columns: {
      weekKey: 0, weekOrder: 1, weekTitle: 2, weekStartDate: 3, weekEndDate: 4,
      drawThreshold: 5, itemNo: 6, itemText: 7, scoreWeight: 8, category: 9, enabled: 10,
    },
  },
};
```

---

## Phase 2.0 — (D) HoldPray 시트 정규화

### D.0 현재 상태와 문제

**현재 상태.**

| 사항 | 내용 |
|---|---|
| 헤더 형식 | `이름(n)`, `교구(p)`, `기도제목(c)`, `익명(a)`, `닉네임(nick)` — 한글+약어 혼합 |
| 헤더 행 수 | Row 1만 존재 (운영진 라벨/machine header 미분리) |
| 행 ID | 없음. 배열 인덱스로만 참조 |
| 원천 데이터 | `HOLD_PRAY_ENTRIES` 하드코딩 상수가 코드에 여전히 존재. `migrateHoldPrayToSheet()`로 시트에 올렸지만 fallback으로 상수가 남아 있음 |
| 반환 형식 | `getYouthHpEntries()`가 `{ n, p, c, a, nick }` 구 약어 형식으로 반환 |

**문제.**
- 운영진이 시트 컬럼 의미를 약어로 읽어야 함.
- row ID가 없어서 HPGuesses·Events에서 "어떤 기도제목 카드를 맞혔는가" 를 참조하기 어려움.
- `HOLD_PRAY_ENTRIES` 상수가 GAS 소스에 117명 분량 JSON 블록으로 남아 있어 코드 가독성 저하.
- `getYouthHpEntries()`의 반환 형식이 구 약어(`n/p/c/a/nick`)를 유지해야 하므로 컬럼명 변경 시 callers도 같이 수정해야 함.

---

### D.1 목표 HoldPray 스키마

**시트명 (machine key)**: `HoldPray` (기존 유지)  
**운영진 라벨**: `H&P 기도제목`  
**헤더 구조**: Row 1 = 운영진 라벨, Row 2 = machine header, Row 3+ = 데이터  

| 컬럼 (machine header) | 운영진 라벨 | 타입 | 설명 |
|---|---|---|---|
| `entryId` | 항목 ID | string | `hp-001` 형식. HPGuesses/Events에서 stable reference용 |
| `name` | 이름 | string | 정답 이름. 익명이면 `무기명` |
| `parish` | 교구 | string | 교구명. `목양*`, `초등*` 교구는 필터 대상 |
| `content` | 기도제목 | string | 기도제목 본문 |
| `anonymous` | 익명 여부 | boolean | `TRUE`면 이름 숨김. 이름이 비어 있거나 `무기명`이면 자동 TRUE 처리 |
| `nickname` | 닉네임 | string | 해당 인물의 앱 계정 닉네임. 없으면 빈 문자열 |

> `entryId` 생성 규칙. `hp-` + 0-padded 3자리 순번 (예. `hp-001`, `hp-117`). 행 추가 시 `hp-118`처럼 이어감.

---

### D.2 SCHEMA 상수 업데이트

```js
// 기존 SCHEMA.HOLD_PRAY (headerRow=1, 컬럼 한글 key)
HOLD_PRAY: Object.freeze({
  sheetName: SHEET_NAMES.HOLD_PRAY,
  headerRow: 1,
  dataStartRow: 2,
  columns: Object.freeze({
    name: '이름(n)',
    parish: '교구(p)',
    content: '기도제목(c)',
    anonymous: '익명(a)',
    nickname: '닉네임(nick)',
  }),
}),

// 목표 SCHEMA.HOLD_PRAY (headerRow=2, 영문 machine key + entryId 추가)
HOLD_PRAY: Object.freeze({
  sheetName: SHEET_NAMES.HOLD_PRAY,
  headerRow: 2,       // Row 1 = 운영진 라벨, Row 2 = machine header
  dataStartRow: 3,
  columns: Object.freeze({
    entryId:   'entryId',
    name:      'name',
    parish:    'parish',
    content:   'content',
    anonymous: 'anonymous',
    nickname:  'nickname',
  }),
}),
```

> `getHoldPrayColumns_` / `getHoldPrayRows_` 함수는 SCHEMA.HOLD_PRAY 변경만으로 자동 적응됨.  
> 단, `getYouthHpEntries()`의 반환 형식(`n/p/c/a/nick`)은 callers가 많아 Phase 2C에서 한꺼번에 수정.  
> migrate_step6 실행 전까지는 SCHEMA.HOLD_PRAY를 기존 그대로 유지. 마이그레이션 후 교체.

---

### D.3 migrate_step6_externalizeHoldPray() 구조

```js
/**
 * HoldPray 시트를 목표 스키마로 변환한다.
 * 1. entryId 컬럼 삽입 (맨 앞에)
 * 2. Row 1(현재 헤더) 앞에 운영진 라벨 행 삽입
 * 3. 기존 헤더 행을 machine header로 교체
 * 4. 데이터 행에 entryId 채움 (hp-001~)
 * 5. HOLD_PRAY_ENTRIES fallback은 별도 코드 수정으로 제거
 * idempotent: entryId 컬럼이 이미 존재하면 skip.
 */
function migrate_step6_externalizeHoldPray() {
  const ss = getSpreadsheet();
  const sheet = ss.getSheetByName(SHEET_NAMES.HOLD_PRAY);
  if (!sheet) throw new Error('HoldPray 시트 없음');

  const firstRow = sheet.getRange(1, 1, 2, 6).getValues();
  // idempotent 체크: Row 2가 이미 machine header이면 skip
  if (firstRow[1] && firstRow[1][0] === 'entryId') {
    Logger.log('migrate_step6: 이미 완료된 상태. skip.');
    return;
  }

  // Step 1: 맨 앞 컬럼에 entryId 삽입
  sheet.insertColumnBefore(1);

  // Step 2: 맨 위에 운영진 라벨 행 삽입
  sheet.insertRowBefore(1);
  const OPERATOR_LABELS = ['항목 ID', '이름', '교구', '기도제목', '익명 여부', '닉네임'];
  sheet.getRange(1, 1, 1, OPERATOR_LABELS.length).setValues([OPERATOR_LABELS]);

  // Step 3: Row 2 (원래 헤더였던 행)를 machine header로 교체
  const MACHINE_HEADERS = ['entryId', 'name', 'parish', 'content', 'anonymous', 'nickname'];
  sheet.getRange(2, 1, 1, MACHINE_HEADERS.length).setValues([MACHINE_HEADERS]);

  // Step 4: 데이터 행 entryId 채움 (Row 3부터)
  const dataStart = 3;
  const lastRow = sheet.getLastRow();
  const count = lastRow - dataStart + 1;
  if (count > 0) {
    const ids = Array.from({ length: count }, (_, i) =>
      ['hp-' + String(i + 1).padStart(3, '0')]
    );
    sheet.getRange(dataStart, 1, count, 1).setValues(ids);
  }

  sheet.setFrozenRows(2);
  Logger.log('migrate_step6 완료. ' + count + '개 항목에 entryId 부여.');
}
```

---

### D.4 getYouthHpEntries() 반환 형식 전환 계획

현재 `getYouthHpEntries()`는 `{ n, p, c, a, nick }` 약어 형식을 반환한다.  
이를 사용하는 callers는 `getHoldPray()`, `submitHoldPrayGuess()`, `adminWriteBBBRows()` 등 여러 곳이다.

migrate_step6 이후 **Phase 2C** 에서 한꺼번에 전환한다.

| 단계 | 내용 |
|---|---|
| migrate_step6 실행 전 | SCHEMA.HOLD_PRAY 기존 유지. `getYouthHpEntries()` → `{ n, p, c, a, nick }` |
| migrate_step6 실행 후 | SCHEMA.HOLD_PRAY를 목표 schema로 교체. `getYouthHpEntries()` → `{ entryId, name, parish, content, anonymous, nickname }`. callers 일괄 수정 |
| HOLD_PRAY_ENTRIES 상수 | migrate_step6 완료 + fallback 분기 제거 후 코드에서 삭제. GAS 파일 ~20KB 감소 |

---

### D.5 HPGuesses 스키마는 현재 유지

HPGuesses는 `cardIndex`(0~2)로 어떤 기도제목 카드를 맞혔는지 기록한다.  
`entryId` 직접 참조로 전환하면 Rendezvous hashing 로직 전체를 바꿔야 한다.  
**이번 마이그레이션 범위에서 제외.** HPGuesses는 현행 schema 유지.

---

## Phase 2.0 — (E) UserDashboard 컬럼 명세 + 시트 함수

### E.0 목적과 제약

**목적.**
- 운영진이 "이 사람 티켓 몇 개야?" "카드 몇 개 갖고 있어?" 를 GAS 없이 시트에서 바로 확인.
- Events(단일 truth source) 기반으로 계산한 값과 Collection(캐시)이 일치하는지 검증하는 double-entry ledger 역할.
- Phase 2D(Collection projection 전환) 이후에는 모든 검증 컬럼이 ✓여야 한다.

**제약.**
- **운영 데이터는 GAS가 이 시트에 쓰지 않는다.** `setupUserDashboard()`는 헤더/수식/서식만 생성하고, 값은 시트 함수가 계산.
- `Events` 시트가 DEV big-bang 백필 또는 PROD dual-write로 채워진 상태에서 동작하는 설계.
- DEV big-bang 마이그레이션에서는 처음부터 Events가 채워지므로 즉시 검증 가능.

---

### E.1 전제 — Events 컬럼 레이아웃 (열 참조 기준)

Events 시트는 Row 1 = 운영진 라벨, Row 2 = machine header, Row 3+ = 데이터.

| 열 | machine header | 주요 사용 값 |
|---|---|---|
| A | `eventId` | |
| B | `timestamp` | ISO 8601 문자열 (문자열 정렬 기준) |
| C | `userId` | 닉네임 (COUNTIFS/SUMIFS 기준) |
| D | `type` | `mission.submitted`, `ticket.granted`, `ticket.consumed`, `card.drawn`, … |
| E | `refId` | card.drawn → 카드 ID (문자열 "1"~"10") |
| F | `amount` | 양수. granted=지급량, consumed=차감량 (항상 양수로 저장) |
| G | `weekKey` | `w1`~`w6` |
| H | `payload` | JSON (시트 함수로 직접 파싱 불가 — 검증용으로는 사용 안 함) |
| I | `source` | |

> `amount` 부호 정책. ticket.granted와 ticket.consumed 모두 **양수** 저장.  
> 남은 뽑기권 = SUMIFS(granted) − SUMIFS(consumed).  
> 음수 저장 방식은 SUMIFS 직관성이 떨어져서 채택하지 않음.

Collection 시트는 Row 1 = 헤더, Row 2+ = 데이터.

| 열 | 의미 |
|---|---|
| A | userId |
| B | 누적뽑기권 (ticketsEarned) |
| C | 실제뽑은개수 (cardsDrawn) |
| D | 남은개수 (ticketsRemaining) |
| E~M | 카드 1~9번 보유 수 (사랑~절제) |
| N | 총카드수 |
| O | 히든 카드 보유 수 |

---

### E.2 UserDashboard 시트 구조

**시트명**: `UserDashboard`  
**운영진 라벨**: `유저 현황 대시보드 (읽기 전용. 수정 금지.)`  
**헤더**: Row 1 = 운영진 라벨, Row 2 = machine header, Row 3+ = 데이터 (유저 1명 = 1행)  
**정렬**: 닉네임 가나다순 (자동 정렬 없음 — Users 시트 순서 그대로)

---

### E.3 컬럼 명세 + 시트 함수

> 함수 예시는 **3행(첫 번째 데이터 행)**을 기준으로 작성.  
> 실제 적용 시 data range는 `Events!C3:C` (헤더 2행 건너뜀) 로 사용.  
> 빈 행 방지를 위해 모든 함수를 `IFERROR(…, "")` 로 감쌈.

#### 그룹 1 — 유저 식별

| 컬럼 | machine header | 운영진 라벨 | 시트 함수 (Row 3) |
|---|---|---|---|
| A | `userId` | 닉네임 | `=IF(Users!A2="","",Users!A2)` |
| B | `name` | 이름 | `=IFERROR(VLOOKUP(A3,Users!A:C,3,0),"")` |
| C | `parish` | 교구 | `=IFERROR(VLOOKUP(A3,Users!A:D,4,0),"")` |

> Users 시트 구조: A=nickname, B=password, C=name, D=parish.  
> UserDashboard는 Row 1~2를 쓰므로 첫 데이터 행 A3은 Users의 첫 데이터 행 A2를 참조.

#### 그룹 2 — 미션

| 컬럼 | machine header | 운영진 라벨 | 시트 함수 (Row 3) |
|---|---|---|---|
| D | `missionCount` | 미션 제출 수 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"mission.submitted")` |

#### 그룹 3 — 뽑기권

| 컬럼 | machine header | 운영진 라벨 | 시트 함수 (Row 3) |
|---|---|---|---|
| E | `ticketsEarned` | 누적 획득 뽑기권 | `=SUMIFS(Events!F3:F,Events!C3:C,A3,Events!D3:D,"ticket.granted")` |
| F | `ticketsConsumed` | 사용 뽑기권 | `=SUMIFS(Events!F3:F,Events!C3:C,A3,Events!D3:D,"ticket.consumed")` |
| G | `ticketsRemaining` | 남은 뽑기권 | `=E3-F3` |

#### 그룹 4 — 카드

| 컬럼 | machine header | 운영진 라벨 | 시트 함수 (Row 3) |
|---|---|---|---|
| H | `cardsDrawn` | 뽑은 총 횟수 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"card.drawn")` |
| I | `card_1` | 사랑 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"card.drawn",Events!E3:E,"1")` |
| J | `card_2` | 희락 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"card.drawn",Events!E3:E,"2")` |
| K | `card_3` | 화평 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"card.drawn",Events!E3:E,"3")` |
| L | `card_4` | 오래참음 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"card.drawn",Events!E3:E,"4")` |
| M | `card_5` | 자비 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"card.drawn",Events!E3:E,"5")` |
| N | `card_6` | 양선 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"card.drawn",Events!E3:E,"6")` |
| O | `card_7` | 충성 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"card.drawn",Events!E3:E,"7")` |
| P | `card_8` | 온유 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"card.drawn",Events!E3:E,"8")` |
| Q | `card_9` | 절제 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"card.drawn",Events!E3:E,"9")` |
| R | `card_10` | 히든 | `=COUNTIFS(Events!C3:C,A3,Events!D3:D,"card.drawn",Events!E3:E,"10")` |
| S | `totalCards` | 총 카드 수 | `=SUM(I3:R3)` |

> `card.received` 이벤트(현장 카드 수령, 절대량 저장)는 별도 집계 필요 시 추가.  
> 이번 설계에서는 `card.drawn` 기준 (온라인 뽑기 횟수)만 집계. 현장 카드는 CardReceived 시트 그대로 참조.

#### 그룹 5 — 교환

| 컬럼 | machine header | 운영진 라벨 | 시트 함수 (Row 3) |
|---|---|---|---|
| T | `activeTrades` | 진행중 교환 건수 | `=COUNTIFS(Trades!B2:B,A3,Trades!H2:H,"pending")+COUNTIFS(Trades!E2:E,A3,Trades!H2:H,"pending")` |

> Trades 시트는 Row 1 = 헤더, Row 2+ = 데이터. B = requester, E = target, H = status.

#### 그룹 6 — 활동

| 컬럼 | machine header | 운영진 라벨 | 시트 함수 (Row 3) |
|---|---|---|---|
| U | `lastActivity` | 마지막 활동 | `=IFERROR(INDEX(SORT(FILTER(Events!B3:B5000,Events!C3:C5000=A3),1,FALSE),1),"")` |

> `Events!B` timestamp는 ISO 8601 문자열이라 내림차순 문자열 정렬의 첫 값을 최신 활동으로 사용.

#### 그룹 7 — Collection 검증 (비교용)

| 컬럼 | machine header | 운영진 라벨 | 시트 함수 (Row 3) |
|---|---|---|---|
| V | `col_ticketsRemaining` | [컬렉션] 남은 뽑기권 | `=IFERROR(VLOOKUP(A3,Collection!A:D,4,0),"")` |
| W | `col_totalCards` | [컬렉션] 총 카드 수 | `=IFERROR(VLOOKUP(A3,Collection!A:N,14,0),"")` |
| X | `col_cardsDrawn` | [컬렉션] 뽑은 횟수 | `=IFERROR(VLOOKUP(A3,Collection!A:C,3,0),"")` |

#### 그룹 8 — 검증 결과

| 컬럼 | machine header | 운영진 라벨 | 시트 함수 (Row 3) |
|---|---|---|---|
| Y | `valid_tickets` | 뽑기권 일치 ✓/❌ | `=IF(A3="","",IF(G3=V3,"✓","❌"))` |
| Z | `valid_cards` | 카드 수 일치 ✓/❌ | `=IF(A3="","",IF(S3=W3,"✓","❌"))` |
| AA | `valid_drawn` | 뽑기 횟수 일치 ✓/❌ | `=IF(A3="","",IF(H3=X3,"✓","❌"))` |

---

### E.4 조건부 서식

| 대상 범위 | 조건 | 서식 |
|---|---|---|
| `Y3:AA` 전체 | 셀 값 = `❌` | 배경색 빨강 (#FF4444), 텍스트 흰색 |
| `A3:AA` 전체 행 | `$Y3="❌"` OR `$Z3="❌"` OR `$AA3="❌"` | 행 배경 연한 빨강 (#FFE0E0) |

설정 방법 (수동).
1. Google Sheets → 서식 → 조건부 서식
2. 범위 `A3:AA` 적용
3. 맞춤 수식 → `=OR($Y3="❌",$Z3="❌",$AA3="❌")`
4. 배경색 → 연한 빨강

---

### E.5 A열 자동 확장 (Users 시트 동기화)

A3부터 시작하는 userId 열을 Users 시트와 자동 동기화하려면 두 가지 방식 중 선택.

**방식 1. 단순 참조 (권장)**
- A3 = `=Users!A2`, A4 = `=Users!A3` … 아래로 드래그.
- Users에 행이 추가될 때마다 UserDashboard도 행을 같이 늘려야 함.
- 구현이 단순하고 실수 여지가 적어서 250명 규모에서는 이 방식으로 충분.

**방식 2. ARRAYFORMULA 자동 확장**
```
A3 셀: =ARRAYFORMULA(IF(Users!A2:A="","",Users!A2:A))
```
- Users에 행이 추가되면 A열이 자동 확장됨.
- 단, 나머지 컬럼(B~AA)도 전부 ARRAYFORMULA로 바꿔야 하거나, A열이 확장되어도 B~AA가 따라오지 않는 문제 발생.
- **결론. 방식 1(단순 참조)로 시작하고, 운영 중 불편하면 방식 2로 전환.**

---

### E.6 성능 고려사항

| 항목 | 내용 |
|---|---|
| Events 행 수 | 사용자 250명 × 주차 6 × 이벤트 수 ≈ 최대 수천 행. Google Sheets COUNTIFS/SUMIFS는 이 규모에서 충분히 빠름 |
| 컬럼 수 | A~AA = 27컬럼 × 250행 = 6,750셀. 문제 없음 |
| 새로고침 지연 | 시트 열 때마다 전체 재계산. Events 행이 수만 건 초과하면 느려질 수 있음 — Phase 2E batchGet 최적화와 함께 재평가 |
| 수동 범위 지정 (`C3:C`) | 전체 열 (`C:C`) 대신 데이터 범위만 지정해야 계산 속도가 빠름. Events 최대 행을 여유 있게(`C3:C5000` 등)로 고정하는 방법도 있음 |

---

### E.7 Phase 2B 실제 적용 순서

```
1. Events 시트 생성 (Phase 2A에서 완료)
2. UserDashboard 시트 생성
3. Row 1: 운영진 라벨 입력
4. Row 2: machine header 입력 (A~AA)
5. A3~A252 (250명 기준): =Users!A2 ~ =Users!A251
6. B3~C252: VLOOKUP 함수
7. D3~U252: Events/Trades 참조 함수 (행 드래그)
8. V3~X252: Collection VLOOKUP
9. Y3~AA252: 검증 ✓/❌ 함수
10. 조건부 서식 설정
11. Row 1~2 고정 (틀 고정)
12. 시트 탭에 색상 지정 (파란색 계열 — 읽기 전용 표시)
13. 시트 편집 권한 잠금 (시트 보호 → 운영진 제외 편집 불가)
```

---

## 최종 스키마 — 전체 시트 참조표

> 마이그레이션 완료 후 목표 상태 기준. GAS 코드의 `SHEET_NAMES` / `SCHEMA` 와 1:1 대응.

---

### F.1 시트 전체 목록

| 시트명 (machine key) | 운영진 라벨 | 상태 | headerRow | dataStartRow | 비고 |
|---|---|---|---|---|---|
| `Events` | 이벤트 이력 | **신규** | 2 | 3 | append-only, LockService |
| `Users` | 회원 정보 | 기존 유지 | 1 | 2 | |
| `raw_checkins` | 미션 제출 이력 | 기존 유지 | 1 | 2 | Events 백필 후 읽기 전용 |
| `CardDraws` | 카드 뽑기 이력 | 기존 유지 | 1 | 2 | Events 백필 후 읽기 전용 |
| `BonusDraws` | 보너스 뽑기권 이력 | 기존 유지 | 1 | 2 | Events 백필 후 읽기 전용 |
| `Collection` | 카드 보유 현황 (캐시) | **헤더 정규화** | 1 | 2 | Phase 2D 이후 Events 파생 |
| `CardReceived` | 실물 카드 수령 수량 | 기존 유지 | 1 | 2 | |
| `Trades` | 카드 교환 요청·처리 | 기존 유지 | 1 | 2 | |
| `HoldPray` | H&P 기도제목 | **스키마 변경** | 2 | 3 | entryId 추가, Phase 2.0 D |
| `HPGuesses` | H&P 정답 제출 이력 | 기존 유지 | 1 | 2 | |
| `AppSettings` | 앱 설정 (Key-Value) | **신규** | 2 | 3 | config 분리 |
| `MissionDefinitions` | 주차별 미션 항목 | **신규** | 2 | 3 | config 분리 |
| `UserDashboard` | 유저 현황 대시보드 | **신규** | 2 | 3 | 읽기 전용, 시트 함수 |
| `TabSettings` | 탭 활성화 설정 | 기존 유지 | 1 | 2 | |
| `BBBSettings` | BBB 섹션 설정 | 기존 유지 | 1 | 2 | |
| `BBB` | BBB 매칭 관계 | 기존 유지 | 1 | 2 | |
| `BBBMessages` | BBB 익명 메시지 | 기존 유지 | 1 | 2 | |
| `BBBPhotos` | BBB 사진 업로드 | 기존 유지 | 1 | 2 | |
| `Notices` | 공지사항 | 기존 유지 | 1 | 2 | |
| `Inquiries` | 개발자 문의 | 기존 유지 | 1 | 2 | |
| ~~`config`~~ | ~~주차/미션 설정~~ | **폐기** | — | — | AppSettings + MissionDefinitions로 대체 |

---

### F.2 신규 시트 — 컬럼 상세 (상세 설계는 Phase 2.0 해당 섹션 참조)

#### Events
> 상세 설계: Phase 2.0 (A) 섹션

| machine header | 운영진 라벨 | 타입 | 필수 |
|---|---|---|---|
| `eventId` | 이벤트 ID | string | ✓ |
| `timestamp` | 발생 시각 | string (ISO 8601) | ✓ |
| `userId` | 닉네임 | string | ✓ |
| `type` | 이벤트 타입 | string | ✓ |
| `weekKey` | 주차 키 | string | |
| `refId` | 참조 ID (카드ID·교환ID 등) | string | |
| `amount` | 수량 (티켓 수 등, 항상 양수) | number | |
| `payload` | 추가 데이터 JSON | string | |
| `source` | 발생 주체 | string | ✓ |

#### AppSettings
> 상세 설계: Phase 2.0 (C) 섹션

| machine header | 운영진 라벨 | 초기 key 예시 |
|---|---|---|
| `key` | 설정 키 | `current_week`, `app_open_date`, `bbb_message_open`, `allow_test_draws` |
| `value` | 값 | |
| `type` | 타입 힌트 | `number`, `date`, `boolean`, `string` |
| `note` | 설명 | |

#### MissionDefinitions
> 상세 설계: Phase 2.0 (C) 섹션

| machine header | 운영진 라벨 | 타입 |
|---|---|---|
| `weekKey` | 주차 키 | string |
| `weekOrder` | 주차 순서 | number |
| `weekTitle` | 주차 제목 | string |
| `weekStartDate` | 시작일 | date |
| `weekEndDate` | 종료일 | date |
| `drawThreshold` | 뽑기권 발급 기준 점수 | number |
| `itemNo` | 항목 번호 | number |
| `itemText` | 항목 내용 | string |
| `scoreWeight` | 배점 | number |
| `category` | 분류 | string |
| `enabled` | 활성화 | boolean |

#### UserDashboard
> 상세 설계: Phase 2.0 (E) 섹션 — A~AA 27컬럼

| 그룹 | machine header | 운영진 라벨 | 소스 |
|---|---|---|---|
| 유저 | `userId` | 닉네임 | Users |
| 유저 | `name` | 이름 | Users |
| 유저 | `parish` | 교구 | Users |
| 미션 | `missionCount` | 미션 제출 수 | Events |
| 뽑기권 | `ticketsEarned` | 누적 획득 뽑기권 | Events |
| 뽑기권 | `ticketsConsumed` | 사용 뽑기권 | Events |
| 뽑기권 | `ticketsRemaining` | 남은 뽑기권 | 계산 |
| 카드 | `cardsDrawn` | 뽑은 총 횟수 | Events |
| 카드 | `card_1`~`card_10` | 사랑~히든 (10컬럼) | Events |
| 카드 | `totalCards` | 총 카드 수 | 계산 |
| 교환 | `activeTrades` | 진행중 교환 건수 | Trades |
| 활동 | `lastActivity` | 마지막 활동 시각 | Events |
| 검증 | `col_ticketsRemaining` | [컬렉션] 남은 뽑기권 | Collection |
| 검증 | `col_totalCards` | [컬렉션] 총 카드 수 | Collection |
| 검증 | `col_cardsDrawn` | [컬렉션] 뽑기 횟수 | Collection |
| 검증 | `valid_tickets` | 뽑기권 일치 ✓/❌ | 계산 |
| 검증 | `valid_cards` | 카드 수 일치 ✓/❌ | 계산 |
| 검증 | `valid_drawn` | 뽑기 횟수 일치 ✓/❌ | 계산 |

---

### F.3 헤더 정규화 대상 시트

마이그레이션 전/후 비교. `migrate_step3_normalizeHeaders()`로 일괄 처리.

#### Collection — 헤더 정규화

현재 시트 헤더(한글)를 machine header(영문)로 교체. SCHEMA.COLLECTION.columns 값도 함께 업데이트.

| GAS 코드 key | 현재 시트 헤더 | 목표 시트 헤더 (machine header) | 운영진 라벨 |
|---|---|---|---|
| `userId` | `userId` | `userId` | 닉네임 |
| `totalEarned` | `누적뽑기권` | `totalEarned` | 누적 획득 뽑기권 |
| `totalDrawn` | `실제뽑은개수` | `totalDrawn` | 뽑기 횟수 |
| `remaining` | `남은개수` | `remaining` | 남은 뽑기권 |
| `card_1` *(card1 → card_1)* | `사랑` | `card_1` | 사랑 |
| `card_2` *(card2 → card_2)* | `희락` | `card_2` | 희락 |
| `card_3` *(card3 → card_3)* | `화평` | `card_3` | 화평 |
| `card_4` *(card4 → card_4)* | `오래참음` | `card_4` | 오래참음 |
| `card_5` *(card5 → card_5)* | `자비` | `card_5` | 자비 |
| `card_6` *(card6 → card_6)* | `양선` | `card_6` | 양선 |
| `card_7` *(card7 → card_7)* | `충성` | `card_7` | 충성 |
| `card_8` *(card8 → card_8)* | `온유` | `card_8` | 온유 |
| `card_9` *(card9 → card_9)* | `절제` | `card_9` | 절제 |
| `totalCards` | `총카드수` | `totalCards` | 총 카드 수 |
| `card_10` *(hidden → card_10)* | `히든` | `card_10` | 히든 카드 |

> **GAS 코드 key도 변경됨**: `card1`→`card_1`, `hidden`→`card_10`. SCHEMA.COLLECTION.columns과 이를 참조하는 `getCollectionCardIndex_`, `rebuildCollectionSheet`, `updateCollectionSheet` 등을 Phase 2C에서 일괄 수정.  
> `card_N` 인덱스 = Events의 `refId` 문자열 `"N"`과 1:1 대응.

#### HoldPray — 헤더 정규화
> 상세 설계: Phase 2.0 (D) 섹션

현재 `이름(n)`, `교구(p)` 등 한글+약어 → `name`, `parish` 등 영문 machine header.  
`entryId` 컬럼 추가 (맨 앞). 헤더 구조가 1행 → 2행으로 변경.

---

### F.4 기존 유지 시트 — 컬럼 요약

Phase 0 조사 결과와 동일. 헤더는 이미 영문 machine key이며 추가 정규화 불필요.

| 시트 | 컬럼 (machine header) |
|---|---|
| `Users` | userId · password · name · parish · createdAt · isStaff · isDev · sessionToken · sessionUpdatedAt |
| `raw_checkins` | timestamp · weekTitle · items_json · userId · weekKey · dateKey · score · indices_json · weekCumScore · ticketEarned |
| `CardDraws` | userId · weekKey · cardId · cardName · drawnAt · received |
| `BonusDraws` | userId · source · awardedAt |
| `CardReceived` | nickname · cardId · receivedQty · updatedAt |
| `Trades` | id · requester · requesterCardId · requesterCardName · target · targetCardId · targetCardName · status · createdAt · resolvedAt · requesterPrayed · targetPrayed |
| `HPGuesses` | nickname · weekKey · cardIndex · guessedName · answeredAt |
| `TabSettings` | tab_key · label · enabled |
| `BBBSettings` | key · open · text |
| `BBB` | userId · careBuddyId · careBuddyName · guessedCorrect · secretBuddyId · secretBuddyName |
| `BBBMessages` | msgId · fromUserId · toUserId · message · createdAt |
| `BBBPhotos` | userId · photoBase64 · uploadedAt · missionType |
| `Notices` | id · title · content · createdAt · imageUrl · updatedAt |
| `Inquiries` | id · nickname · content · createdAt · reply · repliedAt |

---

### F.5 SHEET_NAMES 최종 상수

```js
const SHEET_NAMES = Object.freeze({
  // ── 신규 ─────────────────────────────────────────
  EVENTS:              'Events',
  APP_SETTINGS:        'AppSettings',
  MISSION_DEFINITIONS: 'MissionDefinitions',
  USER_DASHBOARD:      'UserDashboard',
  // ── 기존 유지 ─────────────────────────────────────
  USERS:         'Users',
  RAW_CHECKINS:  'raw_checkins',
  CARD_DRAWS:    'CardDraws',
  BONUS_DRAWS:   'BonusDraws',
  COLLECTION:    'Collection',
  CARD_RECEIVED: 'CardReceived',
  TRADES:        'Trades',
  HOLD_PRAY:     'HoldPray',
  HP_GUESSES:    'HPGuesses',
  TAB_SETTINGS:  'TabSettings',
  BBB_SETTINGS:  'BBBSettings',
  BBB:           'BBB',
  BBB_MESSAGES:  'BBBMessages',
  BBB_PHOTOS:    'BBBPhotos',
  NOTICES:       'Notices',
  INQUIRIES:     'Inquiries',
  // ── 폐기 예정 ─────────────────────────────────────
  CONFIG:        'config',  // migrate_step4 후 제거
});
```

---

### F.6 시트 탭 순서 + 색상 (migrate_step7_orderAndColor 기준)

| 순서 | 시트명 | 탭 색상 | 비고 |
|---|---|---|---|
| 1 | `Events` | 🟣 보라 | Truth source, 핵심 |
| 2 | `UserDashboard` | 🔵 파랑 | 읽기 전용 |
| 3 | `Users` | 🟢 초록 | 회원 |
| 4 | `Collection` | 🟢 초록 | 회원 |
| 5 | `raw_checkins` | 🟡 노랑 | 도메인 |
| 6 | `CardDraws` | 🟡 노랑 | 도메인 |
| 7 | `BonusDraws` | 🟡 노랑 | 도메인 |
| 8 | `CardReceived` | 🟡 노랑 | 도메인 |
| 9 | `Trades` | 🟡 노랑 | 도메인 |
| 10 | `HoldPray` | 🟠 주황 | H&P |
| 11 | `HPGuesses` | 🟠 주황 | H&P |
| 12 | `AppSettings` | ⚫ 회색 | 설정 |
| 13 | `MissionDefinitions` | ⚫ 회색 | 설정 |
| 14 | `TabSettings` | ⚫ 회색 | 설정 |
| 15 | `BBBSettings` | ⚫ 회색 | 설정 |
| 16 | `BBB` | 🔴 빨강 | BBB |
| 17 | `BBBMessages` | 🔴 빨강 | BBB |
| 18 | `BBBPhotos` | 🔴 빨강 | BBB |
| 19 | `Notices` | ⬜ 흰색 | 커뮤니티 |
| 20 | `Inquiries` | ⬜ 흰색 | 커뮤니티 |

---

## 결정 사항

### 합치기로 결정한 것

#### CardDraws + BonusDraws → CardLedger

- 본질이 같은 타임라인 — 뽑기권 적립/사용
- 목표 key. `CardLedger`
- 컬럼 구성. `id`, `nickname`, `type`, `source`, `cardId`, `createdAt`
- 운영진 라벨. `ID`, `닉네임`, `유형(적립/사용)`, `사유`, `카드ID`, `생성일시`
- 적립 row 는 `카드ID` 빈 셀, 사용 row 는 `사유` 단순화. sparse 받아들임
- 효과. "이 사람이 언제 뽑기권 얼마나 적립/사용했나" 한 시트에서 SUMIF 로 잔액 계산 가능

### 쪼개기로 결정한 것

#### config → AppSettings + MissionDefinitions

- 현재 `config` 한 시트에 단일값 설정 (`B1` 현재주차, `B4` 앱오픈일, `C1` BBB메시지 토글, 탭 활성화) + 주차별 미션 정의 (8행 단위 블록 × 6주차) 다 섞임
- 운영진 통증의 핵심 — "이번 주차 미션 어디서 수정하지?" "BBB 메시지 입력창 켜려면?" 매번 행 번호 찾아야 함
- 분리 후.
  - `AppSettings` 는 Key-Value. 예. `bbb_message_open | TRUE | boolean | BBB 메시지 입력창`.
  - `MissionDefinitions` 는 1행 1미션. `week`, `order`, `title`, `score`, `category`, `enabled`.

### 분리 유지하기로 결정 (합치지 않은 것)

| 검토한 묶음 | 결론 | 이유 |
|---|---|---|
| `Collection` 제거 (`CardDraws` 에서 derive) | 유지 | 캐시 역할. derive 하면 read 느려짐. 운영진도 "누가 뭐 갖고 있나" 보기 좋음 |
| `BBBMessages` + `BBBPhotos` 합치기 | 분리 유지 | 데이터 shape 너무 다름 (text vs 사진 URL). 합치면 sparse column 폭증 |
| `Notices` + `Inquiries` 합치기 | 분리 유지 | 방향 반대 (운영→유저 vs 유저→운영). 워크플로우도 다름 |
| `BBB` + `BBBMessages` 합치기 | 분리 유지 | cardinality 다름 (1인당 매칭 1행 vs 메시지 N행) |

### 하드코딩 제거 방향

| 데이터 | 현재 위치 | 목표 위치 | 우선순위 |
|---|---|---|---|
| PROD/DEV 스프레드시트 ID | `Apps_Script` 상수 | 배포별 Apps Script Script Properties의 `SPREADSHEET_ID` | 높음 |
| 관리자 비밀번호 | `Apps_Script` 상수 | Apps Script Script Properties | 높음 |
| 사용자 비밀번호 | `Users` B열 평문 | `passwordHash`, `passwordSalt` 컬럼 | 높음 |
| H&P 기도제목 | `HOLD_PRAY_ENTRIES` 하드코딩 | `HoldPray` 시트 | 높음 |
| 미션 정의 | `config` 8행 블록 | `MissionDefinitions` | 중간 |
| 앱 설정 | `config` 특정 셀 | `AppSettings` | 중간 |
| 카드 정의 | `app.js`, `Apps_Script` 중복 상수 | `CardDefinitions` 또는 정적 JSON | 낮음 |

---

## 리스크 및 완화책

### 리스크 1. 마이그레이션 중 데이터 손실

- **완화.** Phase 3 첫 단계로 모든 시트 복제하여 `백업_YYYYMMDD_원본명` 으로 보관
- 문제 시 백업 시트를 원래 이름으로 되돌리고 GAS 이전 버전으로 롤백

### 리스크 2. GAS 재배포 → URL 변경 → 클라이언트 끊김

- **완화.** GAS Web App 배포 시 "Manage Deployments → 기존 배포 편집 → 새 버전" 으로 동일 URL 유지
- URL 바뀐 경우 `app.js` + `admin.html` 의 DEV/PROD `API_BASE` 동시 갱신 필수
- `app.js`와 `admin.html`은 dev/local/preview 환경에서 DEV GAS URL을 직접 참조하고, PROD 환경에서는 PROD GAS URL을 참조해야 한다.

### 리스크 3. 컬럼 인덱스 기반 코드가 새 헤더 순서로 깨짐

- **완화.** Phase 1 에서 모든 컬럼 접근을 `getColumns(sheet)` 헬퍼 기반으로 전환
- 헤더 이름이 바뀌어도 코드 자동 추적

### 리스크 4. 운영진이 변경된 시트 구조를 모름

- **완화.** Phase 3 완료 후 운영진에 변경 내역 정리한 가이드 1장 전달

---

## 마이그레이션 실행 순서 (확정)

1. DEV 시트에서 전체 사이클 테스트 통과
2. PROD 백업 시트 복제
3. 사용자 적은 시간대 (새벽) 진행 권장
4. PROD 마이그레이션 함수 실행
5. GAS 새 버전 배포
6. 클라이언트 동작 확인
7. 문제 없으면 백업 시트는 1주일간 보관 후 제거

---

## 작업 브랜치

- (확정 필요) 현재 `dev` 에 바로 작업할지, 별도 `feat/sheet-restructure` 따로 작업할지
- 추천. `feat/sheet-restructure` — 작업량이 3일 이상이고 GAS 전체를 건드리므로 격리 권장

---

## 미해결 / 추후 결정 사항

- PROD/DEV 실제 Google Sheet 헤더와 로컬 `Apps_Script` 생성 규칙 대조 완료. 사용자 확인 기준.
- DEV 시트 (`19-2XZ3...`) 실제 존재 여부 + 데이터 보유 여부 확인 필요
- `MissionDefinitions` row 구조는 1행 1미션으로 가는 것이 현재 권장안
- Row 1 운영진 라벨, Row 2 machine header 방식이 실제 Google Sheets 사용성에 맞는지 샘플 시트에서 확인 필요
- `CardLedger`로 `CardDraws`와 `BonusDraws`를 통합할지, 기존 두 시트를 유지하고 View 성격의 요약 시트를 둘지 결정 필요

---

## 작업 로그

> 각 Phase 완료 시 여기에 한 줄로 기록.

- 2026-05-12. 계획 수립 + 본 문서 작성
- 2026-05-12. Phase 0 로컬 조사 완료. `Apps_Script` 기준 현재 스키마, 주요 컬럼 의존성, 영향 함수 목록 문서화. 시트명은 한글 변경 대신 영문 key 유지 + 운영진 라벨/설명 방식으로 방향 수정.
- 2026-05-12. `admin.html`의 `API_BASE`가 dev/local에서는 DEV GAS, 일반 배포에서는 PROD GAS를 참조하도록 분기된 것을 정적 확인.
- 2026-05-12. PROD/DEV 실제 Google Sheet 헤더와 로컬 `Apps_Script` 분석 결과 대조 완료. 사용자 확인 기준.
- 2026-05-12. Phase 1 시작. `Apps_Script`에 `SHEET_NAMES`, `SCHEMA`, `getColumns`, `getSheetRows` 추가. 리터럴 시트명 참조를 `SHEET_NAMES`로 1차 치환하고, `Users` 인증/세션/이름 매핑 흐름은 컬럼 헬퍼 기반으로 전환.
- 2026-05-12. Phase 1.5 시작. 이번 실행 범위는 `SPREADSHEET_ID`, `DEV_SPREADSHEET_ID`, `ADMIN_PASSWORD`의 Script Properties 전환으로 한정하고, 사용자 비밀번호 hash 전환과 행사 데이터 외부화는 별도 하위 Phase로 분리.
- 2026-05-12. Phase 1.5 Script Properties 전환 완료. `Apps_Script`에서 민감값 리터럴을 제거하고 DEV Apps Script 프로젝트 Properties에 값을 설정한 뒤 기존 DEV 웹앱 배포를 version 5로 재배포. `adminLogin`, `getCurrentWeek`, `dashboard`, `getCardStats`, `getTabSettings` smoke 테스트 통과.
- 2026-05-12. Phase 1.5 후속 정리. `DEV_SPREADSHEET_ID`, `_devMode`, 프론트의 `devMode=true` 자동 첨부를 제거하고, GAS 프로젝트별 `SPREADSHEET_ID` Property 하나로 DEV/PROD 시트를 구분하도록 로컬 코드 수정. 이후 GAS 반영과 Properties 확인은 사용자가 수동으로 진행.
- 2026-05-12. Phase 2/3을 Event Sourcing 단계 구조(2A~2E / 3A~3E)로 재편. DEV는 활성 사용자 없으니 dual-write 단계 생략하고 big-bang 변환으로 가기로 결정. PROD는 활성 사용자 있어서 Phase 3에서 dual-write 안전 모드 유지.
- 2026-05-12. 사용자 확인. DEV Phase 2는 big-bang으로 진행. 이에 따라 Phase 2A는 DEV Events 시트 생성 + 기존 데이터 백필 + dry-run/verify 중심으로 정렬하고, PROD dual-write는 Phase 3A에만 유지.
- 2026-05-12. Phase 2.0 설계 시작. Events 시트 스키마 + event type 카탈로그 확정. 컬럼 구조는 하이브리드(`refId`/`amount`/`weekKey` 별도 컬럼 + `payload` JSON). append-only + LockService + ISO 8601 timestamp 채택.
- 2026-05-12. Phase 2.0 (B) 과거 데이터 → Events 변환 규칙 확정. 시트별 변환 매트릭스 + 컬럼 매핑 + idempotent 함수 구조. BBB 메시지/사진은 raw content라서 Events 적재 제외. `BBBMessages`/`BBBPhotos`/`Notices`/`Inquiries` 는 도메인 시트로 standalone 유지. A.9 미해결 4개 모두 해소.
- 2026-05-12. Phase 2A 로컬 GAS 구현 완료. `SHEET_NAMES.EVENTS`, `SCHEMA.EVENTS`, `Events_append`, `Events_readByUser`, `migrate_step5_absorbToEvents`, `migrate_step5_absorbToEvents_dryRun`, `migrate_verify` 를 `Apps_Script`에 추가. 백필은 `source='migration'` 이벤트만 지우고 재생성하는 idempotent 방식이며, BBB 메시지/사진/공지/문의는 원자료 도메인 시트 유지 정책에 따라 제외.
- 2026-05-12. Phase 2.0 (C) AppSettings + MissionDefinitions 스키마 확정. `config` 시트 단일값 설정 → `AppSettings` (Key-Value 4컬럼), 8행 블록 미션 정의 → `MissionDefinitions` (1행 1미션 항목, denormalized). GAS 헬퍼 `getAppSetting_` / `setAppSetting_` / `getMissionItems_` / `getAllWeekMeta_` 설계. migrate_step4_splitConfig() 구조 작성.
- 2026-05-12. Phase 2.0 (D) HoldPray 정규화 설계 확정. `entryId` 컬럼 추가 + 헤더를 영문 machine key로 교체 + 2행 헤더 구조(운영진 라벨/machine header)로 전환. migrate_step6_externalizeHoldPray() 구조 작성. `getYouthHpEntries()` 반환 형식(`n/p/c/a/nick` → 영문 key)은 Phase 2C 일괄 전환으로 분리. `HOLD_PRAY_ENTRIES` 상수 제거는 migrate_step6 + fallback 분기 제거 후 진행.
- 2026-05-12. Phase 2.0 (E) UserDashboard 컬럼 명세 + 시트 함수 설계 완료. A~AA 27컬럼 구성: 유저 식별(A~C) / 미션(D) / 뽑기권(E~G) / 카드(H~S, 카드별 10종) / 교환(T) / 마지막 활동(U) / Collection 검증값(V~X) / 검증 ✓/❌(Y~AA). amount 양수 저장 정책, Users 단순 참조 방식, 조건부 서식 설정 순서, 성능 고려사항 포함.
- 2026-05-12. Phase 2B 로컬 GAS 구현 완료. `SHEET_NAMES.USER_DASHBOARD`, `SCHEMA.USER_DASHBOARD`, `setupUserDashboard(rowLimit)` 추가. `UserDashboard` 3행은 `Users` 2행을 참조하도록 보정했고, Events 실제 컬럼 순서(`refId`=E, `amount`=F, `weekKey`=G)에 맞춰 SUMIFS/COUNTIFS 수식을 생성. 마지막 활동은 ISO 문자열 timestamp를 `FILTER` + `SORT` + `INDEX`로 계산.
- 2026-05-12. DEV 시트 UI 정리용 `hideLegacyDevSheets()` 구현. 최종 구조에서 Events/AppSettings/MissionDefinitions로 흡수될 `config`, `raw_checkins`, `CardDraws`, `BonusDraws` 만 숨김 처리하고, `Collection`, `Trades`, `HPGuesses`, BBB/공지/문의 등 최종 유지 도메인 시트는 표시 상태로 둔다. 삭제가 아니라 숨김이므로 현행 GAS read/write에는 영향 없음.
- 2026-05-12. 최종 스키마 (F) 확정. 전체 21개 시트 목록(신규 4 + 기존 16 + 폐기 1), Collection 헤더 정규화 매핑(card1→card_1, hidden→card_10), SHEET_NAMES 최종 상수, 시트 탭 순서 + 색상 정의. CLAUDE.md 시트 구성표도 함께 갱신.
- 2026-05-12. Phase 2C 첫 로컬 구현 시작. `SHEET_NAMES.APP_SETTINGS`, `SHEET_NAMES.MISSION_DEFINITIONS`, 각 `SCHEMA`와 2행 헤더 생성 헬퍼를 `Apps_Script`에 추가. `migrate_step1_backup()`은 기존 Drive 백업 함수를 호출하는 래퍼로 두고, `migrate_step4_splitConfig()` / `_dryRun()`은 기존 `config` 값을 `AppSettings` 7행 + `MissionDefinitions` 36행으로 복사하도록 구현. 이번 조각은 새 시트 생성과 데이터 복사까지만 수행하며, 현행 앱의 read path는 아직 기존 `config`를 유지한다.
- 2026-05-12. Phase 2C 두 번째 로컬 구현 완료. `getAppSetting_()` / `setAppSetting_()`과 `getMissionConfigFromDefinitions_()` / `getAllWeekMeta_()`를 추가하고, `getConfig()`, `getCurrentWeek`, `setCurrentWeek`, `getMissionConfig`, `setMissionConfig`, `getAppOpenDate()`, 티켓/Collection 재계산 threshold 경로를 `AppSettings` / `MissionDefinitions` 우선으로 전환. 새 시트가 없거나 값이 비어 있으면 기존 `config` fallback을 유지하고, admin 쓰기 경로는 새 시트에 쓰면서 legacy `config`도 동기화해 롤백 여지를 남긴다.
- 2026-05-12. Phase 2C H&P 하드코딩 제거(`migrate_step6_externalizeHoldPray`)는 사용자의 결정으로 보류. 대신 로직 영향이 낮은 `migrate_step7_orderAndColor()`를 로컬 GAS에 추가. F.6의 시트 순서와 색상 기준으로 탭을 정렬하고 색상을 지정한 뒤, 마지막에 `applyFinalSheetVisibility()`를 호출해 `config`, `raw_checkins`, `CardDraws`, `BonusDraws` 숨김 정책을 다시 적용한다.
- 2026-05-12. Phase 2D 시작. 쓰기 경로 전환 전에 비교 전용 `previewCollectionProjection(userId)`를 로컬 GAS에 추가. 인자 없이 실행하면 Users/Collection/Events에서 후보 유저를 모아 기존 Collection row와 Events 기반 projection을 비교한다. projection은 `ticket.granted`, `ticket.consumed`, `card.drawn`, `trade.requested`+`trade.accepted`를 반영하고, field별 diff를 로그로 반환한다. 아직 `updateCollectionSheet`, `updateTicketCols`, `rebuildCollectionSheet`의 실제 쓰기 경로는 변경하지 않았다.
- 2026-05-12. 사용자 DEV 확인 기준 `previewCollectionProjection()` 결과 `mismatchCount: 0`. 이어서 `rebuildCollectionRow(userId)`를 로컬 GAS에 추가. 공개 함수는 Lock을 잡고, 내부 `rebuildCollectionRow_(userId)`가 Events projection을 Collection row에 upsert한다. 기존 mutation 경로는 아직 변경하지 않았고, 수동 검증용 관리자 POST 액션 `adminRebuildCollectionRow`만 추가했다.
