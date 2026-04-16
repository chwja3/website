# Beyond Us — CLAUDE.md

> AI 어시스턴트용 프로젝트 참조 문서. 아래 목차에서 필요한 섹션의 라인 범위를 확인한 뒤 해당 부분만 읽으세요.

---

## 작업 규칙 (MUST FOLLOW)

1. **코드 수정 전 반드시 정책/계획을 먼저 제안하고 유저 확인을 받을 것.**
   - 기능 추가·변경·버그 수정 모두 해당.
   - 계획 없이 바로 Edit/Write 도구를 실행하지 말 것.
2. **계획 제안 형식**: 변경할 파일, 변경 내용 요약, 예상 동작을 텍스트로 먼저 설명.
3. **유저가 "해줘" / "OK" / "ㅇㅇ" 등으로 명시적으로 승인한 후에만 수정 시작.**
4. **수정 전 관련 파일을 반드시 읽고 검토할 것.**
   - 변경이 영향을 미치는 모든 함수/반환값/호출부를 확인.
   - 예: GAS 함수 수정 시 해당 데이터를 사용하는 프론트엔드 코드까지 추적.
   - 누락 없이 일관성이 확보된 상태에서만 수정 시작.

---

## 목차 (섹션별 라인 위치)

| # | 섹션 | 라인 |
|---|------|------|
| 1 | [프로젝트 개요 · URL · 인원](#1-프로젝트-개요) | 25–35 |
| 2 | [기술 스택](#2-기술-스택) | 38–47 |
| 3 | [파일 구조](#3-파일-구조) | 50–66 |
| 4 | [백엔드 — 스프레드시트 · API 엔드포인트 · 액션 목록](#4-백엔드) | 69–100 |
| 5 | [주요 기능 — 로그인/회원가입](#5-로그인--회원가입) | 103–112 |
| 6 | [주요 기능 — 실천 체크(미션)](#6-실천-체크-미션) | 115–122 |
| 7 | [주요 기능 — EN카드 컬렉션 시스템](#7-en카드-컬렉션-시스템) | 125–175 |
| 8 | [주요 기능 — 공지사항](#8-공지사항) | 178–187 |
| 9 | [주요 기능 — 어드민 페이지](#9-어드민-페이지) | 190–198 |
| 10 | [햄버거 메뉴 구조](#10-햄버거-메뉴-구조) | 201–210 |
| 11 | [디자인 테마 (CSS 변수)](#11-디자인-테마) | 213–224 |
| 12 | [EN카드 데이터 (JS 상수)](#12-en카드-데이터) | 227–243 |
| 13 | [LocalStorage 키 목록](#13-localstorage-키-목록) | 246–255 |
| 14 | [테스트 모드](#14-테스트-모드) | 258–267 |
| 15 | [주차 키 생성 로직 (ISO Week)](#15-주차-키-생성-로직) | 270–283 |
| 16 | [향후 작업 (Pending)](#16-향후-작업-pending) | 286–294 |
| 17 | [개발 메모 · 초기화 방법](#17-개발-메모) | 297–308 |

---

## 1. 프로젝트 개요

2026 청년교구 수련회 준비를 위한 실천 체크 + EN카드 컬렉션 앱.
단일 `index.html` 파일로 구성되며 GitHub Pages로 배포, Google Apps Script(GAS)를 백엔드로 사용.

- **서비스 URL**: `https://chwja3.github.io/website/beyond_us/`
- **어드민**: `https://chwja3.github.io/website/beyond_us/admin.html`
- **참가 인원**: 약 250명

---

## 2. 기술 스택

| 영역 | 기술 |
|------|------|
| 프론트엔드 | Vanilla JS + CSS (단일 `index.html`) |
| 백엔드 | Google Apps Script (REST API) |
| 데이터 저장 | Google Sheets |
| 배포 | GitHub Pages (`main` 브랜치, `/` 루트 → `beyond_us/` 리다이렉트) |
| 클라이언트 상태 | `localStorage` |

---

## 3. 파일 구조

```
workspace/
├── index.html              # beyond_us/로 자동 리다이렉트
├── K-translate/            # 별개 프로젝트
├── reels/
└── beyond_us/
    ├── index.html          # 앱 전체 (HTML + CSS + JS)
    ├── admin.html          # 관리자 페이지
    ├── manifest.json       # PWA 홈화면 추가 설정
    ├── CLAUDE.md           # 이 문서
    ├── Apps_Script         # GAS 소스 (편집 후 직접 배포 필요)
    └── images/
        ├── hc_illust1~5.png
        ├── hc_logo_png1~2.png
        ├── pabicon.png
        └── sheep.png
```

---

## 4. 백엔드

### 스프레드시트
- **SPREADSHEET_ID**: `1tlCozEXN8w2y9QqsEjUwffSuLr71edy2YOEJumy9e8Q`
- **시트**: `raw_checkins`, `config`, `CardDraws`, `Users`, `Notices`

### API 엔드포인트
```
https://script.google.com/macros/s/AKfycbwE1WmjS02tZh-jUJOqGEOBobAG73RGpQhxkM9vbgk4xBrq5C-UB8r6vx9lVftaZLAobQ/exec
```

### 액션 목록

| action | 메서드 | 설명 |
|--------|--------|------|
| `dashboard` | GET | 체크 현황·통계·탭설정 조회 |
| `userStatus` | GET | userId의 이번 주 제출 여부 + 보유 카드 목록 |
| `getUsers` | GET | 전체 유저 목록 (adminPw 필요) |
| `getTabSettings` | GET | 손기도·비밀친구 탭 활성화 여부 (adminPw 필요) |
| `getNotices` | GET | 공지사항 목록 (최신순) |
| `submit` | POST | 항목별 미션 체크 제출 |
| `drawCard` | POST | EN카드 뽑기 |
| `register` | POST | 회원가입 |
| `login` | POST | 로그인 |
| `resetPassword` | POST | 비밀번호 찾기 (이름+소속 검증) |
| `adminLogin` | POST | 어드민 로그인 |
| `adminResetPassword` | POST | 어드민 유저 비번 초기화 |
| `setTabSettings` | POST | 탭 활성화 설정 저장 (adminPw 필요) |
| `postNotice` | POST | 공지사항 등록 (adminPw 필요) |
| `deleteNotice` | POST | 공지사항 삭제 (adminPw 필요) |

---

## 5. 로그인 / 회원가입

- 닉네임 = 로그인 ID (중복 불가)
- 가입 시 입력: 닉네임, 비밀번호, 이름, 소속 교구
- 자동 로그인: `localStorage`에 캐시, 앱 재진입 시 서버 검증 없이 즉시 진입
- 비밀번호 분실: 닉네임 + 이름 + 소속 입력 후 새 비밀번호 설정
- 유저 데이터: `Users` 시트 저장

---

## 6. 실천 체크 (미션)

- 주차별 실천 항목은 `config` 시트에서 관리
- **항목별 개별 제출** — 이미 제출한 항목은 취소선+비활성화, 미제출 항목은 언제든 체크 후 제출 가능
- 모든 항목 제출 완료 시 버튼 비활성화
- 제출 후 공동체 진행률 및 통계 업데이트

---

## 7. EN카드 컬렉션 시스템

### 카드 구성 (총 12종)
| 구분 | 수량 | 획득 방법 |
|------|------|---------|
| 온라인 일반카드 | 6종 | 준비기간 미션 뽑기 + 교환 |
| 현장 카드 | 4종 | 수련회 현장 미션 클리어 |
| 히든카드 | 2종 | 비밀친구 미션 클리어 |

### 주차별 뽑기 횟수
| 주차 | 뽑기 기회 |
|------|---------|
| 1~2주차 | 1회/주 |
| 3~4주차 | 2회/주 |
| 5~6주차 | 3회/주 |
| 수련회 현장 | 현장 미션 클리어 시 지급 |
| 비밀친구 | 히든카드 2종 (앱에서 뽑기 이펙트, 실물은 별도 지급) |

### 6주 개근 시 통계
- 최대 뽑기 횟수: 12회
- 6종 완성 확률 (개인): 약 44%
- 교환 포함 시 완성률: 약 80~90%

### 뽑기 UX
- 포켓몬 스타일 3단계: **팩 열기 → 뒷면 카드 클릭 → 앞면 공개**
- 획득 카드: `CardDraws` 시트에 저장
- 컬렉션 갤러리: 미획득 잠금 표시, 중복 획득 시 숫자 배지

### 물리카드 인쇄 계획
- 일반카드 9종: 레드프린팅 옵셋, 500장×9종 — 199,980원
- 히든카드 2종: 프린팅팅, 200장×2종 — 50,600원
- 사이즈: 54×86mm / 스노우지 + 유광 코팅 (히든은 홀로그램)
- **총 예상 비용: 250,580원**

---

## 8. 공지사항

- 어드민에서 제목+내용 작성 후 등록
- 사용자 앱 햄버거 메뉴 최상단 노출
- 읽지 않은 공지: 햄버거 버튼 + 메뉴 항목에 빨간 점 표시
- 확인 시 자동 읽음 처리 (`beyondus_seen_notices` localStorage)
- 제목·내용 실시간 검색 (사용자/어드민 공통)
- 데이터: `Notices` 시트 (자동 생성)

---

## 9. 어드민 페이지

파일: `admin.html`

- 비밀번호 로그인 (세션 유지)
- **유저 관리**: 전체 가입자 통계, 교구별 분류, 비밀번호 초기화
- **체크인 현황**: 이번 주 제출 수, 항목별 체크 현황
- **공지사항**: 등록·삭제·검색
- **탭 설정**: 손기도·비밀친구 탭 전체 on/off

---

## 10. 햄버거 메뉴 구조

```
공지사항   ← 최상단, 새 공지 시 빨간 점
미션
컬렉션
손기도     ← 어드민에서 on/off 가능
비밀친구   ← 어드민에서 on/off 가능
```

---

## 11. 디자인 테마

| 변수 | 값 | 설명 |
|------|----|------|
| `--bg` | `#faf6ef` | 크림 배경 |
| `--card` | `#fffdf8` | 카드 배경 |
| `--text` / `--primary` | `#2c2417` | 차콜 텍스트 |
| `--primary-soft` | `#f0ebe0` | 연한 크림 |
| `--line` | `#e4ddd0` | 테두리 |
| `--success` | `#16a34a` | 초록 |
| `--danger` | `#dc2626` | 빨강 |

---

## 12. EN카드 데이터

```javascript
const SPIRIT_CARDS = [
  { id:1, name:'사랑',     en:'Love',         emoji:'❤️',  g1:'#ff758c', g2:'#c0392b' },
  { id:2, name:'희락',     en:'Joy',          emoji:'☀️',  g1:'#f7971e', g2:'#c0850a' },
  { id:3, name:'화평',     en:'Peace',        emoji:'🕊️', g1:'#185a9d', g2:'#43cea2' },
  { id:4, name:'오래참음', en:'Patience',     emoji:'⏳',  g1:'#8b6914', g2:'#c8a96e' },
  { id:5, name:'자비',     en:'Kindness',     emoji:'🤲',  g1:'#2d6a4f', g2:'#52b788' },
  { id:6, name:'양선',     en:'Goodness',     emoji:'🌿',  g1:'#11998e', g2:'#38ef7d' },
  { id:7, name:'충성',     en:'Faithfulness', emoji:'⭐',  g1:'#b5451b', g2:'#e8a87c' },
  { id:8, name:'온유',     en:'Gentleness',   emoji:'🌸',  g1:'#7b4fa6', g2:'#c084fc' },
  { id:9, name:'절제',     en:'Self-Control', emoji:'🛡️', g1:'#1a3a5c', g2:'#2e86c1' },
];
// 현장 카드 4종, 히든 카드 2종은 별도 정의 예정
```

---

## 13. LocalStorage 키 목록

| 키 | 설명 |
|----|------|
| `beyondus_nickname` | 사용자 닉네임 |
| `beyondus_pw` | 캐시된 비밀번호 (자동 로그인용) |
| `beyondus_parish` | 소속 교구 |
| `beyondus_seen_notices` | 읽은 공지 ID 배열 (빨간 점 관리) |
| `beyondus_last_check_date` | ~~체크 날짜~~ (현재 미사용, 항목별 제출로 변경) |

---

## 14. 테스트 모드

| 모드 | URL | 동작 |
|------|-----|------|
| 서비스 | `chwja3.github.io/website/beyond_us/` | 정상 검증 |
| 테스트 | URL에 `?test=1` 추가 | GAS 중복·자격 체크 스킵 |

```javascript
const TEST_MODE = new URLSearchParams(window.location.search).get('test') === '1';
```

---

## 15. 주차 키 생성 로직

ISO Week 기준으로 주차 키를 생성합니다.

```javascript
function getWeekKey() {
  const now = new Date();
  const d = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const wk = Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(wk).padStart(2,'0')}`;
}
// 예: "2026-W15"
```

---

## 16. 향후 작업 (Pending)

- [ ] 주차별 뽑기 횟수 정책 GAS 로직 반영 (현재 주 1회 고정)
- [ ] 현장 카드 4종 + 히든 카드 2종 데이터 정의 및 앱 반영
- [ ] 히든카드 비밀친구 연동 로직 구현
- [ ] EN카드 팩·앞면·뒷면 실제 이미지로 교체 (제공 예정)
- [ ] 물리카드 인쇄 발주 (레드프린팅 + 프린팅팅)

---

## 17. 개발 메모

**localStorage 초기화** (브라우저 콘솔):
```javascript
localStorage.clear(); // 전체 초기화
localStorage.removeItem('beyondus_seen_notices'); // 공지 읽음 초기화만
```

- **카드 시트 초기화**: Google Sheets `CardDraws` 시트에서 직접 행 삭제
- **공지 시트**: `Notices` 시트 없으면 GAS가 자동 생성
- **GAS 수정 후**: Apps Script 편집기에서 새 버전으로 재배포 필요
