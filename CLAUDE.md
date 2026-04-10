# CLAUDE.md — 콩글리쉬 변환기 프로젝트

## 프로젝트 개요

한국어 텍스트를 입력하면 콩글리쉬(한국식 영문 표기) 로 변환해주는 웹 유틸리티.
예: `안녕하세요` → `annyeonghaseyo`
결과는 원클릭으로 클립보드에 복사 가능.
Google AdSense 광고 수익화 포함.

**기존 `index.html`은 절대 수정하지 않는다.**

---

## 파일 구조

```
workspace/
├── index.html              # 기존 앱 — 손대지 않음
├── konglish/
│   ├── index.html          # 메인 변환기 페이지 (HTML + 인라인 CSS/JS 단일 파일)
│   └── (이미지, 아이콘 등 필요 시 추가)
├── CLAUDE.md               # 이 문서
└── PROJECT.md              # 기존 프로젝트 문서
```

> 단일 `konglish/index.html` 파일로 완결. 별도 CSS/JS 파일 분리 없음.

---

## 핵심 기능

### 1. 변환 엔진 (한국어 → 콩글리쉬)
- 유니코드 한글 음절 분해 알고리즘 사용
  - 한글 음절 범위: `0xAC00` ~ `0xD7A3`
  - 공식: `음절코드 - 0xAC00` → 초성/중성/종성 인덱스 추출
- **초성 (19개)**: ㄱ→g, ㄲ→kk, ㄴ→n, ㄷ→d, ㄸ→tt, ㄹ→r, ㅁ→m, ㅂ→b, ㅃ→pp, ㅅ→s, ㅆ→ss, ㅇ→(빈값), ㅈ→j, ㅉ→jj, ㅊ→ch, ㅋ→k, ㅌ→t, ㅍ→p, ㅎ→h
- **중성 (21개)**: ㅏ→a, ㅐ→ae, ㅑ→ya, ㅒ→yae, ㅓ→eo, ㅔ→e, ㅕ→yeo, ㅖ→ye, ㅗ→o, ㅘ→wa, ㅙ→wae, ㅚ→oe, ㅛ→yo, ㅜ→u, ㅝ→wo, ㅞ→we, ㅟ→wi, ㅠ→yu, ㅡ→eu, ㅢ→ui, ㅣ→i
- **종성 (28개)**: (없음)→'', ㄱ→k, ㄲ→k, ㄳ→k, ㄴ→n, ㄵ→n, ㄶ→n, ㄷ→t, ㄹ→l, ㄺ→k, ㄻ→m, ㄼ→l, ㄽ→l, ㄾ→l, ㄿ→p, ㅀ→l, ㅁ→m, ㅂ→p, ㅄ→p, ㅅ→t, ㅆ→t, ㅇ→ng, ㅈ→t, ㅊ→t, ㅋ→k, ㅌ→t, ㅍ→p, ㅎ→t
- 한글 이외 문자(영문, 숫자, 공백, 특수문자)는 그대로 통과

### 2. UI / UX
- 좌우 2열 레이아웃 (데스크탑) / 상하 1열 (모바일)
  - 왼쪽: 한국어 입력 textarea
  - 오른쪽: 콩글리쉬 출력 (읽기 전용)
- 입력 즉시 실시간 변환 (keyup 이벤트)
- **복사 버튼**: 출력 영역 우상단 고정, 클릭 시 클립보드 복사 + "복사됨!" 피드백 (1.5초)
- 입력 초기화 버튼 (X 아이콘)
- 문자 수 카운터 표시 (입력/출력 각각)
- 예시 문구 클릭 시 자동 입력되는 예시 칩 (안녕하세요, 사랑해, 감사합니다, 파이팅 등)

### 3. Google AdSense
- **퍼블리셔 ID**: 코드 작성 시 플레이스홀더 `ca-pub-XXXXXXXXXX` 로 남겨두고, 사용자가 직접 교체
- **광고 슬롯 위치**:
  1. 헤더 아래 — 가로형 배너 (leaderboard, 728×90 / 반응형)
  2. 변환 영역 아래 — 직사각형 (336×280 / 반응형)
  3. 푸터 위 — 가로형 배너 (반응형)
- 모든 광고 슬롯은 `<ins class="adsbygoogle">` 반응형으로 구현
- AdSense 스크립트 `<head>` 에 삽입, `async` 속성 포함

---

## 디자인 시스템

| 항목 | 값 |
|------|----|
| 배경 | `#0f0f0f` (다크) |
| 카드 배경 | `#1a1a1a` |
| 포인트 컬러 | `#7c3aed` (보라) |
| 포인트 라이트 | `#a78bfa` |
| 텍스트 | `#f5f5f5` |
| 서브 텍스트 | `#888` |
| 테두리 | `#2e2e2e` |
| 폰트 | `'Pretendard', 'Noto Sans KR', sans-serif` (CDN) |

- 다크모드 기본
- 모서리 `border-radius: 12px`
- 복사 버튼: 포인트 컬러 채움, hover 시 밝아짐
- 미니멀 & 클린 — 광고가 거슬리지 않도록 콘텐츠 영역과 명확히 구분

---

## SEO / 메타데이터

```html
<title>콩글리쉬 변환기 — 한국어를 영문으로 바로 변환</title>
<meta name="description" content="한국어 텍스트를 콩글리쉬(한국식 영문 표기)로 즉시 변환. 클립보드 복사까지 원클릭.">
<meta property="og:title" content="콩글리쉬 변환기">
<meta name="keywords" content="콩글리쉬, 한국어 영문 변환, 로마자 변환, Korean romanization">
```

---

## 기술 스택

| 영역 | 기술 |
|------|------|
| 언어 | Vanilla HTML/CSS/JavaScript |
| 번들러 | 없음 (단일 파일) |
| 폰트 | Pretendard CDN |
| 광고 | Google AdSense |
| 배포 | GitHub Pages (정적) |

---

## 구현 순서

1. `konglish/index.html` 기본 HTML 구조 + AdSense 플레이스홀더
2. CSS — 레이아웃, 다크 테마, 반응형
3. JS — 한글 분해 + 로마자 변환 엔진
4. JS — UI 인터랙션 (실시간 변환, 복사, 초기화, 예시 칩)
5. 검토 및 마무리

---

## 주의사항

- `index.html` (기존 Beyond Us 앱) 절대 수정 금지
- 광고 슬롯 ID(`data-ad-slot`)는 플레이스홀더로 남김 — 사용자가 AdSense 계정에서 직접 발급 후 교체
- 순수 정적 파일 — 외부 API 호출 없음

---

## Google AdSense 승인 최적화 체크리스트

> 참고 자료:
> - [Google 공식 — 애드센스 자격 요건 (한국어)](https://support.google.com/adsense/answer/9724?hl=ko)
> - [Google 공식 — AdSense Eligibility (영어)](https://support.google.com/adsense/answer/9724?hl=en)
> - [2025년 구글 애드센스 승인 조건 완벽 정리](https://gaho1.com/entry/2025%EB%85%84-%EA%B5%AC%EA%B8%80-%EC%95%A0%EB%93%9C%EC%84%BC%EC%8A%A4-%EC%8A%B9%EC%9D%B8-%EC%A1%B0%EA%B1%B4-%EC%99%84%EB%B2%BD-%EC%A0%95%EB%A6%AC-%EB%B8%94%EB%A1%9C%EA%B7%B8-%EC%8A%B9%EC%9D%B8%EC%9D%84-%EB%B0%9B%EC%9C%BC%EB%A0%A4%EB%A9%B4)
> - [애드센스 승인 기준 2025: 빠르게 통과하는 법](https://annsy0318.com/149)
> - [7 Proven Strategies for AdSense Approval 2025 — AdPushup](https://www.adpushup.com/blog/google-adsense-approval/)
> - [AdSense Requirements for Website 2025 — AllInAllSEO](https://allinallseo.com/adsense-requirements-for-website-a-complete-guide-for-2025/)
> - [Google AdSense Approval Guide — MonetizationGuy](https://monetizationguy.com/articles/google-adsense-approval-guide-requirements-process-and-avoiding-rejections)

### 필수 페이지 (없으면 승인 거의 불가)
- [ ] **개인정보처리방침 (Privacy Policy)** 페이지 — `konglish/privacy.html`
- [ ] **이용약관 (Terms of Service)** 페이지 — `konglish/terms.html`
- [ ] **문의하기 (Contact)** 페이지 또는 이메일 링크
- [ ] **About (사이트 소개)** 섹션 또는 페이지
- 모든 필수 페이지는 푸터에서 링크로 접근 가능해야 함

### 콘텐츠 품질
- [ ] 독창적이고 유익한 콘텐츠 — 단순 툴이므로 사용법 설명, FAQ, 예시 섹션으로 보완
- [ ] 페이지 내 텍스트 충분히 확보 (툴 설명 + 사용 가이드 + FAQ 최소 500자 이상)
- [ ] 복사 콘텐츠(중복) 없음

### 기술 요건
- [ ] **HTTPS** — GitHub Pages는 기본 제공
- [ ] **모바일 반응형** — viewport 메타태그 + 반응형 CSS 필수
- [ ] **Core Web Vitals 최적화**
  - LCP (최대 콘텐츠풀 페인트): 이미지 최적화, 폰트 preload
  - CLS (레이아웃 시프트): 광고 슬롯 크기 미리 확보 (`min-height` 지정)
  - FID/INP: JS 블로킹 최소화
- [ ] 페이지 로딩 속도 최적화 — 외부 스크립트 `async`/`defer` 처리
- [ ] 깨진 링크 없음

### SEO
- [ ] 각 페이지 고유한 `<title>` 및 `<meta name="description">`
- [ ] `<html lang="ko">` 언어 속성
- [ ] 명확한 헤딩 구조 (h1 → h2 → h3)
- [ ] `robots.txt` 또는 `sitemap.xml` (선택, 있으면 유리)
- [ ] OG(Open Graph) 메타태그

### 광고 배치 규칙
- [ ] 광고가 콘텐츠보다 많으면 안 됨 (콘텐츠 > 광고)
- [ ] 광고 슬롯 주변에 충분한 여백 확보
- [ ] 클릭을 유도하는 문구("여기 클릭" 등) 금지
- [ ] 팝업·자동재생 광고 없음

### 금지 콘텐츠 (해당 없음 확인)
- [ ] 성인 콘텐츠 없음
- [ ] 저작권 침해 콘텐츠 없음
- [ ] 불법 콘텐츠 없음
