# Supabase API Map

## API 계층 원칙

프론트는 Supabase 테이블을 직접 많이 읽지 않고, `apiClient`를 통해 RPC 또는 Edge Function을 호출한다. 이렇게 하면 기존 GAS 호출을 하나씩 교체할 수 있다.

## 사용자 앱 API

| 기존 GAS action | 새 API | 방식 | 주 테이블 |
|---|---|---|---|
| `register` | `auth_register_profile` | Edge Function plus Auth Admin | `auth.users`, `profiles`, `events`, `raffle_tickets` |
| `login` | Supabase Auth sign in with synthetic email | supabase-js | `auth.users`, `profiles` |
| `resetPassword` | `reset_password_by_profile` | Edge Function plus Auth Admin | `auth.users`, `profiles`, `events` |
| `findNickname` | `find_login_id_by_profile` | Edge Function | `profiles` |
| `dashboard` | `get_app_bootstrap` | RPC | `app_settings`, `tab_settings`, `notices`, `mission_weeks` |
| `userStatus`, `userStatusLite` | `get_user_status` | RPC | `profiles`, `user_inventory`, `user_cards`, `mission_progress`, `raffle_tickets` |
| `submit` | `submit_pre_mission` | RPC | `mission_submissions`, `events`, `user_inventory`, `mission_progress` |
| `drawCard`, `drawSpecialCard` | `draw_card_pack` | RPC | `user_inventory`, `user_cards`, `events` |
| `getPublicCollection` | `get_public_collection` | RPC | `profiles`, `user_cards` |
| `getTrades` | `get_user_trades` | RPC | `trades`, `trade_prayers`, `user_cards` |
| `requestTrade` | `request_trade` | RPC | `trades`, `events` |
| `acceptTrade` | `accept_trade` | RPC | `trades`, `user_cards`, `events` |
| `rejectTrade` | `reject_trade` | RPC | `trades`, `events` |
| `cancelTrade` | `cancel_trade` | RPC | `trades`, `events` |
| `prayForTrade` | `pray_for_trade` | RPC | `trade_prayers` |
| `getHoldPray` | `get_hold_pray` | RPC | `hold_pray_entries`, `hold_pray_guesses`, `hold_pray_hints` |
| `submitHoldPrayGuess` | `submit_hold_pray_guess` | RPC | `hold_pray_guesses`, `events` |
| `postHpHint` | `post_hold_pray_hint` | RPC | `hold_pray_hints` |
| `getBBB` | `get_bbb_status` | RPC | `bbb_assignments`, `mission_photo_submissions`, `pilgrim_assignments` |
| `uploadBBBPhoto` | `submit_mission_photo` | Storage plus RPC | `mission_photo_submissions`, `events`, `user_inventory`, `user_cards` |
| `deleteBBBPhoto` | `delete_mission_photo` | RPC plus Storage | `mission_photo_submissions` |
| `guessBBBSecret` | `guess_bbb_secret` | RPC | `bbb_assignments`, `events` |
| `sendBBBMessage` | `send_bbb_message` | RPC | `bbb_messages` |
| `getBBBMessages` | `get_bbb_messages` | RPC | `bbb_messages` |
| `getNotices` | `get_notices` | RPC or direct select | `notices`, `notice_reads` |
| `getInquiries` | `get_my_inquiries` | RPC | `inquiries` |
| `postInquiry` | `create_inquiry` | RPC | `inquiries` |
| `editInquiry` | `update_inquiry` | RPC | `inquiries` |
| `deleteInquiry` | `delete_inquiry` | RPC | `inquiries` |

## 관리자 API

| 기존 GAS action | 새 API | 방식 | 주 테이블 |
|---|---|---|---|
| `adminLogin` | Supabase Auth admin role | Auth plus role check | `auth.users`, `profiles` |
| `getUsers` | `admin_get_users` | RPC | `profiles`, `group_members`, `retreat_attendance`, `user_summary` |
| `dashboard` | `admin_dashboard_summary` | RPC | `mission_weeks`, `mission_items`, `mission_progress`, `profiles` |
| `adminGetRaffleAttendance` | `admin_get_participants` | RPC | `profiles`, `retreat_attendance`, `raffle_tickets` |
| `adminDeactivateUser`, `adminRestoreUser` | `admin_set_user_status` | RPC | `profiles`, `events` |
| `adminSetRaffleAttendance` | `admin_set_attendance` | RPC | `retreat_attendance`, `events` |
| `adminSetRaffleExcluded` | `admin_set_raffle_excluded` | RPC | `profiles`, `raffle_tickets`, `events` |
| `adminResetPassword` | `admin-reset-password` | Edge Function plus Auth Admin | `auth.users`, `profiles`, `events` |
| `getCurrentWeek`, `setCurrentWeek` | `admin_get_app_settings`, `admin_set_app_setting` | RPC | `app_settings` |
| `getMissionConfig`, `setMissionConfig` | `admin_get_mission_config`, `admin_set_mission_config` | RPC | `mission_weeks`, `mission_items` |
| `getTabSettings`, `setTabSettings` | `admin_get_tab_settings`, `admin_set_tab_settings` | RPC | `tab_settings` |
| `postNotice`, `editNotice`, `deleteNotice` | `admin_create_notice`, `admin_update_notice`, `admin_delete_notice` | RPC | `notices` |
| `getAdminTrades` | `admin_get_trades` | RPC | `trades` |
| `adminGetBBB` | `admin_get_bbb_assignments` | RPC | `bbb_assignments`, `profiles` |
| `adminWriteBBBRows` | `admin_import_bbb_assignments` | RPC | `bbb_assignments` |
| `adminGetBBBPhotoApprovals` | `admin_get_photo_approvals` | RPC | `mission_photo_submissions`, `profiles` |
| `adminApproveBBBPhoto`, `adminRejectBBBPhoto` | `admin_review_photo_submission` | RPC | `mission_photo_submissions`, `events`, `user_inventory`, `user_cards` |
| `adminFindRaffleTicket` | `admin_find_raffle_ticket` | RPC | `raffle_tickets`, `profiles` |
| `adminGetRaffleTickets` | `admin_get_raffle_tickets` | RPC | `raffle_tickets`, `profiles` |
| `getCardStats`, `setCardReceivedQty` | `admin_card_stats`, `admin_dispatch('setCardReceivedQty')` | RPC | `user_cards`, `physical_card_receipts`, `profiles` |
| `adminCreateCardEvent` | `admin_adjust_card` | RPC | `events`, `user_cards` |
| `adminRebuildEventDerivedViews` | `admin_rebuild_user_state` | RPC | `user_inventory`, `user_cards`, `user_summary`, `raffle_tickets` |
| `replyInquiry` | `admin_reply_inquiry` | RPC | `inquiries` |

## 앱 코드 초안

`app.js`에는 GAS URL을 직접 흩뿌리지 않고 아래 계층을 둔다.

```js
const api = {
  async getUserStatus(options) {
    return callRpc('get_user_status', options);
  },
  async submitMission(payload) {
    return callRpc('submit_pre_mission', payload);
  },
  async drawCardPack(payload) {
    return callRpc('draw_card_pack', payload);
  },
  async getBbbStatus(payload) {
    return callRpc('get_bbb_status', payload);
  },
};
```

이 계층을 먼저 만들면 DEV에서 GAS와 Supabase를 스위치할 수 있다.
