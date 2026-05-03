# Beyond Us — CLAUDE.md

> AI 어시스턴트용 프로젝트 참조 문서.

---

## 작업 규칙 (MUST FOLLOW)

1. **코드 수정 전 반드시 정책/계획을 먼저 제안하고 유저 확인을 받을 것.**
   - 기능 추가·변경·버그 수정 모두 해당.
   - 계획 없이 바로 Edit/Write 도구를 실행하지 말 것.
2. **계획 제안 형식**: 변경할 파일, 변경 내용 요약, 예상 동작을 텍스트로 먼저 설명.
3. **유저가 "해줘" / "OK" / "ㅇㅇ" 등으로 명시적으로 승인한 후에만 수정 시작.**
4. **수정 전 관련 파일을 반드시 읽고 검토할 것.**
5. **배포 시 버전 동기화 필수** — `index.html` 변경을 포함한 모든 배포에서 아래 두 값을 **반드시 동일하게** 업데이트할 것.
   - `beyond_us/version.txt` (파일 내용)
   - `index.html` 스크립트 상단 `const APP_VERSION = '...'` 상수
   - 형식: `YYYYMMDD` (예: `20260428`). 같은 날 여러 번 배포 시 `20260428b`, `20260428c` 등 suffix 사용.
   - **둘 중 하나만 바꾸면 무한 reload 루프 또는 캐시 갱신 불가** → 반드시 함께 수정.

---

## 1. 프로젝트 개요

2026 청년교구 수련회 준비를 위한 실천 체크 + EN카드 컬렉션 + Hold & Pray + 단톡방 앱.
단일 `index.html` 파일로 구성되며 GitHub Pages로 배포, Google Apps Script(GAS)를 메인 백엔드, Firebase Firestore를 실시간 채팅 백엔드로 사용.
PWA(홈화면 추가, 오프라인 캐시, 버전 체크 강제 갱신) 지원.

- **서비스 URL**: `https://chwja3.github.io/website/beyond_us/`
- **어드민**: `https://chwja3.github.io/website/beyond_us/admin.html`
- **참가 인원**: 약 250명

---

## 2. 기술 스택

| 영역 | 기술 |
|------|------|
| 프론트엔드 | Vanilla JS + CSS (단일 `index.html`) |
| 메인 백엔드 | Google Apps Script (REST API) |
| 실시간 채팅 백엔드 | Firebase Firestore (Spark 무료 플랜) |
| 데이터 저장 | Google Sheets, Firestore |
| 배포 | GitHub Pages (`main` 브랜치) |
| 부가 인프라 | Cloudflare Workers/Pages (`wrangler.jsonc` — 옵션) |
| 클라이언트 상태 | `localStorage` |
| 외부 라이브러리 | GSAP 3.12.5, Firebase v9 compat |

---

## 3. 파일 구조

```
website/
├── index.html               # 루트 — beyond_us/로 리다이렉트
├── wrangler.jsonc           # Cloudflare Workers/Pages 설정 (충돌 해결됨)
└── beyond_us/
    ├── index.html           # 앱 전체 (HTML + CSS + JS)
    ├── admin.html           # 관리자 페이지
    ├── manifest.json        # PWA 홈화면 추가 설정
    ├── sw.js                # 서비스 워커 (오프라인 캐시 + 네트워크 우선)
    ├── version.txt          # 앱 버전 문자열 (배포 시 동기화 필수)
    ├── Apps_Script          # GAS 소스 (편집 후 직접 배포 필요)
    ├── config_sheets/       # 주차별 미션 TSV (w1~w6.tsv)
    ├── 사전미션*.txt        # 사전미션 텍스트
    └── images/
```

---

## 4. 백엔드

### 4.1 Google Apps Script (메인 API)

- **SPREADSHEET_ID**: `1tlCozEXN8w2y9QqsEjUwffSuLr71edy2YOEJumy9e8Q`
- **시트**: `raw_checkins`, `config`, `CardDraws`, `Users`, `Notices`, `Inquiries`, `HoldPray`
- **API**: `https://script.google.com/macros/s/AKfycbxwpRSDeXLxaLzvmfJj7zSSTmG0qPykJw_eu-NjtKpLEpgIDyHU3Po3qG5Hl-lg6iTtJg/exec`
  - GAS 재배포 시 URL이 바뀌면 `index.html` + `admin.html` 양쪽 `API_BASE` 동시 갱신 필수.

| action | 메서드 | 설명 |
|--------|--------|------|
| `dashboard` | GET | 체크 현황·통계·탭설정 조회 |
| `userStatus` | GET | 이번 주 제출 여부 + 보유 카드 + 뽑기권 |
| `getUsers` | GET | 전체 유저 목록 (adminPw 필요) |
| `getTabSettings` | GET | 탭 활성화 설정 조회 (adminPw 필요) |
| `getCurrentWeek` | GET | 현재 미션 주차 조회 (adminPw 필요) |
| `getNotices` | GET | 공지사항 목록 |
| `getInquiries` | GET | 개발자 문의 목록 |
| `getHoldPray` | GET | 이번 주 H&P 기도제목 (계정별 다른 카드 노출) |
| `getMissionConfig` | GET | 주차별 미션 조회 (adminPw 필요) |
| `getCardStats` | GET | 카드 뽑기 통계 (adminPw 필요) |
| `submit` | POST | 항목별 미션 체크 제출 |
| `drawCard` | POST | EN카드 뽑기 (이월 뽑기권 차감) |
| `register` | POST | 회원가입 |
| `login` | POST | 로그인 |
| `resetPassword` | POST | 비밀번호 찾기 |
| `adminLogin` | POST | 어드민 로그인 |
| `adminResetPassword` | POST | 어드민 비밀번호 재설정 |
| `submitHoldPrayGuess` | POST | H&P 이름 맞추기 정답 제출 |
| `postInquiry` / `editInquiry` / `deleteInquiry` / `replyInquiry` | POST | 개발자 문의 CRUD |
| `setMissionConfig` | POST | 미션 설정 저장 (adminPw 필요) |
| `setCurrentWeek` | POST | 현재 주차 설정 (adminPw 필요) |
| `setTabSettings` | POST | 탭 활성화 설정 (adminPw 필요) |
| `postNotice` / `editNotice` / `deleteNotice` | POST | 공지사항 CRUD (adminPw 필요) |

### 4.2 Firebase Firestore (단톡방 전용)

- **프로젝트 ID**: `agc-treat`
- **컬렉션**: `messages`
- **메시지 스키마**: `{ nickname: string, parish: string, text: string, createdAt: serverTimestamp }`
- **SDK**: v9 compat (CDN 로드: `firebase-app-compat.js`, `firebase-firestore-compat.js`)
- **FIREBASE_CONFIG 위치**: `beyond_us/index.html` 스크립트 하단 (`/* ════ Firebase 단톡방 ════ */` 섹션)
- **보안 규칙 (현재)**: 테스트 모드 — `allow read, write: if request.time < timestamp.date(2026, 5, 24);`
- **만료 전 필수 작업**: 닉네임 검증·rate limit 등 보안 규칙 강화

### 4.3 Cloudflare Workers/Pages (옵션)

- **wrangler.jsonc**: 정적 자산 배포 설정 (`assets.directory: "."`, `compatibility_date: "2026-04-25"`)
- 머지 충돌 해결됨. 현재는 GitHub Pages가 메인 배포 채널, Cloudflare는 미사용.

### 4.4 PWA (홈화면 추가 + 오프라인 + 강제 갱신)

- **`manifest.json`**: 아이콘 192/512 (`pabicon_192.png`, `pabicon_512.png`), `display: standalone`, `purpose: "any"` (maskable 사용 시 짤림 발생 → 일반 any로 고정)
- **`sw.js`**: 캐시 버전 (`beyondus-vN`) + index.html은 네트워크 우선, 나머지 자산은 캐시 우선
- **버전 체크 (강제 갱신)**: `index.html` 진입 시 `version.txt`를 `cache: 'no-store'`로 fetch → `APP_VERSION` 상수와 다르면 `location.reload(true)`
  - **배포 시 `version.txt` + `APP_VERSION` 둘 다 갱신 필수** (작업 규칙 5번 참고)
- **설치 가이드**: Coming Soon 화면에 브라우저 자동 감지 후 OS별 설치 방법 표시 (`detectBrowser`, `renderBrowserStatus`)

---

## 5. 주요 정책

- **로그인**: 닉네임=ID, 자동 로그인(localStorage 캐시), 서버 검증 실패 시 `beyondus_` 키 전체 클리어
- **isStaff 라우팅 / Coming Soon**: `shouldEnterApp(isStaff, appOpenDate)` — 운영진(`Users` F열) 또는 오늘 ≥ `config B4 (app_open_date)` 일 때만 앱 진입, 그 외엔 Coming Soon 화면. config B4=`2026-05-10`
- **미션**: 주차별 6개 항목, 항목별 개별 제출, 날짜 단위 저장(`beyondus_submitted_YYYY-MM-DD`)
- **미션 제출 즉시 반영**: optimistic update — 제출 직후 점수/캘린더 체크/버튼 비활성화 즉시 갱신, 다른 기기에서 제출해도 `loadUserStatus`가 서버 이력으로 캘린더 동기화 (`todayIndices` 포함)
- **주차 점수 집계**: 미션 주차(`weekTitle`) 기준으로 집계 — 캘린더 주가 바뀌어도 미션 주차 정의가 바뀌지 않으면 같은 주로 처리
- **config 시트 구조**: 8행 단위 블록, `startRow = (week-1)*8+5`, 항목 6개
- **config 업데이트**: `Apps_Script`의 `setupAllWeeks()` 함수 실행
- **EN카드 뽑기권 이월**: 이전 주에 자격 달성했지만 뽑지 않은 경우 다음 주로 이월. 보유 뽑기권은 헤더 🎫 배지로 표시, 권 0이면 뽑기 버튼 비활성화
- **EN카드**: 온라인 일반 9종(뽑기), 현장 카드, 히든 카드 / 뽑기 기준은 주차별 threshold
- **컬렉션 미획득 표시**: `앤뒷모습.png` 통일 실루엣
- **Hold & Pray (H&P)**: 매주 다른 사람의 기도제목 1개를 랜덤 노출, 이름 빈칸 채우기 — 정답 시 이름 고정 표시 (정책 참고: 향후 정답 시 뽑기권 보상 검토)
- **단톡방**: 로그인 상태에서만 메시지 입력, `parish`(교구) 뱃지 표시, 본인/타인 메시지 좌우 분리
- **테스트 모드**: URL에 `?test=1` 추가 시 GAS 검증 스킵

---

## 6. 카드 뽑기 씬 구조 (중요)

카드 뽑기 오버레이(`#drawOverlay`)의 DOM/레이아웃 구조:

```
#drawOverlay (position:fixed; inset:0; flex column center)
├── #starBg
├── .draw-close-btn
├── #sceneWrap (280×440px; position:relative; z-index:2)
│   ├── #sceneGlow
│   ├── #effectsLayer (#flashEl, #ringEl)
│   ├── #carouselLayer (팩 선택 캐러셀, 3개 팩)
│   ├── #packLayer (팩 뜯기 애니메이션)
│   └── #cardLayer (position:absolute; inset:0; flex column center)
│       ├── #cardGlow (position:absolute — 후광, flex 흐름 밖)
│       ├── #flipHint (position:absolute; top:-36px; z-index:10 — 카드 위 안내문구)
│       ├── #cardTrigger (flex 흐름)
│       │   └── [perspective wrapper]
│       │       ├── #cardInner (transform-style:preserve-3d)
│       │       │   ├── .card-face.card-back > .card-face-back (뒷면 PNG)
│       │       │   └── .card-face.card-front#cardFace (앞면)
│       │       └── [overflow:hidden 클리핑 div; border-radius:22px]
│       │           └── #cardFlipShine (shimmer 효과)
│       └── #cardLoadingHint ("두 근 두 근 . . . !" 로딩 도트, 카드 등장 전 활성)
└── #settleActions (position:absolute; bottom:48px; z-index:10 — 컬렉션 버튼)
```

### 핵심 CSS 주의사항

- **`overflow:hidden` + `transform-style:preserve-3d` 동시 사용 불가** (스펙 충돌 — 3D flatten됨)
- **`#cardFlipShine`는 반드시 `overflow:hidden` 클리핑 div 안에 있어야 함** — GSAP `x:'155%'` 이동 시 카드 밖으로 삐져나오는 것을 막기 위함
- **`#settleActions`는 `#cardLayer` 안에 두면 안 됨** — display:none→flex 전환 시 flex 재정렬로 카드가 위로 이동하는 버그 발생
- **`#flipHint`는 `position:absolute; top:-36px`** — 카드 scale:1.82로 인해 레이아웃 박스 위로 시각적으로 튀어나옴
- **카드 대기 후광 펄스 제거됨** — `#cardGlow` 펄스 애니메이션 사용 안 함
- **카드 대기 흰색 외곽선 제거됨** — 대기 상태에서 깔끔하게 표시

### 카드 애니메이션 단계

| 단계 | 상태(`drawState`) | 설명 |
|------|-------------------|------|
| tlB  | `card_back_wait`  | 카드 등장 (y:128→-8, scale:1.56→1.82), 로딩 도트 정지 |
| enableRevealClick | `card_back_wait` | 힌트 표시, 클릭 활성화 |
| tlC (클릭 시) | `card_flip_reveal` | rotateY 0→106→194→180, shimmer sweep |
| onComplete | `card_front_settle` | settleActions 표시 |

- 카드 등장 전(`drawCard` API 대기 중): `startLoadingDots()` 호출, "두 근 두 근" → "두 근 두 근 . . . !" 5단계 순환
- 카드 클릭 시 `gsap.killTweensOf('#cardTrigger')` 후 `gsap.set({ y:-8 })` (float 위치 유지)
- tlC에서 scale 변경 없음 — 제자리 플립

---

## 7. 이미지 파일 현황

| 파일 | 용도 |
|------|------|
| `images/앤카드뒷면.png` / `앤카드뒷면최종.png` | 카드 뒷면 (투명 배경 PNG, 라운드 내장) |
| `images/앤카드팩디자인배경제거.png` | 카드 팩 디자인 |
| `images/BEYONDUS2.png` | 메인 히어로 Beyond Us 로고 (979×150) |
| `images/hc_illust1.png` ~ `hc_illust5.png` | 히어로/티저 일러스트 (양·교회 등) |
| `images/hc_logo_png1.png` / `hc_logo_png2.png` | 스플래시/로그인 로고 |
| `images/pabicon.png` | 파비콘 |
| `images/pabicon_192.png` / `pabicon_512.png` / `pabicon_180.png` | PWA 아이콘 (Android 192/512, iOS 180), `pabicon_large.png`도 존재 |
| `images/sheep.png` | 양 (보조 일러스트) |
| `images/요일별.png` / `일요일별.png` / `월·수·금·일요일앤.png` | 요일별 캐릭터 / 카드 팩 미니 |
| `images/앤뒷모습.png` / `images/앤수배.png` | 미획득 컬렉션 카드 실루엣/표시 이미지 |
| `images/사랑.png`~`절제.png`, `히든.png` | 9개 성령의 열매 카드 앞면 + 히든 |
| `images/Hold&Pray.jpeg` / `images/h&p익명.jpeg` | H&P 탭 카드 / 익명 기도자 이미지 |

### PNG 카드 관련 주의

- `images/앤카드뒷면.png`는 투명 배경 PNG — `overflow:hidden` 적용해도 PNG의 투명 픽셀은 그대로 보임 (레이아웃 박스 내부이므로 클리핑 안 됨)
- `.spirit-card`와 `.card-face`의 `border-radius`는 반드시 일치해야 함 (현재 22px)
- 미획득 카드 실루엣은 `앤뒷모습.png`로 통일됨 (개별 실루엣 미사용)

---

## 8. Git 협업 워크플로우

> 다른 워커와 함께 작업하므로 반드시 브랜치 전략 준수.

**절대 main 브랜치에서 직접 작업 금지.**

### 작업 시작 전 필수 (매번)

```bash
git checkout main
git pull origin main
```

### 작업 순서

```bash
# 1. 최신 main 받기 (위에서 완료)

# 2. 내 작업 브랜치 생성
git checkout -b feature/작업-이름

# 3. 작업 후 커밋 (기존대로)
git add 파일명
git commit -m "feat: 작업 내용"

# 4. 푸시 전 main 변경사항 반영 (핵심 — 충돌 여기서 해결)
git fetch origin main
git rebase origin/main

# 5. 브랜치 푸시
git push origin feature/작업-이름
# PR은 GitHub 웹에서 직접 생성 (gh CLI 미설치)
# https://github.com/chwja3/website/pull/new/feature/작업-이름
```

---

## 9. Hold & Pray (H&P) 탭

### 구조
- 드로어 메뉴: `Hold & Pray` (`data-section="prayer"`, 정식 명칭, 구 "손기도")
- 섹션 ID: `#sectionPrayer`
- 진입 시 `loadHoldPray()` 호출 → GAS `getHoldPray?weekKey=&nickname=` API
- Coming Soon 티저에서도 `loadHoldPrayPreview()`로 메인 슬라이드에 미리 노출

### 동작
1. 주차 키 + 닉네임으로 GAS에 요청 → 계정별로 다른 기도제목 1개 응답
2. `renderHoldPrayCard(data)`로 카드 렌더 — 기도내용 이미지 위 손글씨 폰트(Nanum Pen Script) 오버레이
3. 기도제목 작성자 이름은 빈칸 처리, 입력칸에 이름 + 교구 입력
4. 정답 제출: `submitHoldPrayGuess` POST — 정답 시 이름 고정 표시
5. 카드 하단: 말씀 구절(`.footer-note`, 이탤릭) + 홈 버튼

### 자산
- 카드 이미지: `images/h&p익명.jpeg` (익명 기도자 표지) / `images/Hold&Pray.jpeg`
- 폰트: Nanum Pen Script (Google Fonts) — 폰트 로드 완료 대기 후 카드 렌더

---

## 10. 단톡방 (Firebase Firestore)

### 구조
- 드로어 메뉴: `💬 단톡방` (`data-section="chat"`)
- 섹션 ID: `#sectionChat` (`height: calc(100vh - 56px)`, flex column)
- 입력바: `#chatInput`, `#chatSendBtn` (전송)

### 동작 흐름
1. `switchSection('chat')` → `initChat()` 호출
2. `ensureFirebase()`로 Firebase 앱 초기화 (싱글톤)
3. `localStorage.beyondus_nickname` 체크 — 없으면 안내 문구 표시 후 종료
4. `messages` 컬렉션에 `orderBy('createdAt','asc').limitToLast(100)` 구독
5. `onSnapshot` `docChanges()`에서 `type==='added'` 인 변경만 렌더 (날짜 라벨 자동 삽입)
6. 다른 섹션으로 이동 시 `teardownChat()` — `_chatUnsub()` 호출 + DOM 초기화

### 메시지 렌더 규칙
- **본인 메시지** (`data.nickname === beyondus_nickname`): 우측 정렬, 닉네임 미표시
- **타인 메시지**: 좌측 정렬, 교구 뱃지(`.chat-parish`) + 닉네임 표시
- 시간 표시: `H:MM` (`chatTimestamp`)
- 날짜 변경 시 `.chat-date-divider` 자동 삽입

### 한계
- `limitToLast(100)`로 최근 100개만 로드 (페이지네이션 미구현)
- 메시지 수정/삭제/신고 기능 없음
- 보안 규칙 만료(2026-05-24)되면 채팅 작동 중지

---

## 11. 기능별 함수 인덱스

`beyond_us/index.html` 내 주요 함수. 줄번호가 변동되어도 함수명으로 검색 가능.

### 인증 / 세션 / 라우팅
| 기능 | 함수 / 핸들러 |
|------|---------------|
| 자동 로그인 | `autoLogin()` |
| 앱 진입 자격 판정 | `shouldEnterApp(isStaff, appOpenDate)` |
| Coming Soon 화면 표시 | `showComingSoon()` |
| 인증 화면 표시 | `showAuth(pane)` |
| 인증 패널 전환 | `switchAuthPane(pane)` |
| 로그인 정보 저장 | `saveAuth(nickname, password, parish)` |
| 스플래시 숨김 | `hideSplash()` |
| 앱 화면 진입 | `showApp()` |
| 상단 유저 뱃지 갱신 | `updateUserBadge()` |
| 회원가입 | `#registerBtn` click (`action=register`) |
| 로그인 | `#loginBtn` click (`action=login`) |
| 비밀번호 재설정 | `#resetBtn` click (`action=resetPassword`) |
| 로그아웃 | 드로어 로그아웃 버튼 — `beyondus_*` localStorage 클리어 |

### Coming Soon / PWA 설치
| 기능 | 함수 |
|------|------|
| 버전 체크 (강제 갱신) | IIFE `checkVersion()` |
| Coming Soon 캐러셀 이동 | `csGoTo(idx)` / `csStartAuto()` / `csStopAuto()` |
| 스와이프/드래그 핸들러 | `onStart(x)` / `onEnd(x)` |
| 브라우저 자동 감지 | `detectBrowser()` / `renderBrowserStatus()` |
| 설치 가이드 OS/브라우저 탭 | `csOsTab(os, btn)` / `csBrowserTab(browser, btn)` |
| 설치 배너 렌더 | `renderInstallBanner()` |
| H&P 티저 미리보기 로드 | `loadHoldPrayPreview()` |

### 미션 (체크 / 제출)
| 기능 | 함수 |
|------|------|
| 주차 키 계산 | `getWeekKey()` |
| 오늘 키 | `getTodayKey()` |
| 오늘 제출 항목 조회 | `getSubmittedToday()` |
| 제출 항목 저장 | `saveSubmittedItems(items)` |
| 체크 UI 갱신 | `updateCheckUI(allItems)` |
| 미션 텍스트 렌더 | `renderItemText(text)` |
| config 렌더 | `renderConfig(data)` |
| 카운트 렌더 | `renderCounts(data)` |
| 진행률 렌더 | `renderProgress(total)` |
| 점수 진행 갱신 | `updateScoreProgress()` |
| 주차 캘린더 | `renderWeekCal()` |
| 대시보드 fetch | `fetchDashboard()` |
| 탭 설정 적용 | `applyTabSettings(data)` |
| 유저 상태 fetch | `loadUserStatus()` |
| 전체 데이터 로드 | `loadAll()` |
| 상태 메시지 표시 | `setStatus(msg, type)` |
| 오늘 체크 여부 | `hasCheckedToday()` |
| 체크 날짜 저장 | `saveCheckDate()` |

### EN카드 / 뽑기
| 기능 | 함수 |
|------|------|
| 카드 상세 열기 | `openCardDetail(cardId, cnt)` |
| 카드 상세 닫기 | `closeCardDetail()` |
| 카드 HTML 생성 | `makeCardHTML(card)` |
| 뽑기 섹션 렌더 | `renderDrawSection()` |
| 컬렉션 렌더 | `renderCollection()` |
| 뽑기 오버레이 열기 | `openDrawOverlay()` |
| 뽑기 오버레이 닫기 | `closeDrawOverlay()` |
| 캐러셀 위치 적용 | `applyCarouselPositions()` |
| 뒤집기 클릭 활성화 | `enableRevealClick()` |
| 로딩 도트 시작 | `startLoadingDots()` |
| 로딩 도트 정지 | `stopLoadingDots()` |
| 빛 효과 준비 | `ensureRevealSparks()` |
| 빛 효과 리셋 | `resetRevealSparks()` |
| 빛 효과 발사 | `burstRevealSparks(power)` |

### 공지사항
| 기능 | 함수 |
|------|------|
| 본 ID 조회 | `getSeenIds()` |
| 본 ID 저장 | `saveSeenIds(ids)` |
| 알림 점 갱신 | `updateNoticeDot()` |
| 모두 본 처리 | `markAllSeen()` |
| 공지 목록 렌더 | `renderNoticeList(notices, seen)` |
| 공지 fetch | `loadNotices()` |
| 날짜 포맷 | `formatNoticeDate(v)` |

### 개발자 문의
| 기능 | 함수 |
|------|------|
| 로그인 UI 갱신 | `updateInquiryLoginUI()` |
| 문의 fetch | `loadInquiries()` |
| 문의 렌더 | `renderInquiries(inquiries)` |
| 수정 시작 | `startInquiryEdit(id)` |
| 삭제 시작 | `startInquiryDelete(id)` |
| 삭제 확정 | `confirmInquiryDelete(id)` |
| 수정 저장 | `saveInquiryEdit(id)` |

### 단톡방 (Firebase)
| 기능 | 함수 |
|------|------|
| Firebase 초기화 | `ensureFirebase()` |
| 시간 포맷 | `chatTimestamp(ts)` |
| 날짜 라벨 | `chatDateLabel(ts)` |
| 메시지 버블 빌드 | `buildBubble(doc)` |
| 단톡방 진입 | `initChat()` |
| 단톡방 정리 | `teardownChat()` |

### Hold & Pray
| 기능 | 함수 |
|------|------|
| H&P 카드 로드 | `loadHoldPray()` |
| H&P 카드 렌더 | `renderHoldPrayCard(data)` |
| 티저용 미리보기 로드 | `loadHoldPrayPreview()` |
| 정답 제출 | `submitHoldPrayGuess` POST |

### 네비게이션 / UI
| 기능 | 함수 |
|------|------|
| 드로어 열기 | `openDrawer()` |
| 드로어 닫기 | `closeDrawer()` |
| 섹션 전환 | `switchSection(name)` |
| HTML 이스케이프 | `escHtml(s)` |

### 드로어 메뉴 순서 (현재)
`공지사항 → 미션 → Hold & Pray → 컬렉션 → 비밀친구 → 단톡방 → 개발자 문의`
(컬렉션 하단에 중보기도 버튼 별도 배치)

### SECTION_IDS (드로어 섹션 키)
`notice` / `mission` / `prayer` / `collection` / `secret` / `inquiry` / `chat`

---

## 12. 향후 작업 (Pending)

### 5/10 OPEN 전 (긴급)
- [ ] **앱(PWA) ↔ 웹(브라우저) 캘린더 동기화 버그** — 4월 4째주 박스에서 한쪽에서 체크한 게 다른 쪽에 반영 안 됨. 양쪽이 각자의 localStorage만 보고 있을 가능성 (서버 이력 머지 누락) — `loadUserStatus` / `saveSubmittedItems` / `getSubmittedIndices` 흐름 점검 필요
- [ ] **카드팩 고르는 화면(캐러셀) 로딩 시간 단축** — 이미지 프리로드 / GAS `drawCard` 응답 시간 개선
- [ ] **컬렉션 중복 보유 시 카드 상세에서 "N장 보유" 텍스트 대신 카드 병렬 시각화**

### 운영 (코드 작업 아님)
- [x] TF 제외 인원 Coming Soon 노출 — 코드 구현 완료. 시트 정리(`Users.isStaff` F열 운영진만 TRUE)만 남음

### 게임/콘텐츠
- [ ] **H&P 정답 보상**: 이름·교구 맞추면 뽑기권 지급 정책 확정 + 구현
- [ ] **H&P 빈칸 답 공유 기능**: 다른 사람이 뭐라고 썼는지 앱에서 볼 수 있도록
- [ ] **현장 미션 완료 시 그 사람이 미보유한 카드만 노출** — 현장 카드 보상 로직
- [ ] **카드 확률 계산 재검토** (등급별 / 주차별 threshold)
- [ ] 주차별 뽑기 횟수 정책 GAS 로직 (현재 주 1회 고정 + 이월 시스템)
- [ ] **현장 카드 / 히든 카드 데이터 확정 및 앱 반영**
- [ ] EN카드 팩·앞면·뒷면 실제 이미지로 교체
- [ ] 물리카드 인쇄 발주 (레드프린팅 + 프린팅팅)

### 비밀친구
- [x] **비밀친구 명칭 변경**: B.B.B. = Buddy Beyond Buddy (확정)
- [ ] **비밀친구 익명 메시지 기능** — 매일 22:00 또는 admin 토글로만 메시지 입력 오픈

### 인프라/보안
- [ ] **Firestore 보안 규칙 강화** — 5/24 만료 전 닉네임 검증·rate limit 룰 적용
- [ ] 단톡방 페이지네이션 (현재 `limitToLast(100)`만)
- [ ] 단톡방 메시지 신고/삭제/수정 기능
- [ ] (선택) Firebase Cloud Messaging 푸시 알림 검토
- [ ] Cloudflare Pages 배포 채널 활성화 검토 (현재 `https://website-78h.pages.dev/beyond_us/`도 살아있음)
