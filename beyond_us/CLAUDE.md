# Beyond Us — CLAUDE.md

> AI 어시스턴트용 프로젝트 참조 문서. (2026-05-05 갱신)

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
   - 형식: `YYYYMMDD` (예: `20260505`). 같은 날 여러 번 배포 시 `20260505b`, `20260505c` 등 suffix 사용.
   - **둘 중 하나만 바꾸면 무한 reload 루프 또는 캐시 갱신 불가** → 반드시 함께 수정.
6. **Git 워크플로우 준수** — 절대 main 브랜치에서 직접 작업 금지 (8장 참고).

---

## 1. 프로젝트 개요

2026 청년교구 수련회 준비를 위한 통합 앱:
- 사전미션 체크 / EN카드 컬렉션·뽑기·교환 / Hold & Pray / 채팅방 / 비밀친구(BBB) / QnA / 공지사항 / 개발자 문의

단일 `index.html` 파일 + GAS REST API + Firebase Firestore(채팅) 구조. GitHub Pages 배포. PWA 지원.

- **서비스 URL**: `https://chwja3.github.io/website/beyond_us/`
- **어드민**: `https://chwja3.github.io/website/beyond_us/admin.html`
- **참가 인원**: 약 250명
- **앱 정식 오픈**: 2026-05-10 (config B4 `app_open_date`)
- **수련회 일정**: 2026-05-17(일) — 실물 카드 수령일

---

## 2. 기술 스택

| 영역 | 기술 |
|------|------|
| 프론트엔드 | Vanilla JS + CSS (단일 `index.html`) |
| 메인 백엔드 | Google Apps Script (REST API) |
| 실시간 채팅 백엔드 | Firebase Firestore (Spark 무료 플랜) |
| 데이터 저장 | Google Sheets (메인), Firestore (채팅), Drive (이미지 업로드) |
| 배포 | GitHub Pages (`main` 브랜치) |
| 부가 인프라 | Cloudflare Workers/Pages (`wrangler.jsonc` — 미사용) |
| 클라이언트 상태 | `localStorage` (`beyondus_*` 키들) |
| 외부 라이브러리 | GSAP 3.12.5, Firebase v9 compat |

---

## 3. 파일 구조

```
website/
├── index.html               # 루트 — beyond_us/로 리다이렉트
├── wrangler.jsonc           # Cloudflare Workers/Pages 설정
└── beyond_us/
    ├── index.html           # 앱 전체 (HTML + CSS + JS)
    ├── admin.html           # 관리자 페이지
    ├── manifest.json        # PWA 홈화면 추가 설정
    ├── sw.js                # 서비스 워커 (오프라인 캐시 + 네트워크 우선)
    ├── version.txt          # 앱 버전 문자열 (배포 시 동기화 필수)
    ├── Apps_Script          # GAS 소스 (편집 후 직접 배포 필요)
    ├── config_sheets/       # 주차별 미션 TSV (w1~w6.tsv)
    ├── 사전미션*.txt        # 사전미션 텍스트
    ├── preview_draw.html    # 카드 이펙트 미리보기 (개발용)
    ├── CLAUDE.md            # ← 이 문서
    └── images/
```

---

## 4. 백엔드

### 4.1 Google Apps Script (메인 API)

- **SPREADSHEET_ID**: `1tlCozEXN8w2y9QqsEjUwffSuLr71edy2YOEJumy9e8Q`
- **API URL**: `https://script.google.com/macros/s/AKfycbxwpRSDeXLxaLzvmfJj7zSSTmG0qPykJw_eu-NjtKpLEpgIDyHU3Po3qG5Hl-lg6iTtJg/exec`
  - 재배포 시 URL이 바뀌면 `index.html` + `admin.html` 양쪽 `API_BASE` **동시 갱신 필수**.

#### 시트 구성

| 시트명 | 용도 |
|--------|------|
| `config` | 주차별 미션 정의(8행 단위 블록), B1=현재 주차, B4=app_open_date |
| `raw_checkins` | 모든 미션 제출 이력 |
| `Users` | 회원 정보 (닉네임/PW/교구/이름/isStaff) |
| `CardDraws` | 카드 뽑기 이력 |
| `Collection` | 사용자별 카드 보유 현황 + 응모권 누계 |
| `BonusDraws` | 추가 뽑기권 지급 이력 (H&P 정답·H&P 카운트 보상 등) |
| `HoldPray` | H&P 기도제목 (랜덤 노출 + 이름 빈칸 채우기) |
| `Trades` | 카드 교환 요청·수락·기도 |
| `BBB` | 비밀친구 매칭 (4단계 체인) |
| `BBB_Messages` | 비밀친구 익명 메시지 |
| `BBB_Photos` | 비밀친구 사진 업로드 |
| `Notices` | 공지사항 (이미지 업로드 지원) |
| `Inquiries` | 개발자 문의 (CRUD + 답글) |

#### Action 목록

**GET (`doGet`)**
| action | 설명 |
|--------|------|
| `dashboard` | 체크 현황·통계·탭설정 조회 |
| `userStatus` | 이번 주 제출 여부 + 보유 카드 + 뽑기권 |
| `getUsers` | 전체 유저 목록 (adminPw 필요) |
| `getTabSettings` | 탭 활성화 설정 (adminPw) |
| `getCurrentWeek` | 현재 미션 주차 (adminPw) |
| `getMissionConfig` | 주차별 미션 (adminPw) |
| `getCardStats` | 카드 뽑기 통계 (adminPw) |
| `getNotices` | 공지사항 목록 |
| `getInquiries` | 개발자 문의 목록 |
| `findNickname` | 이름+교구로 닉네임 조회 (비번 찾기용) |
| `getHoldPray` | 이번 주 H&P 카드 3장 (계정별 다른 조합) |
| `getPublicCollection` | 공개 컬렉션 (다른 유저 카드 보기) |
| `getTrades` | 내 교환 요청 목록 |
| `getAdminTrades` | 전체 교환 현황 (adminPw) |
| `getBBB` | 내 비밀친구 정보 (사진/추측 결과/메시지함) |
| `getBBBMessages` | 내가 받은 익명 메시지 |
| `adminGetBBB` | 전체 BBB 매칭 현황 (adminPw) |
| `migrateCardDrawsToCollection` | CardDraws → Collection 마이그레이션 (1회성) |

**POST (`doPost`)**
| action | 설명 |
|--------|------|
| `submit` | 미션 항목별 제출 |
| `drawCard` | EN카드 뽑기 (이월 뽑기권 차감, `isNew` 반환) |
| `register` / `login` / `resetPassword` | 회원 인증 |
| `adminLogin` / `adminResetPassword` | 어드민 인증 |
| `submitHoldPrayGuess` | H&P 이름 정답 제출 |
| `postInquiry` / `editInquiry` / `deleteInquiry` / `replyInquiry` | 문의 CRUD |
| `setMissionConfig` / `setCurrentWeek` / `setTabSettings` | 어드민 설정 |
| `postNotice` / `editNotice` / `deleteNotice` | 공지 CRUD (이미지 Drive 업로드) |
| `requestTrade` / `acceptTrade` / `rejectTrade` / `cancelTrade` / `prayForTrade` | 카드 교환 |
| `guessBBBSecret` / `sendBBBMessage` / `uploadBBBPhoto` | 비밀친구 |
| `adminSetupBBBMatching` / `adminWriteBBBRows` / `adminSetBBBMessageOpen` | BBB 어드민 |
| `adminRebuildCollection` / `adminSetupRawHeader` / `adminBackfillRawCols` | 데이터 정비 |

### 4.2 Firebase Firestore (채팅방 전용)

- **프로젝트 ID**: `agc-treat`
- **컬렉션**: `messages`
- **메시지 스키마**: `{ nickname: string, parish: string, text: string, createdAt: serverTimestamp }`
- **SDK**: v9 compat (CDN)
- **보안 규칙 (현재)**: 테스트 모드 — `allow read, write: if request.time < timestamp.date(2026, 5, 24);`
- **만료 전 필수 작업**: 닉네임 검증·rate limit 등 보안 규칙 강화

### 4.3 PWA (홈화면 추가 + 오프라인 + 강제 갱신)

- **`manifest.json`**: 192/512 아이콘, `display: standalone`, `purpose: "any"`
- **`sw.js`**: 캐시 버전 (`beyondus-vN`) + index.html은 네트워크 우선
- **버전 체크**: 진입 시 `version.txt`를 `cache: 'no-store'`로 fetch → `APP_VERSION`과 다르면 `location.reload(true)`
- **설치 가이드**: Coming Soon 화면에 OS/브라우저 자동 감지

---

## 5. 주요 정책

### 인증
- 닉네임=ID, 비밀번호 해시 저장, 자동 로그인(localStorage 캐시)
- **비밀번호 찾기**: 이름+교구 → 매칭되는 닉네임(들) 표시 → 닉네임 선택 → 임시 비번 발급 (동명이인 지원)
- 서버 검증 실패 시 `beyondus_*` 키 전체 클리어

### 라우팅
- **isStaff**: `Users` F열 TRUE → 운영진 (앱 즉시 진입 가능)
- **shouldEnterApp(isStaff, appOpenDate)**: 운영진 또는 오늘 ≥ `config B4` 이면 앱 진입, 아니면 Coming Soon

### 미션
- 주차별 6개 항목, 항목별 개별 제출
- 날짜 단위 저장: `beyondus_submitted_YYYY-MM-DD`
- **즉시 반영 (optimistic update)**: 제출 직후 점수/캘린더/버튼 갱신
- `loadUserStatus`로 서버 이력 머지 (다른 기기 동기화)
- **주차 점수 집계**: `weekTitle` 기준 (캘린더 주가 바뀌어도 같은 주차로 처리)
- **config 시트**: 8행 단위 블록, `startRow = (week-1)*8+5`, 항목 6개
- config 갱신: `Apps_Script`의 `setupAllWeeks()` 실행
- **주차 자동 전환은 미구현** — 어드민이 `setCurrentWeek` 수동 호출

### EN카드
- **종류**: 온라인 일반 9종(성령의 열매), 현장 카드, 히든 카드
- **뽑기권 시스템**: 주차 자격 달성 + 이월 + H&P 보너스 (BonusDraws 시트)
- 뽑기권 0이면 뽑기 버튼 비활성화, 헤더 🎫 배지로 표시
- `drawCard` 응답에 `isNew` 포함 — 신규/중복 이펙트 분기
- **컬렉션 미획득 표시**: `앤뒷모습.png` 통일 실루엣
- **실물 카드 수령일**: 5/17(일) 수련회 당일

### 카드 교환 (Trade)
- 다른 유저의 공개 컬렉션에서 카드 → 교환 요청
- 상대방이 수락/거절/만료 처리
- 제3자가 "기도(prayForTrade)" 가능 — 응원 카운트
- 시트: `Trades`, 만료 자동 처리: `_expireOldTrades`

### Hold & Pray (H&P)
- 매주 다른 사람의 기도제목 **3장 캐러셀** 노출 (계정별 다른 조합, hash 기반)
- 이름 빈칸 채우기 — 정답 시 이름 고정 표시
- **3장 모두 익명일 경우 마지막 카드 비익명으로 자동 교체**
- 정답 시 보상: w3·w6 주차에 뽑기권 지급
- 폰트: Nanum Pen Script
- 117명 기도제목 (초등부 제외)

### 비밀친구 (BBB = Buddy Beyond Buddy)
- 4단계 체인 매칭 (`adminSetupBBBMatching`)
- 익명 메시지 (admin 토글로 입력창 오픈/닫힘)
- 사진 업로드 (Drive)
- 정답 추측: 누구인지 맞추기 (`guessBBBSecret`)

### 채팅방
- 로그인 상태에서만 메시지 입력
- `parish`(교구) 뱃지 표시, 본인/타인 좌우 분리
- `limitToLast(100)` (페이지네이션 미구현)

### QnA / 도움말
- **QnA 섹션** (`data-section="faq"`): 검색 기능 + 미션/카드/H&P FAQ
- **페이지별 도움말 툴팁(?)**: 미션·뽑기·컬렉션·H&P 각 페이지에 맥락 안내

### 테스트 모드
- URL에 `?test=1` 추가 시 GAS 검증 스킵

---

## 6. 카드 뽑기 씬 구조

카드 뽑기 오버레이(`#drawOverlay`)의 DOM/레이아웃:

```
#drawOverlay (position:fixed; inset:0; flex column center)
├── #starBg
├── .draw-close-btn
├── #sceneWrap (280×440px; position:relative; z-index:2)
│   ├── #sceneGlow
│   ├── #effectsLayer
│   │   ├── #flashEl, #ringEl, #ringEl2, #ringEl3
│   │   ├── #cardBeam (수평 황금 잔광)
│   │   ├── #cardBeamCore (수평 코어 라인)
│   │   ├── #cardBeamV (세로 광선)
│   │   └── #particleLayer (별/불씨 파티클)
│   ├── #carouselLayer (팩 선택 캐러셀)
│   ├── #packLayer (팩 뜯기 애니메이션)
│   └── #cardLayer
│       ├── #cardGlow (카드 후광)
│       ├── #flipHint (Tap to flip)
│       ├── #cardTrigger (전체 회전 wrapper)
│       │   └── perspective wrapper
│       │       ├── #cardInner (preserve-3d)
│       │       │   ├── .card-face.card-back
│       │       │   └── .card-face.card-front#cardFace
│       │       └── #cardFlipShine (overflow:hidden 클리핑 안)
│       └── #cardLoadingHint
└── #settleActions (position:absolute; bottom:48px)
```

### 핵심 CSS 주의

- **`overflow:hidden` + `transform-style:preserve-3d` 동시 사용 불가**
- **`#cardFlipShine`는 반드시 `overflow:hidden` 클리핑 div 안에**
- **`#settleActions`는 `#cardLayer` 안에 두면 안 됨** (flex 재정렬 버그)
- **`#flipHint`는 `position:absolute; top:-36px`** (scale:1.82 보정)

### 카드 애니메이션 단계 (현재 흐름)

| 단계 | drawState | 설명 |
|------|-----------|------|
| 팩 뜯기 | `card_back_rise` | 팩 분리 + 카드 등장 |
| tlB | `card_back_wait` | 카드 등장(y:128→0, scale:1.56→1.82) — **0.46s 후 클릭 가능** |
| 클릭 | `card_flip_reveal` | 빙글빙글 시작 (rotateY 0→1800, 3s power3.out 감속) + `twinkleGoldStars` 배경 반짝임 |
| 스핀 onComplete | — | `tlC` 시작 — 카드 플립 + 십자 빔 + 후광 |
| tlC onComplete | `card_front_settle` | settleActions 표시 + 후광 펄스 + shimmer 루프 |

### 신규/중복 이펙트 분기 (`drawIsNew`)

| 요소 | 신규 (`isNew=true`) | 중복 |
|------|---------------------|------|
| `#cardGlow.glow-new` | 황금/주황 강한 후광 | `glow-dup` 은은한 회색 |
| 십자 빔 (3레이어) | tlC 0.62에 폭발 → 1.6s 잔광 | 없음 |
| 배경 별 | 50개 금색 별 트윙클 (3~4초) | 없음 |
| 임팩트 진동 | `#cardTrigger` x:3 흔들림 | 없음 |
| 펄스 | 강하게 (opacity 0.95, scale 1.80) | 은은하게 |

---

## 7. 이미지 자산

| 파일 | 용도 |
|------|------|
| `images/앤카드뒷면.png` / `앤카드뒷면최종.png` | 카드 뒷면 |
| `images/앤카드팩디자인배경제거.png` | 카드 팩 |
| `images/BEYONDUS2.png` | 메인 로고 |
| `images/hc_illust1.png` ~ `hc_illust5.png` | 히어로 일러스트 |
| `images/hc_logo_png1.png` / `hc_logo_png2.png` | 로고 |
| `images/pabicon.png` / `pabicon_192.png` / `pabicon_512.png` / `pabicon_180.png` | 파비콘 + PWA 아이콘 |
| `images/sheep.png` | 양 일러스트 |
| `images/요일별.png` / `일요일별.png` / `월·수·금·일요일앤.png` | 요일 캐릭터 |
| `images/앤뒷모습.png` / `앤수배.png` | 미획득 실루엣 |
| `images/사랑.png`~`절제.png`, `히든.png` | 9개 성령의 열매 + 히든 |
| `images/Hold&Pray.jpeg` / `h&p익명.jpeg` | H&P 카드 |

### 주의
- `앤카드뒷면.png` 투명 배경 PNG — `overflow:hidden`으로 클리핑 안 됨
- `.spirit-card`와 `.card-face`의 `border-radius` 일치 (22px)

---

## 8. Git 협업 워크플로우

> 다른 워커와 함께 작업하므로 반드시 브랜치 전략 준수.

**절대 main 브랜치에서 직접 작업 금지.**

### 작업 시작 전 (매번)
```bash
git checkout main
git pull origin main
```

### 작업 순서
```bash
git checkout -b feature/작업-이름
# 작업 후
git add 파일명
git commit -m "feat: 작업 내용"
git fetch origin main
git rebase origin/main   # 충돌 여기서 해결
git push origin feature/작업-이름
# PR은 GitHub 웹에서 생성
```

### 머지 충돌 주의
- `version.txt` / `APP_VERSION`은 충돌 빈발 — dev 쪽 버전으로 정리
- 충돌 마커(`<<<<<<<`)가 `index.html`에 남으면 `Uncaught SyntaxError` 발생

---

## 9. 드로어 / 섹션

### 현재 드로어 메뉴 순서
`공지사항 → 사전미션 → Hold & Pray → 카드 컬렉션 → 현장미션 → 채팅방 → QnA → 개발자 문의`

### SECTION_IDS 매핑
| key | data-section | 라벨 | 비고 |
|-----|--------------|------|------|
| `notice` | notice | 공지사항 | 알림 점 표시 |
| `mission` | mission | 사전미션 | 홈 (기본) |
| `prayer` | prayer | Hold & Pray | 3장 캐러셀 |
| `collection` | collection | 카드 컬렉션 | 교환 알림 점 |
| `secret` | secret | 현장미션 | (구 비밀친구 → 현장미션으로 라벨 변경) |
| `chat` | chat | 채팅방 | (구 단톡방) |
| `faq` | faq | QnA | 검색 가능 |
| `inquiry` | inquiry | 개발자 문의 | |

---

## 10. 카드 교환 (Trade)

### 흐름
1. 컬렉션 → 다른 유저 컬렉션 보기 (`getPublicCollection`)
2. 교환 요청 (`requestTrade`) — 내 카드 ↔ 상대 카드
3. 상대방이 수락(`acceptTrade`) / 거절(`rejectTrade`) / 만료
4. 본인이 취소(`cancelTrade`) 가능
5. 제3자가 기도 누르기(`prayForTrade`) — 응원 카운트
6. 만료 자동 처리: `_expireOldTrades`

### 시트
- `Trades`: id, 요청자, 대상, 줄카드, 받을카드, 상태(pending/accepted/rejected/cancelled/expired), 생성일, 처리일

### 어드민
- `getAdminTrades` — 전체 교환 현황 조회

---

## 11. 비밀친구 (BBB)

### 매칭
- 4단계 체인: A→B→C→D→A 형태로 무작위 묶음
- `adminSetupBBBMatching` — 어드민이 일괄 셋업
- `_shuffle` 으로 배열 섞기

### 동작
- `getBBB(userId)` — 내가 응원해야 할 친구 정보(닉네임 비공개) + 사진 + 추측 결과
- `guessBBBSecret` — 누구인지 맞추기
- `sendBBBMessage` — 익명 메시지 보내기 (어드민 토글로 입력창 오픈/닫힘)
- `getBBBMessages` — 내가 받은 메시지함
- `uploadBBBPhoto` — Drive 사진 업로드

### 시트
- `BBB`: 매칭 정보
- `BBB_Messages`: 익명 메시지
- `BBB_Photos`: 업로드 사진

### 어드민
- `adminGetBBB` — 전체 매칭 현황
- `adminSetBBBMessageOpen` — 메시지 입력창 오픈/닫힘 토글

---

## 12. Hold & Pray (H&P)

### 구조
- 드로어 메뉴: `Hold & Pray` (`data-section="prayer"`)
- 진입 시 `loadHoldPray()` → GAS `getHoldPray?weekKey=&nickname=`
- Coming Soon 티저에서도 `loadHoldPrayPreview()`로 노출

### 동작
1. 주차 키 + 닉네임으로 GAS에 요청 → 계정별로 다른 **3장** 응답
2. 캐러셀로 좌우 스와이프 (모바일+마우스 드래그)
3. 양쪽에 화살표 오버레이 배치
4. 각 카드에서 이름 + 교구 입력 → `submitHoldPrayGuess`
5. 정답 시 이름 고정 표시
6. 3장 모두 익명일 경우 마지막 카드 비익명으로 자동 교체
7. 정답 보상: w3·w6 주차에 뽑기권 지급 (`BonusDraws`)
8. 힌트 버튼: 문의 보내기 가능 (Inquiries 시트)

### 자산
- 카드 이미지: `images/h&p익명.jpeg`, `images/Hold&Pray.jpeg`
- 폰트: Nanum Pen Script (Google Fonts)

---

## 13. 채팅방 (Firebase Firestore)

### 구조
- 드로어 메뉴: `채팅방` (`data-section="chat"`)
- 섹션 ID: `#sectionChat` (`height: calc(100vh - 56px)`, flex column)
- 입력바: `#chatInput`, `#chatSendBtn`

### 동작
1. `switchSection('chat')` → `initChat()` → `ensureFirebase()`
2. `messages` 컬렉션 `orderBy('createdAt','asc').limitToLast(100)` 구독
3. `onSnapshot.docChanges()`에서 `type==='added'`만 렌더 (날짜 라벨 자동)
4. 다른 섹션 이동 시 `teardownChat()`

### 메시지 렌더
- 본인: 우측 정렬, 닉네임 미표시
- 타인: 좌측 정렬, 교구 뱃지 + 닉네임
- 시간: `H:MM`
- 날짜 변경 시 `.chat-date-divider` 자동 삽입

### 한계
- `limitToLast(100)`만 (페이지네이션 미구현)
- 메시지 수정/삭제/신고 미구현
- 보안 규칙 만료(2026-05-24) 후 작동 중지

---

## 14. 기능별 함수 인덱스

> 줄번호는 변동 가능 — 함수명으로 검색.

### 인증 / 세션 / 라우팅
| 기능 | 함수 |
|------|------|
| 자동 로그인 | `autoLogin()` |
| 앱 진입 자격 | `shouldEnterApp(isStaff, appOpenDate)` |
| Coming Soon | `showComingSoon()` |
| 인증 화면 | `showAuth(pane)` / `switchAuthPane(pane)` |
| 로그인 정보 저장 | `saveAuth(nickname, password, parish)` |
| 스플래시/앱 표시 | `hideSplash()` / `showApp()` |
| 유저 뱃지 | `updateUserBadge()` |
| 닉네임 찾기 | `findNickname` (GAS) — 이름+교구 → 닉네임 후보 |

### Coming Soon / PWA
| 기능 | 함수 |
|------|------|
| 버전 체크 | IIFE `checkVersion()` |
| 캐러셀 | `csGoTo(idx)` / `csStartAuto()` / `csStopAuto()` |
| 스와이프 | `onStart(x)` / `onEnd(x)` |
| 브라우저 감지 | `detectBrowser()` / `renderBrowserStatus()` |
| 설치 가이드 탭 | `csOsTab` / `csBrowserTab` |
| 설치 배너 | `renderInstallBanner()` |
| H&P 티저 | `loadHoldPrayPreview()` |

### 미션
| 기능 | 함수 |
|------|------|
| 주차/오늘 키 | `getWeekKey()` / `getTodayKey()` |
| 제출 항목 조회/저장 | `getSubmittedToday()` / `saveSubmittedItems(items)` |
| 체크 UI 갱신 | `updateCheckUI(allItems)` |
| config 렌더 | `renderConfig(data)` |
| 진행률 | `renderProgress(total)` / `updateScoreProgress()` |
| 캘린더 | `renderWeekCal()` |
| 데이터 로드 | `fetchDashboard()` / `loadUserStatus()` / `loadAll()` |
| 탭 설정 | `applyTabSettings(data)` |

### EN카드 / 뽑기 / 컬렉션 / 교환
| 기능 | 함수 |
|------|------|
| 카드 상세 | `openCardDetail(cardId, cnt)` / `closeCardDetail()` |
| 카드 HTML | `makeCardHTML(card)` |
| 뽑기 섹션 | `renderDrawSection()` / `renderCollection()` |
| 뽑기 오버레이 | `openDrawOverlay()` / `closeDrawOverlay()` |
| 캐러셀 | `applyCarouselPositions()` |
| 클릭 활성화 | `enableRevealClick()` |
| 로딩 도트 | `startLoadingDots()` / `stopLoadingDots()` |
| 빛 효과 | `ensureRevealSparks()` / `resetRevealSparks()` / `burstRevealSparks(power)` |
| 별/빔 이펙트 | `twinkleGoldStars()` / `ensureDrawParticles()` / `resetDrawParticles()` |
| 카드 교환 | `requestTrade` / `acceptTrade` / `rejectTrade` / `cancelTrade` / `prayForTrade` (GAS) |

### Hold & Pray
| 기능 | 함수 |
|------|------|
| 로드 | `loadHoldPray()` |
| 렌더 (3장) | `renderHoldPrayCard(data)` |
| 티저 미리보기 | `loadHoldPrayPreview()` |
| 정답 제출 | `submitHoldPrayGuess` POST |

### 비밀친구 (BBB)
| 기능 | 함수 (GAS 위주) |
|------|------|
| 매칭 셋업 | `setupBBBMatching` |
| 정보 조회 | `getBBB(userId)` |
| 정답 추측 | `guessBBBSecret(body)` |
| 메시지 송수신 | `sendBBBMessage(body)` / `getBBBMessages(userId)` |
| 사진 업로드 | `uploadBBBPhoto(body)` |

### 공지 / 문의 / QnA
| 기능 | 함수 |
|------|------|
| 공지 fetch | `loadNotices()` |
| 공지 렌더 | `renderNoticeList(notices, seen)` |
| 본 ID | `getSeenIds()` / `saveSeenIds(ids)` / `markAllSeen()` |
| 알림 점 | `updateNoticeDot()` |
| 문의 fetch/렌더 | `loadInquiries()` / `renderInquiries(inquiries)` |
| 문의 CRUD | `startInquiryEdit(id)` / `confirmInquiryDelete(id)` / `saveInquiryEdit(id)` |

### 채팅방 (Firebase)
| 기능 | 함수 |
|------|------|
| 초기화 | `ensureFirebase()` |
| 메시지 빌드 | `buildBubble(doc)` |
| 시간/날짜 포맷 | `chatTimestamp(ts)` / `chatDateLabel(ts)` |
| 진입/정리 | `initChat()` / `teardownChat()` |

### 네비게이션 / UI
| 기능 | 함수 |
|------|------|
| 드로어 | `openDrawer()` / `closeDrawer()` |
| 섹션 전환 | `switchSection(name)` |
| HTML 이스케이프 | `escHtml(s)` |
| 링크 변환 | `linkify(s)` (URL → `<a>`) |

---

## 15. 향후 작업 (Pending)

### 5/10 OPEN 전 (긴급)
- [x] **캘린더 동기화 버그** — `fix/calendar-sync-todayIndices` PR로 해결
- [x] **컬렉션 중복 보유 시각화** — `openCardDetail`이 1장/2장/3장+ 부채꼴 시각화로 구현됨
- [ ] **기존 공지 → Q&A 탭 이전** (운영 작업)

### 백엔드 / 자동화
- [ ] **주차 자동 전환 (미구현)** — GAS `ScriptApp.newTrigger()` 시간 기반 트리거 필요. 현재 어드민 `setCurrentWeek` 수동 호출만 가능

### 게임 / 콘텐츠
- [ ] **컬렉션 보상 (응모권 시스템) 구현** — 9종 다 모으면? N장 모으면?
- [ ] **카드 공개 효과음 추가** — 신규(화려) / 중복(수수) MP3 준비 후 코드 연결
- [ ] **현장 미션 완료 시 미보유 카드만 노출** — 현장 카드 보상 로직
- [ ] **현장 카드 / 히든 카드 데이터 확정**
- [ ] **EN카드 팩·앞면·뒷면 실제 이미지로 교체**
- [ ] **물리카드 인쇄 발주** (5/17 수령 목표)

### 비밀친구 (BBB)
- [x] **명칭 확정**: B.B.B. = Buddy Beyond Buddy

### 보류 (Deferred)
- ⏸ **카드 장수 & 배포 정책** — 첫 2~3주 카드 풀리는 양상 보고 **8~9장 사이로 결정** 예정. 카드 확률 재검토(주차별 threshold)도 함께 처리

---

## 16. 최근 주요 변경 (2026-05-05 기준)

- 카드 이펙트 전면 개편: 무지개 광선 제거 → 황금 십자 빔 + 금색 별 트윙클
- 카드 클릭 흐름 변경: 뒷면 정지 대기 → 클릭 시 빙글빙글 (3s 감속) → 공개
- QnA 섹션 추가 + 검색 기능
- 페이지별 도움말 툴팁
- H&P 3장 캐러셀
- 기도제목 80→117명 확대
- 비밀번호 찾기 이름+교구 기반
- 공지 삭제 옵티미스틱 UI
- 실물 카드 수령일 5/17 확정
