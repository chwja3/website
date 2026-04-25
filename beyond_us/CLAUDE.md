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

---

## 1. 프로젝트 개요

2026 청년교구 수련회 준비를 위한 실천 체크 + EN카드 컬렉션 + 단톡방 앱.
단일 `index.html` 파일로 구성되며 GitHub Pages로 배포, Google Apps Script(GAS)를 메인 백엔드, Firebase Firestore를 실시간 채팅 백엔드로 사용.

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
├── wrangler.jsonc           # Cloudflare Workers/Pages 설정
└── beyond_us/
    ├── index.html           # 앱 전체 (HTML + CSS + JS)
    ├── admin.html           # 관리자 페이지
    ├── manifest.json        # PWA 홈화면 추가 설정
    ├── Apps_Script          # GAS 소스 (편집 후 직접 배포 필요)
    ├── config_sheets/       # 주차별 미션 TSV (w1~w6.tsv)
    ├── 사전미션*.txt        # 사전미션 텍스트
    └── images/
```

---

## 4. 백엔드

### 4.1 Google Apps Script (메인 API)

- **SPREADSHEET_ID**: `1tlCozEXN8w2y9QqsEjUwffSuLr71edy2YOEJumy9e8Q`
- **시트**: `raw_checkins`, `config`, `CardDraws`, `Users`, `Notices`
- **API**: `https://script.google.com/macros/s/AKfycbwE1WmjS02tZh-jUJOqGEOBobAG73RGpQhxkM9vbgk4xBrq5C-UB8r6vx9lVftaZLAobQ/exec`

| action | 메서드 | 설명 |
|--------|--------|------|
| `dashboard` | GET | 체크 현황·통계·탭설정 조회 |
| `userStatus` | GET | 이번 주 제출 여부 + 보유 카드 |
| `getUsers` | GET | 전체 유저 목록 (adminPw 필요) |
| `getNotices` | GET | 공지사항 목록 |
| `getMissionConfig` | GET | 주차별 미션 조회 (adminPw 필요) |
| `submit` | POST | 항목별 미션 체크 제출 |
| `drawCard` | POST | EN카드 뽑기 |
| `register` | POST | 회원가입 |
| `login` | POST | 로그인 |
| `resetPassword` | POST | 비밀번호 찾기 |
| `adminLogin` | POST | 어드민 로그인 |
| `setMissionConfig` | POST | 미션 설정 저장 (adminPw 필요) |
| `setTabSettings` | POST | 탭 활성화 설정 (adminPw 필요) |
| `postNotice` | POST | 공지사항 등록 (adminPw 필요) |
| `deleteNotice` | POST | 공지사항 삭제 (adminPw 필요) |

### 4.2 Firebase Firestore (단톡방 전용)

- **프로젝트 ID**: `agc-treat`
- **컬렉션**: `messages`
- **메시지 스키마**: `{ nickname: string, parish: string, text: string, createdAt: serverTimestamp }`
- **SDK**: v9 compat (CDN 로드: `firebase-app-compat.js`, `firebase-firestore-compat.js`)
- **FIREBASE_CONFIG 위치**: `beyond_us/index.html` 스크립트 하단 (`/* ════ Firebase 단톡방 ════ */` 섹션)
- **보안 규칙 (현재)**: 테스트 모드 — `allow read, write: if request.time < timestamp.date(2026, 5, 24);`
- **만료 전 필수 작업**: 닉네임 검증·rate limit 등 보안 규칙 강화

### 4.3 Cloudflare Workers/Pages (옵션)

- **wrangler.jsonc**: 정적 자산 배포 설정 (`assets.directory: "."`)
- ⚠️ **현재 머지 충돌 마커가 남아있음** (`compatibility_date` 충돌) — 사용 전 해결 필요

---

## 5. 주요 정책

- **로그인**: 닉네임=ID, 자동 로그인(localStorage 캐시), 서버 검증 실패 시 `beyondus_` 키 전체 클리어
- **미션**: 주차별 6개 항목, 항목별 개별 제출, 날짜 단위 저장(`beyondus_submitted_YYYY-MM-DD`)
- **config 시트 구조**: 8행 단위 블록, `startRow = (week-1)*8+5`, 항목 6개
- **config 업데이트**: `Apps_Script`의 `setupAllWeeks()` 함수 실행
- **EN카드**: 온라인 일반 6종(뽑기), 현장 4종, 히든 2종 / 뽑기 기준은 주차별 threshold
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
| `images/앤카드뒷면.png` | 카드 뒷면 (투명 배경 PNG, 라운드 내장) |
| `images/BEYONDUS2.png` | 메인 히어로 Beyond Us 로고 (979×150) |
| `images/hc_illust4.png` | 메인 히어로 양 일러스트 |
| `images/hc_logo_png2.png` | 스플래시/로그인 로고 |
| `images/pabicon.png` | 앱 아이콘 |
| `images/월요일앤.png` | 캐러셀 인덱스 0번 팩 위 미니 카드 (요일별 캐릭터 중 하나) |
| `images/앤뒷모습.png` / `images/앤수배.png` | 미획득 컬렉션 카드 실루엣/표시 이미지 |

### PNG 카드 관련 주의

- `images/앤카드뒷면.png`는 투명 배경 PNG — `overflow:hidden` 적용해도 PNG의 투명 픽셀은 그대로 보임 (레이아웃 박스 내부이므로 클리핑 안 됨)
- `.spirit-card`와 `.card-face`의 `border-radius`는 반드시 일치해야 함 (현재 22px)
- 미획득 카드 실루엣은 `앤뒷모습.png`로 통일됨 (개별 실루엣 미사용)

---

## 8. 단톡방 (Firebase Firestore)

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

## 9. 기능별 함수 인덱스

`beyond_us/index.html` 내 주요 함수. 줄번호가 변동되어도 함수명으로 검색 가능.

### 인증 / 세션
| 기능 | 함수 / 핸들러 |
|------|---------------|
| 자동 로그인 | `autoLogin()` |
| 인증 화면 표시 | `showAuth(pane)` |
| 인증 패널 전환 | `switchAuthPane(pane)` |
| 로그인 정보 저장 | `saveAuth(nickname, password, parish)` |
| 스플래시 숨김 | `hideSplash()` |
| 앱 화면 진입 | `showApp()` |
| 상단 유저 뱃지 갱신 | `updateUserBadge()` |
| 회원가입 | `#registerBtn` click (`action=register`) |
| 로그인 | `#loginBtn` click (`action=login`) |
| 비밀번호 재설정 | `#resetBtn` click (`action=resetPassword`) |

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

### 네비게이션 / UI
| 기능 | 함수 |
|------|------|
| 드로어 열기 | `openDrawer()` |
| 드로어 닫기 | `closeDrawer()` |
| 섹션 전환 | `switchSection(name)` |
| HTML 이스케이프 | `escHtml(s)` |

### SECTION_IDS (드로어 섹션 키)
`notice` / `mission` / `collection` / `prayer` / `secret` / `inquiry` / `chat`

---

## 10. 향후 작업 (Pending)

- [ ] 주차별 뽑기 횟수 정책 GAS 로직 반영 (현재 주 1회 고정)
- [ ] 현장 카드 4종 + 히든 카드 2종 데이터 정의 및 앱 반영
- [ ] 히든카드 비밀친구 연동 로직 구현
- [ ] EN카드 팩·앞면·뒷면 실제 이미지로 교체 (제공 예정)
- [ ] 물리카드 인쇄 발주 (레드프린팅 + 프린팅팅)
- [ ] **Firestore 보안 규칙 강화** — 5/24 만료 전 닉네임 검증·rate limit 룰 적용
- [ ] **wrangler.jsonc 머지 충돌 해결** — `compatibility_date` 충돌 마커 제거
- [ ] 단톡방 페이지네이션 (현재 `limitToLast(100)`만)
- [ ] 단톡방 메시지 신고/삭제/수정 기능
- [ ] (선택) Firebase Cloud Messaging 푸시 알림 검토
