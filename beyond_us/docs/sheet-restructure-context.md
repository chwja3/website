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
| PROD/DEV 스프레드시트 ID | `Apps_Script` 상수 | Apps Script Script Properties | 높음 |
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
- 특히 `admin.html`은 dev/local에서도 현재 단일 `API_BASE`에 devMode만 붙이는 구조이므로, 계획 실행 시 dev/local 관리자 페이지가 바뀐 DEV GAS를 직접 참조하도록 수정해야 한다.

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
