# GAS Action 인벤토리

## 현재 호출 구조

현재 앱과 관리자 페이지는 `action` 값을 GAS Web App에 전달한다. GET action은 `doGet`, POST action은 `doPost`에서 분기된다.

## 사용자 앱에서 실제 호출 중인 action

| action | 현재 의미 | Supabase 전환 후 방향 |
|---|---|---|
| `dashboard` | 전체 대시보드 조회 | `get_public_dashboard` 또는 `get_app_bootstrap`으로 대체 |
| `userStatus` | 유저 전체 상태 조회 | `get_user_status` RPC로 대체 |
| `userStatusLite` | 유저 경량 상태 조회 | `get_user_status_lite` 또는 `get_user_status` 옵션으로 대체 |
| `getHoldPray` | H&P 목록과 내 추측 상태 조회 | `get_hold_pray`로 대체 |
| `findNickname` | 이름과 교구로 아이디 찾기 | 보안상 공개 API 폐기 권장. 관리자 또는 Auth recovery로 대체 |
| `getPublicCollection` | 다른 유저 컬렉션 조회 | `get_public_collection`으로 대체 |
| `getTrades` | 내 교환 목록 조회 | `get_trades`로 대체 |
| `getNotices` | 공지 조회 | `get_notices`로 대체 |
| `getInquiries` | 개발자 문의 조회 | `get_inquiries`로 대체 |
| `getBBB` | BBB, 천로역정, 매칭 상태 조회 | `get_bbb_status`로 대체 |
| `getBBBMessages` | BBB 메시지 조회 | `get_bbb_messages`로 대체 |
| `register` | 가입 | Supabase Auth sign up과 `profiles` insert로 대체 |
| `login` | 로그인과 세션 발급 | Supabase Auth sign in으로 대체 |
| `resetPassword` | 사용자 비밀번호 재설정 | Supabase Auth password reset 또는 관리자 reset로 대체 |
| `submit` | 사전미션 제출과 카드팩 지급 | `submit_pre_mission`로 대체 |
| `drawCard` | 일반 카드팩 개봉 | `draw_card_pack`로 대체 |
| `drawSpecialCard` | 특별 카드팩 개봉 | `draw_card_pack`의 pack type으로 통합 |
| `devResetCards` | DEV 계정 테스트 초기화 | DEV 전용 admin RPC로만 유지 |
| `requestTrade` | 카드 교환 요청 | `request_trade`로 대체 |
| `acceptTrade` | 카드 교환 수락 | `accept_trade`로 대체 |
| `rejectTrade` | 카드 교환 거절 | `reject_trade`로 대체 |
| `cancelTrade` | 카드 교환 취소 | `cancel_trade`로 대체 |
| `prayForTrade` | 교환 기도 체크 | 기능 유지 시 `pray_for_trade`로 대체 |
| `deleteInquiry` | 문의 삭제 | `delete_inquiry`로 대체 |
| `editInquiry` | 문의 수정 | `edit_inquiry`로 대체 |
| `postInquiry` | 문의 등록 | `post_inquiry`로 대체 |
| `uploadBBBPhoto` | BBB 사진과 천로역정 인증 업로드 | Storage 업로드 후 `submit_mission_photo`로 대체 |
| `deleteBBBPhoto` | BBB 사진 삭제 | `delete_mission_photo`로 대체 |
| `guessBBBSecret` | 시크릿 버디 추측 | `guess_bbb_secret`로 대체 |
| `sendBBBMessage` | BBB 메시지 전송 | `send_bbb_message`로 대체 |
| `submitHoldPrayGuess` | H&P 이름 맞히기 | `submit_hold_pray_guess`로 대체 |
| `postHpHint` | H&P 힌트 등록 | `post_hp_hint`로 대체 |

## 관리자에서 실제 호출 중인 action

| action | 현재 의미 | Supabase 전환 후 방향 |
|---|---|---|
| `adminLogin` | 관리자 비밀번호 로그인 | Supabase Auth role 기반 로그인으로 폐기 |
| `getUsers` | 유저 목록 조회 | `admin_get_users`로 대체 |
| `adminGetRaffleAttendance` | 앱 가입자, 참석, 추첨권 제외 조회 | `admin_get_participants`로 대체 |
| `adminDeactivateUser` | 유저 비활성화 | `admin_set_user_status`로 대체 |
| `adminRestoreUser` | 유저 복구 | `admin_set_user_status`로 대체 |
| `adminSetRaffleAttendance` | 참석 체크 | `admin_set_attendance`로 대체 |
| `adminSetRaffleExcluded` | 추첨권 제외 체크 | `admin_set_raffle_excluded`로 대체 |
| `setCardReceivedQty` | 실물 카드 수령 수량 관리 | `admin_set_physical_card_receipt`로 대체 |
| `getTicketStats` | 뽑기권 집계 | view 또는 `admin_get_inventory_stats`로 대체 |
| `getCardStats` | 카드 집계 | view 또는 `admin_get_card_stats`로 대체 |
| `adminResetPassword` | 유저 비밀번호 초기화 | Supabase Auth admin reset로 대체 |
| `getCurrentWeek` | 현재 주차 조회 | `app_settings` 조회로 대체 |
| `setCurrentWeek` | 현재 주차 변경 | `admin_set_app_setting`로 대체 |
| `getMissionConfig` | 사전미션 설정 조회 | `mission_weeks`, `mission_items` 조회로 대체 |
| `setMissionConfig` | 사전미션 설정 변경 | `admin_upsert_mission_config`로 대체 |
| `getTabSettings` | 탭 표시와 상태 조회 | `tab_settings` 조회로 대체 |
| `setTabSettings` | 탭 표시와 상태 저장 | `admin_set_tab_settings`로 대체 |
| `postNotice` | 공지 등록 | `admin_create_notice`로 대체 |
| `editNotice` | 공지 수정 | `admin_update_notice`로 대체 |
| `deleteNotice` | 공지 삭제 | `admin_delete_notice`로 대체 |
| `getAdminTrades` | 교환 전체 조회 | `admin_get_trades`로 대체 |
| `adminGetBBBPhotoApprovals` | BBB 사진 승인 목록 | `admin_get_photo_approvals`로 대체 |
| `adminApproveBBBPhoto` | BBB 사진 승인 | `admin_approve_photo_submission`로 대체 |
| `adminRejectBBBPhoto` | BBB 사진 거절 | `admin_reject_photo_submission`로 대체 |
| `adminFindRaffleTicket` | 추첨권 번호 검색 | `admin_find_raffle_ticket`로 대체 |
| `adminGetRaffleTickets` | 추첨권 번호 목록 | `admin_get_raffle_tickets`로 대체 |
| `adminGetBBB` | BBB 매칭 전체 조회 | `admin_get_bbb_assignments`로 대체 |
| `adminSetupBBBMatching` | 기존 TF 기준 자동 매칭 | 기능 의미상 폐기. 조별, 티어 기반 매칭으로 재설계 |
| `adminWriteBBBRows` | BBB 매칭 행 직접 쓰기 | `admin_import_bbb_assignments`로 대체 |
| `adminCreateCardEvent` | 카드 지급, 회수 이벤트 생성 | `admin_adjust_card`로 대체 |
| `adminRebuildEventDerivedViews` | Events 기준 파생 테이블 재계산 | Supabase job 또는 admin rebuild RPC로 대체 |
| `prodCutoverHealthCheck` | PROD cutover 상태 확인 | Supabase 전환 후 폐기 |
| `prodCutoverDryRun` | Sheet 구조 변경 dry run | Supabase 전환 후 폐기 |
| `prodCutoverApply` | Sheet 구조 변경 apply | Supabase 전환 후 폐기 |
| `replyInquiry` | 문의 답변 | `admin_reply_inquiry`로 대체 |

## GAS에 있지만 기능 의미상 폐기할 action

| action | 폐기 이유 |
|---|---|
| `migrateCardDrawsToCollection` | Sheet 시절 마이그레이션 전용이다. Supabase 이관 후 필요 없다 |
| `adminSetupRawHeader` | `raw_checkins` 시트 헤더 보정용이다. Supabase에서는 사용하지 않는다 |
| `adminBackfillRawCols` | legacy raw 시트 backfill용이다. Supabase에서는 사용하지 않는다 |
| `phase2EHealthCheck` | Sheet 최적화 전환 단계 진단용이다 |
| `phase2EMeasurePerformance` | GAS와 Sheet 성능 측정용이다 |
| `phase2EStressTestDraws` | GAS draw 성능 테스트용이다 |
| `prodCutoverDryRun` | Sheet PROD cutover용이다 |
| `prodCutoverApply` | Sheet PROD cutover용이다 |
| `prodCutoverHealthCheck` | Sheet PROD cutover 후 확인용이다 |
| `adminRebuildCollection` | Collection 시트 재계산용이다. Supabase에서는 파생 테이블 rebuild job으로 대체한다 |
| `adminRebuildCollectionRow` | Collection 시트 행 재계산용이다. Supabase에서는 특정 유저 summary rebuild RPC로 대체한다 |
| `adminSetupBBBMatching` | 기존 임의 매칭 방식이다. 새 정책은 조별, 티어 기반 매칭이므로 폐기한다 |
| `adminSetBBBMessageOpen` | BBBSettings 전용 임시 action이다. 탭 설정 또는 app setting으로 통합한다 |
| `setDrawReceived` | 과거 CardDraws 수령 플래그 기반이다. 실물 수령은 별도 physical receipt 구조로 통합한다 |
| `adminGrantHiddenCard` | 레어 카드 전용 수동 지급이다. 일반화된 `admin_adjust_card`로 통합한다 |
| `adminGrantTestCard` | GAS test admin action이다. DEV 전용 seed 또는 admin adjustment로 대체한다 |

## 유지해야 하는 기능이지만 GAS action 이름은 폐기할 항목

- 가입, 로그인, 비밀번호 재설정은 기능은 유지하되 Supabase Auth로 이전한다.
- 대시보드와 유저 상태 조회는 기능은 유지하되 view, summary table, RPC로 이전한다.
- 카드팩, 추첨권, BBB, H&P, 교환, 문의, 공지는 기능은 유지하되 domain API로 재작성한다.
- 관리자 카드 지급, 회수는 기능은 유지하되 `admin_adjust_card` 하나로 통합한다.
