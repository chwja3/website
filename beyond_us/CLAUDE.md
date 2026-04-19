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
| 배포 | GitHub Pages (`main` 브랜치) |
| 클라이언트 상태 | `localStorage` |

---

## 3. 파일 구조

```
beyond_us/
├── index.html          # 앱 전체 (HTML + CSS + JS)
├── admin.html          # 관리자 페이지
├── manifest.json       # PWA 홈화면 추가 설정
├── Apps_Script         # GAS 소스 (편집 후 직접 배포 필요)
├── config_sheets/      # 주차별 미션 TSV (w1~w6.tsv)
└── images/
```

---

## 4. 백엔드

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

---

## 5. 주요 정책

- **로그인**: 닉네임=ID, 자동 로그인(localStorage 캐시), 서버 검증 실패 시 beyondus_ 키 전체 클리어
- **미션**: 주차별 6개 항목, 항목별 개별 제출, 날짜 단위 저장(`beyondus_submitted_YYYY-MM-DD`)
- **config 시트 구조**: 8행 단위 블록, `startRow = (week-1)*8+5`, 항목 6개
- **config 업데이트**: `Apps_Script`의 `setupAllWeeks()` 함수 실행
- **EN카드**: 온라인 일반 6종(뽑기), 현장 4종, 히든 2종 / 뽑기 기준은 주차별 threshold
- **테스트 모드**: URL에 `?test=1` 추가 시 GAS 검증 스킵

---

## 6. 향후 작업 (Pending)

- [ ] 주차별 뽑기 횟수 정책 GAS 로직 반영 (현재 주 1회 고정)
- [ ] 현장 카드 4종 + 히든 카드 2종 데이터 정의 및 앱 반영
- [ ] 히든카드 비밀친구 연동 로직 구현
- [ ] EN카드 팩·앞면·뒷면 실제 이미지로 교체 (제공 예정)
- [ ] 물리카드 인쇄 발주 (레드프린팅 + 프린팅팅)
