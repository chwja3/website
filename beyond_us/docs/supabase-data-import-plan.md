# Supabase 데이터 이관 계획

## 목표

기존 Google Sheet의 DEV와 PROD 데이터를 Supabase로 옮긴다. 단순히 현재 상태만 가져오지 않고, Events와 legacy 로그, 운영 도메인 시트까지 원본 행 단위로 보존한다.

## 원칙

- DEV Sheet를 먼저 가져와서 변환 규칙, 정합성, 앱 동작을 검증한다.
- DEV 검증이 끝난 뒤 PROD는 서버를 잠시 닫고 같은 절차를 한 번에 실행한다.
- PROD 작업 시간은 최소화한다. 이관 스크립트와 검증 쿼리는 DEV에서 먼저 확정한다.
- Google Sheet export는 CSV가 아니라 Apps Script JSON export 함수로 수행한다.
- 기존 원본 row는 `legacy_sheet_rows`에 그대로 보관한다.
- 변환된 Supabase 행은 `legacy_import_refs`로 원본 row와 연결한다.
- `Events`는 과거 로그 원장으로 가져오고, `user_cards`, `user_inventory`, `user_summary`는 Events와 도메인 시트에서 다시 계산한다.
- `Collection`, `UserDashboard`, `MissionProgress`, `DashboardStats`는 캐시 또는 projection 성격이므로 원본 row는 보관하되, 최종 현재 상태는 Supabase에서 재계산한 값을 우선한다.

## 이관 대상 분류

| Sheet | Supabase 대상 | 처리 방식 |
|---|---|---|
| `Users` | `auth.users`, `profiles`, `user_inventory`, `user_summary` | Auth 계정 생성, profile 생성, 기본 현재 상태 생성 |
| `RetreatAttendance` | `retreat_attendance` | 참석 여부와 운영 체크 이관 |
| `Events` | `events` | 기존 eventId와 payload를 보존해 원장 이관 |
| `RaffleTickets` | `raffle_tickets`, `events` | 활성 번호와 회수 번호를 그대로 이관하고 누락 이벤트는 보강 |
| `Collection` | `user_cards`, `user_inventory`, `user_summary` | 원본 보관 후 Events projection과 비교. 불일치 시 issue 기록 |
| `MissionProgress` | `mission_progress` | 원본 보관 후 mission events와 비교 |
| `UserDashboard` | `user_summary` | 원본 보관과 검증용. 직접 truth source로 쓰지 않음 |
| `CardReceived` | `physical_card_receipts` | 실물 카드 수령 수량 이관 |
| `Trades` | `trades`, `trade_prayers`, `events` | 진행 중 교환 상태와 기도 체크 이관 |
| `HoldPray` | `hold_pray_entries` | H&P 본문 이관 |
| `HPGuesses` | `hold_pray_guesses`, `events` | 사용자 추측 기록 이관 |
| `BBB` | `bbb_assignments` | 케어버디, 시크릿버디 매칭 이관 |
| `BBBMessages` | `bbb_messages` | 메시지 기록 이관 |
| `BBBPhotos` | `mission_photo_submissions`, Storage | base64 사진은 Storage로 옮긴 뒤 경로 저장 |
| `Notices` | `notices` | 공지와 이미지 URL 이관 |
| `Inquiries` | `inquiries` | 개발자 문의와 답변 이관 |
| `AppSettings` | `app_settings` | 운영 설정 이관 |
| `MissionDefinitions` | `mission_weeks`, `mission_items` | 주차와 사전미션 항목 이관 |
| `TabSettings` | `tab_settings` | 탭 노출과 상태 이관 |
| `BBBSettings` | `app_settings` 또는 `tab_settings` | BBB 섹션 상태를 구조화해 이관 |
| `raw_checkins` | `legacy_sheet_rows`, `events` 검증 | 숨김 legacy 로그. Events에 누락된 경우만 보강 |
| `CardDraws` | `legacy_sheet_rows`, `events` 검증 | 숨김 legacy 로그. Events에 누락된 경우만 보강 |
| `BonusDraws` | `legacy_sheet_rows`, `events` 검증 | 숨김 legacy 로그. Events에 누락된 경우만 보강 |
| `config` | `legacy_sheet_rows` | 숨김 legacy 설정. AppSettings 이관 검증에만 사용 |
| `DashboardStats` | `legacy_sheet_rows` | 캐시. 최종 이관 대상 아님 |

## DEV 이관 순서

1. DEV Supabase에 모든 migration을 적용한다.
2. DEV GAS에서 `exportSupabaseMigrationJsonDev`를 실행해 Drive JSON 파일을 만든다.
3. DEV JSON export 파일을 import 스크립트에 넣어 모든 대상 시트 row를 `legacy_sheet_rows`에 적재한다.
4. `Users`부터 `profiles`와 Auth 계정을 만든다.
5. 설정 시트 `AppSettings`, `MissionDefinitions`, `TabSettings`, `BBBSettings`를 이관한다.
6. `Events`를 이관한다.
7. 도메인 시트 `HoldPray`, `HPGuesses`, `BBB`, `BBBMessages`, `BBBPhotos`, `Trades`, `CardReceived`, `Notices`, `Inquiries`를 이관한다.
8. `RaffleTickets`를 번호 단위로 이관한다.
9. Events와 도메인 상태를 기준으로 `user_cards`, `user_inventory`, `user_summary`, `mission_progress`를 재계산한다.
10. `Collection`, `UserDashboard`, `MissionProgress` 원본과 Supabase 재계산 결과를 비교한다.
11. `migration_issues`가 error 없이 끝나는지 확인한다.
12. DEV 앱을 Supabase API에 연결해 로그인, 미션, 카드팩, H&P, BBB, 천로역정, 추첨권, 관리자 화면을 검증한다.

## PROD 한 번에 작업할 순서

1. PROD 전환 직전 main과 PROD GAS 상태를 기록한다.
2. 사용자 앱을 maintenance 또는 점검 안내 상태로 전환한다.
3. PROD Google Sheet 전체 사본을 만든다.
4. PROD Supabase에 DEV에서 검증된 migration이 모두 적용되어 있는지 확인한다.
5. PROD GAS에서 `exportSupabaseMigrationJsonProd`를 실행해 Drive JSON 파일을 만든다.
6. PROD JSON export 파일을 import 스크립트에 넣어 `legacy_sheet_rows`를 먼저 채운다.
7. Auth 계정과 `profiles`를 생성한다.
8. 설정, Events, 도메인 시트, 추첨권 순서로 정규 테이블을 채운다.
9. 현재 상태 테이블을 재계산한다.
10. 검증 쿼리로 사용자 수, Events 수, 활성 추첨권 수, 카드 보유 합계, 사진 제출 수, 문의 수를 대조한다.
11. 앱과 admin의 API endpoint를 Supabase 기준으로 전환한다.
12. smoke test를 한다.
13. 문제가 없으면 maintenance를 해제한다.
14. Google Sheet와 GAS는 읽기 전용 백업으로 보관한다.

## PROD 검증 기준

- `profiles` 활성 사용자 수가 PROD `Users` 활성 사용자 수와 같다.
- `events` 이벤트 수가 PROD `Events` 수와 같거나 legacy 보강 규칙만큼 많다.
- `raffle_tickets.active=true` 수가 기존 활성 추첨권 수와 같다.
- 사용자별 카드 보유량이 `Collection`과 비교해 mismatch 0이다.
- 사용자별 일반 카드팩과 현장미션 카드팩 잔량이 `Collection`과 비교해 mismatch 0이다.
- H&P, BBB 사진, 문의, 공지 row 수가 원본과 같다.
- 로그인 테스트 계정, 일반 사용자 계정, 관리자 계정이 모두 정상 동작한다.

## 보류 결정

- 기존 비밀번호 해시는 Supabase Auth로 직접 가져오지 않는다.
- 기존 사용자는 이관 후 `password_migration_required=true` 상태가 되고, 최초 접속 또는 안내된 재설정 절차로 새 비밀번호를 만든다.
- BBBPhotos의 base64 사진은 DB에 그대로 넣지 않고 Storage로 옮긴다. 원본 base64 row는 `legacy_sheet_rows`에 보존한다.
