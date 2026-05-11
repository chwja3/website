<!-- beyond_us 폴더 전체 파일 분석 보고서 -->

# beyond_us 전체 파일 분석

작성일: 2026-05-12.

## 1. 전체 구조 요약

`beyond_us`는 2026 청년교구 수련회 준비 앱이다. 프론트엔드는 정적 파일로 GitHub Pages에 배포되고, 메인 데이터는 Google Apps Script와 Google Sheets를 통해 처리된다. 실시간 채팅만 Firebase Firestore를 사용한다.

핵심 실행 축은 다음 다섯 파일이다.

| 파일 | 역할 | 규모 |
|---|---:|---:|
| `app.html` | 사용자 앱의 DOM 골격 | 약 70 KB |
| `app.css` | 사용자 앱 스타일과 애니메이션 | 약 80 KB |
| `app.js` | 사용자 앱 전체 로직 | 약 207 KB |
| `admin.html` | 관리자 페이지 전체 UI와 로직 | 약 90 KB |
| `Apps_Script` | GAS 백엔드 API 소스 | 약 158 KB |

기타 파일은 PWA 설정, 서비스 워커, 문서, 미션 설정 TSV, 이미지와 음악 자산, 원본 콘텐츠 자료로 구성된다.

## 2. 진입점과 배포 파일

### `index.html`

`beyond_us` 하위의 진입점이다. 내용은 매우 작고, 즉시 `app.html`로 이동시키는 리다이렉트 파일이다. 구버전 PWA 캐시나 직접 URL 진입을 위해 유지되는 호환 레이어로 보인다.

### `app.html`

사용자 앱의 화면 골격이다. CSS와 JS를 외부 파일로 분리해서 로드한다.

주요 화면 블록은 다음과 같다.

| 영역 | 주요 ID | 설명 |
|---|---|---|
| 스플래시 | `splashScreen` | 앱 로딩 중 표시 |
| 설치 배너 | `installBanner` | PWA 설치 유도 |
| 오픈 전 화면 | `comingSoonScreen` | 정식 오픈 전 안내와 H&P 미리보기 |
| 인증 | `authScreen` | 회원가입, 로그인, 닉네임 찾기, 비밀번호 변경 |
| 카드 뽑기 | `drawOverlay` | 카드팩 선택, 찢기, 공개, 컬렉션 이동 |
| 앱 본문 | `appScreen` | 상단바, 드로어, 섹션 컨테이너 |
| 공지 | `sectionNotice` | 공지사항 목록과 검색 |
| 사전미션 | `sectionMission` | 미션 제출, 주간 달력, 카드 뽑기, 현황 |
| 컬렉션 | `sectionCollection` | 카드 보유 현황과 교환현황 |
| 교환 모달 | `tradeOverlay` | 4단계 카드 교환 요청 플로우 |
| H&P | `sectionPrayer` | 기도제목 카드 캐러셀 |
| QnA | `sectionFaq` | 정적 FAQ 아코디언 |
| 문의 | `sectionInquiry` | 개발자 문의 목록과 CRUD |
| 채팅 | `sectionChat` | Firebase 기반 실시간 채팅 |
| BBB | `sectionSecret` | 현장미션 B.B.B.와 사진 업로드 |

외부 의존성은 Google Fonts의 Nanum Pen Script와 GSAP 3.12.5 CDN이다.

### `app.css`

사용자 앱 전체 스타일이다. 전역 색상, 미션 카드, 인증 화면, 드로어, 카드 뽑기 애니메이션, 컬렉션, Coming Soon, H&P, 채팅 UI까지 한 파일에 들어 있다.

특징은 다음과 같다.

- 카드 뽑기 화면의 CSS 비중이 크다.
- `#drawOverlay`, `#carouselLayer`, `#packLayer`, `#cardLayer`, `#settleActions` 중심으로 복잡한 레이어 애니메이션이 구성되어 있다.
- H&P는 손글씨 폰트와 카드 이미지 위 텍스트 fitting 로직을 전제로 스타일링되어 있다.
- 작은 화면 대응은 일부 `@media`로 처리되어 있다.
- CSS 안에서 카드팩과 카드 뒷면 이미지를 직접 참조한다.

### `app.js`

사용자 앱의 메인 로직이다. 주요 책임은 다음과 같다.

| 영역 | 함수 예시 | 설명 |
|---|---|---|
| API와 세션 | `post`, `withSession`, `getSessionToken` | GAS 호출과 세션 토큰 첨부 |
| 버전 갱신 | `checkVersion`, `showUpdateBanner` | `version.txt`와 `APP_VERSION` 비교 |
| DEV 분기 | `IS_DEV_ENV`, fetch interceptor | DEV 환경에서 `devMode=true` 자동 첨부 |
| 인증 | `autoLogin`, 회원가입/로그인 이벤트 | 로컬 캐시 기반 즉시 진입과 백그라운드 검증 |
| 미션 | `loadAll`, `renderConfig`, `saveSubmittedItems` | 제출 상태, 달력, 점수, 뽑기권 반영 |
| 카드 | `renderDrawSection`, `openDrawOverlay`, `renderCollection` | 카드 뽑기와 컬렉션 렌더링 |
| 교환 | `openTradeModal`, `requestTrade`, `loadTrades` | 교환 요청, 수락, 거절, 취소, 기도 표시 |
| 공지 | `loadNotices`, `renderNoticeList` | 공지 목록, 이미지, 읽음 표시 |
| 문의 | `loadInquiries`, `postInquiry`, `editInquiry` | 사용자 문의 CRUD |
| BBB | `loadBBB`, `sendBBBMsg`, `bbbM3Upload` | 버디 정보, 메시지, 사진, 지도 미션 |
| H&P | `loadHoldPray`, `guessHoldPray`, `hpHintInquiry` | 기도 카드, 정답 제출, 힌트 문의 |
| 채팅 | `ensureFirebase`, `initChat` | Firestore 메시지 구독과 전송 |
| PWA | `initInstallBanner`, service worker 등록 | 설치 안내와 오프라인 대응 |

중요한 상태 저장소는 `localStorage`이다. 주요 키는 `beyondus_nickname`, `beyondus_parish`, `beyondus_session_token`, `beyondus_cache_config`, `beyondus_cache_userStatus_*`, `beyondus_seen_notices`, `beyondus_new_card_*`, `beyondus_hp_*` 계열이다.

주의할 점은 다음과 같다.

- DEV URL 또는 localhost에서는 실제 `API_BASE`는 DEV GAS로 바뀌고, fetch interceptor가 `devMode=true`도 추가한다.
- `?test=1` 또는 DEV 환경에서는 일부 클라이언트 테스트 모드가 켜진다.
- Firebase 설정은 클라이언트에 포함되어 있고, Firestore 보안 규칙에 의존한다.
- 코드와 문서가 일부 어긋난다. 문서는 비밀번호 해시 저장을 말하지만, 현재 GAS는 비밀번호를 평문으로 저장하고 비교한다.

### `admin.html`

관리자 페이지는 CSS, HTML, JS가 모두 한 파일에 들어 있다.

주요 패널은 다음과 같다.

| 패널 | data-panel | 설명 |
|---|---|---|
| 공지 | `notice` | 공지 등록, 이미지 업로드, 수정, 삭제 |
| 실물 카드 수령 | `cards` | 카드 수령 수량과 교환 반영 확인 |
| 주차·미션 설정 | `settings` | 현재 주차, 주차별 미션 항목 수정 |
| 탭 활성화 | `tabtoggle` | 앱 탭과 BBB 섹션 오픈 상태 조정 |
| 유저 비밀번호 초기화 | `users` | 사용자 목록과 비밀번호 초기화 |
| 개발자 문의 | `inquiry` | 문의 답변과 삭제 |
| 현장미션 BBB | `bbb` | 매칭 실행, 메시지 로그, 섹션 토글 |
| 카드 집계 | `collection` | 컬렉션 재빌드와 raw header/backfill 관리 |

중요한 차이점은 `admin.html`의 `API_BASE`가 PROD GAS URL로 고정되어 있다는 점이다. DEV 환경에서는 같은 URL에 `devMode=true`를 붙이는 방식이다. 사용자 앱의 `app.js`처럼 DEV GAS URL 자체로 분기하지 않는다. 따라서 관리자 작업 시 실제 GAS 배포와 `devMode` 처리 방식이 맞는지 확인이 필요하다.

### `sw.js`

서비스 워커다. `CACHE = 'beyondus-20260512a'`로 현재 버전과 맞춰져 있다. 설치 시 주요 HTML, CSS, JS, 아이콘, 카드 이미지를 캐시에 넣고, 활성화 시 이전 캐시를 삭제한다. HTML 진입점은 네트워크 우선이고, 그 외 GET 요청은 캐시 우선이다.

### `version.txt`

현재 값은 `20260512a`이다. `app.js`의 `APP_VERSION`과 `sw.js`의 `CACHE` suffix와 일치한다.

### `manifest.json`

PROD PWA 매니페스트다. 앱 이름은 `Beyond Us`, standalone 표시, 배경색과 테마색은 앱의 베이지/짙은 갈색 계열과 맞춰져 있다. `pabicon` 계열 5개 아이콘을 참조한다.

### `manifest-dev.json`

DEV PWA 매니페스트다. 앱 이름은 `Beyond Us (DEV)`, short name은 `BU DEV`이고 테마색이 경고색 계열이다. DEV 환경에서 `app.js`가 manifest href를 이 파일로 바꾼다.

## 3. GAS 백엔드 분석

### `Apps_Script`

GAS 백엔드 전체 소스다. PROD와 DEV 스프레드시트 ID를 모두 가지고 있고, 요청마다 `_devMode` 값에 따라 `getSpreadsheet()`가 사용할 시트를 바꾼다.

주요 시트 접근은 다음과 같다.

| 시트 | 역할 |
|---|---|
| `Users` | 회원, 비밀번호, 교구, 운영진 여부, 세션 토큰 |
| `config` | 현재 주차, 앱 오픈일, 미션 정의, 일부 토글 |
| `raw_checkins` | 미션 제출 이력과 주차 누적 점수 |
| `CardDraws` | 카드 뽑기 이력 |
| `Collection` | 카드 보유 현황과 뽑기권 캐시 |
| `BonusDraws` | H&P와 BBB 등 보너스 뽑기권 |
| `HoldPray` | H&P 기도제목 |
| `HPGuesses` | H&P 정답 제출 이력 |
| `TabSettings` | 앱 탭 활성화 설정 |
| `BBBSettings` | BBB 섹션별 오픈과 안내문 |
| `BBB` | BBB 매칭 정보 |
| `BBBMessages` | BBB 익명 메시지 |
| `BBBPhotos` | BBB 사진 업로드 |
| `Notices` | 공지사항 |
| `Inquiries` | 개발자 문의 |
| `Trades` | 카드 교환 요청 |
| `CardReceived` | 실물 카드 수령 수량 |

GAS action 목록은 다음과 같다.

| 분류 | action |
|---|---|
| 인증 | `register`, `login`, `resetPassword`, `adminLogin`, `adminResetPassword` |
| 미션 | `dashboard`, `userStatus`, `submit`, `getCurrentWeek`, `setCurrentWeek`, `getMissionConfig`, `setMissionConfig` |
| 카드 | `drawCard`, `getPublicCollection`, `getCardStats`, `getTicketStats`, `setCardReceivedQty`, `setDrawReceived`, `adminRebuildCollection` |
| 교환 | `requestTrade`, `acceptTrade`, `rejectTrade`, `cancelTrade`, `prayForTrade`, `getTrades`, `getAdminTrades` |
| H&P | `getHoldPray`, `submitHoldPrayGuess`, `postHpHint` |
| BBB | `getBBB`, `getBBBMessages`, `guessBBBSecret`, `sendBBBMessage`, `uploadBBBPhoto`, `deleteBBBPhoto`, `adminGetBBB`, `adminSetupBBBMatching`, `adminWriteBBBRows`, `adminSetBBBMessageOpen` |
| 공지/문의 | `getNotices`, `postNotice`, `editNotice`, `deleteNotice`, `getInquiries`, `postInquiry`, `editInquiry`, `deleteInquiry`, `replyInquiry` |
| 정비 | `adminSetupRawHeader`, `adminBackfillRawCols`, `migrateCardDrawsToCollection`, `adminGrantHiddenCard` |

동시성 대응은 중요한 쓰기 경로에 `LockService`를 사용한다. 미션 제출과 카드 뽑기에는 `requestId` 기반 캐시도 있어 중복 요청을 줄인다. 대시보드와 공지 등 일부 조회는 `CacheService`를 사용한다.

주의할 점은 다음과 같다.

- `ADMIN_PASSWORD`가 소스에 하드코딩되어 있다.
- 사용자 비밀번호는 현재 코드상 평문 저장/비교다.
- `HOLD_PRAY_ENTRIES`에 실제 이름과 기도제목이 대량 하드코딩되어 있다.
- 문서의 BBB 시트명은 `BBB_Messages`, `BBB_Photos`로 쓰인 곳이 있으나 실제 GAS는 `BBBMessages`, `BBBPhotos`를 사용한다.
- 시트 접근 상당수가 숫자 인덱스와 고정 컬럼 위치에 묶여 있어, 시트 구조 개편 전 `getColumns`류 헬퍼 도입이 필요하다.

## 4. 관리자와 사용자 앱의 데이터 흐름

사용자 앱은 `app.html`에서 DOM을 만들고 `app.js`가 이벤트와 렌더링을 모두 제어한다. 대부분의 영속 데이터는 GAS로 보내고, 빠른 화면 반응은 `localStorage` 캐시로 보완한다.

관리자 페이지는 별도 SPA처럼 동작한다. `admin.html` 내부에서 로그인 후 패널별로 GAS action을 호출한다. 운영 작업은 대부분 Google Sheets를 직접 편집하지 않고 admin UI를 통해 가능하도록 되어 있다.

GAS는 Web App으로 배포되며, `doGet`과 `doPost`에서 action 기반 라우팅을 한다. DEV/PROD 시트 분리는 `_devMode`와 `getSpreadsheet()`로 처리한다.

## 5. 미션 설정과 원본 콘텐츠

### `config_sheets/w1.tsv`부터 `w6.tsv`

주차별 미션 원본 TSV다. 각 파일은 `week_title`, 설정값, threshold처럼 보이는 값, 6개 미션 항목으로 구성된다. 항목은 텍스트, 점수, 카테고리(`L`, `MC`, `MW`)를 가진다.

현재 threshold로 보이는 값은 다음과 같다.

| 파일 | 주차 | threshold 값 |
|---|---|---:|
| `w1.tsv` | 1주차 | 9 |
| `w2.tsv` | 2주차 | 9 |
| `w3.tsv` | 3주차 | 9 |
| `w4.tsv` | 4주차 | 10 |
| `w5.tsv` | 5주차 | 11 |
| `w6.tsv` | 6주차 | 10 |

### `사전미션.txt`

초기 사전미션안으로 보인다. 각 주차별 4개 안팎의 미션과 총점, 뽑기 기준이 적혀 있다.

### `사전미션_6개버전.txt`

6개 항목 버전의 사전미션안이다. `config_sheets`의 내용과 더 가깝고, 새로 추가된 항목은 별표로 표시되어 있다.

### `Beyond_Us_QnA.txt`

앱 사용자를 위한 FAQ 원본이다. 설치, 계정/로그인, 미션 체크, EN카드 뽑기, 기타 문제 대응으로 구성된다.

### `손기도 1차 정리.xlsx`

Excel 원본 자료다. 내부 구조는 시트 3개(`Sheet1`, `Sheet2`, `Sheet3`)이며, 공유 문자열과 worksheet XML을 포함한다. 파일명상 H&P 또는 손기도 원자료로 보인다.

## 6. 문서 파일

### `CLAUDE.md`

프로젝트 운영 지침이 가장 많이 담긴 문서다. 앱 개요, 기술 스택, 파일 구조, GAS action 목록, 이미지 자산, Git 워크플로우, 주요 기능별 함수 인덱스가 포함되어 있다.

주의할 점은 문서가 일부 현재 코드와 다르다는 것이다. 특히 현재 구조는 `app.html`, `app.css`, `app.js` 분할인데 문서 상단에는 “단일 index.html 파일”이라는 과거 표현이 남아 있다. 비밀번호 저장 정책도 문서와 코드가 다르다.

### `TODO.md`

현재 유지되는 TODO 문서다. 완료 항목과 남은 항목이 잘 구분되어 있다. 남은 주요 항목은 H&P 손바닥 텍스트 정렬 확인, 카드팩 캐러셀 로딩 단축, 실물카드 교환과 앱 컬렉션 동기화, 현장 미션 보상, H&P 답 공유 등이다.

### `TODO.txt`

오래된 TODO 문서다. 2026-04-28 기준의 초기 계획이 들어 있고, 현재는 상당수가 `TODO.md`와 실제 코드로 흡수된 상태다. 보존용 히스토리로 보는 게 맞다.

### `docs/sheet-restructure-plan.md`

Google Sheets 구조 개편 전체 계획이다. Phase 0부터 Phase 3까지 현황 파악, GAS 리팩토링, 마이그레이션, PROD 적용 순서를 정의한다.

### `docs/sheet-restructure-checklist.md`

시트 구조 개편 작업 체크리스트다. 현재 체크된 항목은 없다. Phase 0의 GAS 전수조사부터 시작하는 상태다.

### `docs/sheet-restructure-context.md`

시트 구조 개편의 결정 배경이다. `CardDraws + BonusDraws` 통합, `config`를 `앱_설정`과 `미션_정의`로 분리, `Collection`과 BBB 관련 시트 분리 유지 같은 판단이 기록되어 있다.

## 7. 개발용 미리보기

### `preview_draw.html`

카드 뽑기 효과를 단독으로 테스트하는 개발용 HTML이다. 본 앱과 분리해서 카드팩, 공개 효과, 애니메이션 감각을 확인하는 용도다. 운영 경로의 핵심 파일은 아니지만 카드 이펙트 수정 시 참고 가치가 있다.

## 8. 이미지 자산 분석

이미지는 총 48개다. 사용 목적별로 나누면 다음과 같다.

### 로고와 PWA 아이콘

| 파일 | 용도 |
|---|---|
| `BEYONDUS2.png` | 메인 히어로 로고 |
| `hc_logo_png1.png` | 상단바 홈 로고 |
| `hc_logo_png2.png` | 스플래시, 인증, H&P 빈 상태 로고 |
| `pabicon.png`, `pabicon_180.png`, `pabicon_192.png`, `pabicon_512.png` | favicon, apple touch icon, PWA 아이콘 |
| `pabicon_maskable_192.png`, `pabicon_maskable_512.png` | maskable PWA 아이콘 |
| `pabicon_large.png` | 현재 코드 참조 없음 |

### 히어로와 안내 일러스트

| 파일 | 용도 |
|---|---|
| `hc_illust1.png` | 서비스 워커 캐시 대상, 현재 화면 직접 참조는 적음 |
| `hc_illust2.png` | 미션 진행률 카드 장식 |
| `hc_illust4.png` | 미션 히어로 장식 |
| `hc_illust5.png` | 문서상 히어로 자산, 현재 참조는 제한적 |
| `hc_illust3.png` | 현재 코드 참조 없음 |
| `sheep.png` | UI 장식 또는 과거 자산 |

### 카드 관련 자산

| 파일 | 용도 |
|---|---|
| `앤카드팩디자인배경제거.png` | 카드팩 이미지와 CSS mask |
| `앤카드뒷면최최종.png` | 현재 카드 뒷면 CSS 이미지 |
| `앤카드뒷면최종.png`, `앤카드뒷면.png` | 캐시 또는 과거 카드 뒷면 자산 |
| `앤뒷모습.png`, `앤수배.png` | 미획득 카드 실루엣과 히든 카드 잠김 표시 |
| `앤카드사랑최최종.png`부터 `앤카드절제최최종.png` | 실제 앱에서 쓰는 일반 카드 9종 |
| `히든.png` | 히든 카드 |

큰 원본 카드 이미지(`사랑.png`, `양선.png`, `오래참음.png`, `온유.png`, `자비.png`, `충성.png`, `화평.png`, `희락.png`, `절제.png`, `히든.png`)는 대부분 2787x4439 고해상도다. 이 중 일반 카드 원본 8개는 현재 코드 직접 참조가 없고 용량이 매우 크다. `사랑.png`, `절제.png`, `히든.png`은 파일명으로는 참조가 잡히지만 앱은 주로 `앤카드...최최종.png` 축소본과 `히든.png`을 사용한다.

### H&P와 현장미션 자산

| 파일 | 용도 |
|---|---|
| `h&p익명.jpeg` | 앱의 H&P 익명 카드 이미지 |
| `Hold&Pray.jpeg` | H&P 원본 또는 대체 카드 이미지 |
| `천로역정맵.png` | BBB 현장 미션 지도 |

### 요일 캐릭터

| 파일 | 용도 |
|---|---|
| `월요일앤.png`, `수요일앤.png`, `금요일앤.png`, `일요일앤.png` | 주간 달력 체크 표시 장식 |
| `요일별.png`, `일요일별.png` | 과거 또는 보조 요일 자산 |

## 9. 음악 자산 분석

음악 파일은 총 10개이고 모두 `app.js`의 `SFX_FILES`에서 참조된다.

| 파일 | 용도 |
|---|---|
| `카드 Main BGM.mp3` | 카드 뽑기 오버레이 BGM |
| `포장지 클릭.mp3` | 카드팩 클릭 |
| `포장지 개봉.mp3` | 카드팩 개봉 |
| `카드 등장.mp3` | 카드 등장 |
| `tap to flip.mp3` | 카드 뒤집기 안내 |
| `마우스 클릭.mp3` | 일반 클릭음 |
| `카드회전.mp3` | 카드 회전 |
| `카드 깜빡.mp3` | 반짝임 효과 |
| `일반 카드 공개.mp3` | 일반 카드 공개 |
| `히든 카드 공개.mp3` | 히든 카드 공개 |

## 10. 현재 위험 지점

1. `Apps_Script`의 관리자 비밀번호가 하드코딩되어 있다.
2. 사용자 비밀번호가 현재 코드상 평문으로 저장되고 비교된다.
3. `HOLD_PRAY_ENTRIES`에 실제 개인 기도제목이 코드 안에 들어 있다.
4. `admin.html`은 PROD GAS URL 고정에 `devMode=true`를 붙이는 구조라, DEV GAS와 PROD GAS 분리 정책을 다시 확인해야 한다.
5. GAS의 시트 접근이 고정 이름과 숫자 컬럼 인덱스에 크게 의존한다.
6. `CLAUDE.md`와 현재 코드가 일부 다르다.
7. 대용량 원본 이미지가 함께 배포될 수 있어 Pages 전송량과 저장소 크기에 부담이 있다.
8. Firestore 보안 규칙 만료 항목이 문서상 남아 있어 실제 운영 상태 확인이 필요하다.

## 11. 시트 구조 개편 관점의 즉시 작업 순서

현재 `docs/sheet-restructure-*` 문서는 Phase 0 시작 전 상태다. 실제로 이어서 하려면 다음 순서가 좋다.

1. `Apps_Script`의 `getSheetByName`, `getRange`, `appendRow`, `getValues`, `setValues` 사용처를 시트별로 표로 정리한다.
2. 실제 현재 시트 헤더를 `Apps_Script` 생성 함수 기준으로 먼저 복원한다.
3. `BBBMessages`와 `BBBPhotos`처럼 문서와 실제 코드의 시트명 차이를 정리한다.
4. `SHEET_NAMES` 상수와 `getColumns(sheet)` 헬퍼를 도입하기 전, `Users`, `raw_checkins`, `Collection`, `Trades`부터 컬럼 의존도를 분리한다.
5. 비밀번호와 H&P 개인정보 데이터의 보관 방식을 시트 구조 개편과 별도 보안 작업으로 분리해 추적한다.

