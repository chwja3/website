# Beyond Us — TODO

> 항상 최신 상태 유지. 완료된 항목은 체크만 하고 그대로 두기 (히스토리 용도).

**바로가기**:
[🔴 즉시](#-즉시-오늘-내일) ·
[🟠 5/10 전](#-510-오픈-전) ·
[🟡 오픈 후](#-오픈-후-빠르게) ·
[🟢 여유](#-여유있을-때) ·
[📜 완료](#-완료-참고용)

---

## 🔴 즉시 (오늘·내일)

- [x] **GAS 재배포** — 완료
  - 공지사항 이미지 첨부 (Drive URL 저장)
  - dev/prod 시트 분리 (`devMode` 라우팅)
  - Users 함수 `getSpreadsheet()` 수정 반영

- [ ] **Firestore 보안 규칙 강화** — **5/24 만료** 전에 반드시 처리
  - 현재: 테스트 모드 (`allow read, write: if request.time < 2026-05-24`)
  - 만료되면 단톡방 완전 중단
  - 닉네임 검증 + rate limit 룰로 교체 필요

---

## 🟠 5/10 오픈 전

- [ ] **H&P 손바닥 안 텍스트 정렬** — 웹·모바일 최종 확인
  - dev URL에서 확인 후 추가 조정 필요하면 알려주기

- [ ] **EN카드 실제 이미지로 교체**
  - 팩 앞면·뒷면·카드 앞면 실제 디자인 파일 → `images/` 교체

- [ ] **카드 확률 재계산** — 등급별 / 주차별 threshold 재설계

- [ ] **현장 카드 / 히든 카드 데이터 확정 + 앱 반영**

- [ ] **앱 ↔ 웹 캘린더 동기화** — 안성재 작업, 실제 기기에서 동작 확인

- [ ] **카드팩 캐러셀 로딩 단축** (급하지 않으면 오픈 후로 미뤄도 됨)

---

## 🟡 오픈 후 (빠르게)

- [ ] **물리카드 인쇄 발주** — 레드프린팅 + 프린팅팅

- [ ] **H&P 정답 시 뽑기권 보상** — 정책 확정 후 구현

- [ ] **현장 미션 완료 → 미보유 카드만 노출** — 현장 카드 보상 로직

- [ ] **비밀친구 명칭 B.B.B 확정** + **익명 메시지 기능**
  - 매일 22:00 또는 admin 토글로만 입력 오픈

- [ ] **실물카드 교환 ↔ 앱 컬렉션 동기화** (Plan D — 신뢰 기반 닉네임 트레이드)
  - A가 교환 신청 → B 수락 → 양쪽 컬렉션 동시 업데이트
  - GAS `Trades` 시트 + API 3종 (`requestTrade` / `acceptTrade` / `cancelTrade`)
  - admin 수동 보정 + 트레이드 히스토리 UI

---

## 🟢 여유있을 때

- [ ] **H&P 빈칸 답 공유** — 다른 사람이 뭐라고 썼는지 앱에서 보기

- [ ] 단톡방 페이지네이션 (현재 `limitToLast(100)`)

- [ ] 단톡방 메시지 신고·삭제·수정

- [ ] Firebase Cloud Messaging 푸시 알림 (선택)

- [ ] Cloudflare Pages 정식 채택 여부 결정

---

## ✅ 운영 (코드 작업 아님)

- [x] TF 제외 인원 Coming Soon 노출 — 코드 완료. `Users` F열 isStaff TRUE 시트 정리만
- [ ] `Users` F열 — 운영진만 `TRUE` 설정 확인

---

## 📌 의도된 동작 (변경 X)

- **APP_VERSION ↔ version.txt**: 배포 시 반드시 동기화 (안 맞으면 무한 reload)
- **DEV 환경**: `dev.website-78h.pages.dev` → 자동 TEST_MODE + DEV 시트 사용
- **테스트 모드 카드 뽑기**: GAS 호출 없음 → 통계에 기록 안 됨 (의도된 동작)

---

## 📜 완료 (참고용)

- [x] PWA 아이콘 짤림 수정 (`purpose: "any"`)
- [x] DEV PWA 별도 설치 (`manifest-dev.json`, 앱 이름 "Beyond Us DEV")
- [x] DEV/PROD 완전 분리 — dev URL → DEV 스프레드시트 자동 라우팅 (fetch 인터셉터)
- [x] Admin DEV 배너 (노란색 경고)
- [x] 테스트 모드 GAS 호출 제거 → 통계 오염 방지
- [x] GAS Users 함수 하드코딩 → `getSpreadsheet()` 수정 (dev 유저 분리)
- [x] 공지사항 이미지 첨부 (Drive URL 입력 + 파일 직접 업로드 탭)
- [x] 이미지 URL `lh3.googleusercontent.com` 포맷 자동 변환
- [x] 카드 등장/뒤집기 이펙트 강화 (glow 버그 수정, 스파크 28개·4색, 2차 링, bounce)
- [x] 컬렉션 중복 카드 병렬 시각화 (2장 부채꼴 / 3장+ 팬)
- [x] H&P 손글씨 폰트 (Nanum Pen Script) 입력칸·정답 표시
- [x] H&P 교구 뱃지 제거
- [x] Hold & Pray 탭 신규 구현
- [x] Coming Soon 캐러셀 + 설치 가이드 + PWA 아이콘
- [x] PWA 버전 체크 강제 갱신 (version.txt)
- [x] 뽑기권 이월 시스템 + 🎫 헤더 배지
- [x] 미션 제출 즉시 반영 (optimistic update)
- [x] 주차 점수 미션 주차 기준 집계 버그 수정
- [x] saveCheckin 중복 제출 인덱스 기반 방지
- [x] 어드민 미션 텍스트 수정 시 제출 체크 유지
- [x] 앱 ↔ 웹 캘린더 동기화
