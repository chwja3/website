# Beyond Us — 청년교구 수련회 체크 웹앱

## 개요

2026 청년교구 수련회 준비를 위한 실천 체크 + 성령의 열매 카드 컬렉션 앱.
단일 `index.html` 파일로 구성되며 GitHub Pages로 배포, Google Apps Script(GAS)를 백엔드로 사용.

---

## 스택

| 영역 | 기술 |
|------|------|
| 프론트엔드 | Vanilla JS + CSS (단일 `index.html`) |
| 백엔드 | Google Apps Script (REST API) |
| 데이터 저장 | Google Sheets |
| 배포 | GitHub Pages (`main` 브랜치 자동 배포) |
| 클라이언트 상태 | `localStorage` |

---

## 파일 구조

```
workspace/
├── index.html      # 앱 전체 (HTML + CSS + JS)
├── sheep.png       # 상단 양 일러스트 (배경 제거 버전)
└── PROJECT.md      # 이 문서
```

---

## 백엔드 (Google Apps Script)

### 스프레드시트
- **SPREADSHEET_ID**: `1tlCozEXN8w2y9QqsEjUwffSuLr71edy2YOEJumy9e8Q`
- **시트**: `raw_checkins`, `config`, `CardDraws`

### API 엔드포인트
```
https://script.google.com/macros/s/AKfycbwE.../exec
```

### 액션 목록

| action | 설명 |
|--------|------|
| `dashboard` | 체크 현황, 통계 조회 |
| `userStatus` | 특정 userId의 이번 주 제출 여부 + 보유 카드 목록 조회 |
| `submit` | 오늘 체크 제출 (userId, weekKey 컬럼 포함) |
| `drawCard` | 카드 뽑기 (testMode일 때 중복/자격 체크 스킵) |

### raw_checkins 시트 컬럼
1. 타임스탬프
2. 닉네임
3. 체크 항목들
4. userId (닉네임 기반 ID)
5. weekKey (ISO 주차, e.g. `2026-W15`)

---

## 주요 기능

### 1. 실천 체크
- 주차별 실천 항목 체크 후 제출
- 이번 주 이미 제출 시 재제출 불가 (localStorage + GAS 서버 양쪽 검증)
- 제출 후 공동체 진행률 및 실천 현황 업데이트

### 2. 닉네임 시스템
- 최초 1회 입력 → `localStorage`에 저장 (`beyondus_nickname`)
- 닉네임 기반 userId 생성 (서버 저장용)
- 앱 재진입 시 자동 로드

### 3. 성령의 열매 카드 컬렉션
- 9종 카드 (사랑, 희락, 화평, 오래참음, 자비, 양선, 충성, 온유, 절제)
- 이번 주 체크 제출 시 카드 뽑기 기회 1회 부여
- 포켓몬 스타일 3단계 뽑기 UX: **팩 열기 → 뒷면 카드 클릭 → 앞면 공개**
- 획득 카드는 서버(CardDraws 시트)에 저장
- 컬렉션 갤러리: 미획득 카드는 잠금 상태로 표시, 중복 획득 시 배지(숫자)

### 4. Pull-to-Refresh
- 스크롤 최상단에서 아래로 당기면 데이터 새로고침
- `isRefreshing` 플래그로 중복 트리거 방지
- 새로고침 완료 후 인디케이터 자동 닫힘

---

## 테스트 / 서비스 모드 분리

| 모드 | URL | 동작 |
|------|-----|------|
| 서비스 | `https://...github.io/...` | 이번 주 제출 여부·중복 카드 체크 정상 적용 |
| 테스트 | URL에 `?test=1` 추가 | GAS에서 중복/자격 체크 스킵 → 자유롭게 뽑기 가능 |

프론트엔드에서 `TEST_MODE` 플래그를 API 요청에 포함:
```javascript
const TEST_MODE = new URLSearchParams(window.location.search).get('test') === '1';
```

---

## 디자인 테마

| 변수 | 값 | 설명 |
|------|----|------|
| `--bg` | `#faf6ef` | 크림 배경 |
| `--card` | `#fffdf8` | 카드 배경 |
| `--text` / `--primary` | `#2c2417` | 차콜 텍스트 |
| `--primary-soft` | `#f0ebe0` | 연한 크림 (버튼 secondary 등) |
| `--line` | `#e4ddd0` | 테두리 |
| `--success` | `#16a34a` | 초록 |
| `--danger` | `#dc2626` | 빨강 |

---

## 카드 데이터

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
```

---

## LocalStorage 키 목록

| 키 | 설명 |
|----|------|
| `beyondus_nickname` | 사용자 닉네임 (최초 입력 후 영구 저장) |
| `beyondus_last_check_date` | 오늘 체크 완료 날짜 (중복 제출 방지용) |

---

## 주요 버그 수정 이력

| 버그 | 원인 | 해결 |
|------|------|------|
| 카드 앞뒷면 동시 표시 | iOS Safari에서 `backface-visibility: hidden` 미작동 | 3D flip 폐기 → `flip-out` / `flip-in` 두 단계 CSS 애니메이션으로 교체 |
| 뽑기 3단계가 동시에 보임 | `.hidden` CSS 규칙 누락 | `.hidden { display: none !important; }` 추가 |
| Pull-to-refresh 1회만 동작 | `triggered` 플래그가 async 이후 리셋 안 됨 | `isRefreshing` 플래그로 교체, async 완료 후 리셋 |
| 카드 뽑기 섹션에 "이번 주 체크 먼저" 표시 | 닉네임 미설정 시 `userStatus` 미로드 | 닉네임 확인 후 `loadUserStatus()` 호출 순서 조정 |

---

## 향후 작업 (Pending)

- [ ] 카드 팩 / 앞면 / 뒷면 실제 이미지로 교체 (이미지 파일 제공 예정)
- [ ] GAS `drawCard` 함수에 `testMode` 파라미터 처리 코드 적용 확인

---

## 주차 키 생성 로직 (ISO Week)

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

## 개발 메모

- **localStorage 초기화** (브라우저 콘솔):
  ```javascript
  localStorage.clear(); // 닉네임 + 체크 날짜 모두 초기화
  localStorage.removeItem('beyondus_last_check_date'); // 체크 날짜만 초기화
  ```
- **폰에서 초기화**: Pull-to-refresh로 서버 데이터는 새로고침 가능. localStorage는 브라우저 개발자도구 필요.
- **카드 시트 초기화**: Google Sheets `CardDraws` 시트에서 직접 행 삭제.
