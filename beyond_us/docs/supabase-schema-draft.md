# Supabase 스키마 초안

## 핵심 원칙

유저를 열었을 때 필요한 모든 정보는 조회 결과에 모여야 한다. 하지만 저장은 한 테이블에 몰지 않고, 기능별 테이블을 `user_id`로 연결한다.

## Auth와 유저

| table | 역할 | 주요 컬럼 |
|---|---|---|
| `auth.users` | Supabase Auth 기본 계정 | Supabase 관리 |
| `profiles` | 앱 유저 기본 정보 | `id`, `auth_user_id`, `participant_no`, `login_id`, `display_name`, `name`, `birth_date`, `gender`, `parish`, `role`, `account_status`, `is_dev`, `is_test`, `raffle_excluded`, `created_at`, `last_login_at`, `deleted_at`, `admin_note` |
| `profile_private_notes` | 민감하거나 운영진 전용 메모 | `profile_id`, `note`, `created_by`, `created_at` |

- `profiles.login_id`는 대소문자를 구분하는 `text`다.
- Supabase Auth email은 실제 이메일이 아니라 `u_<sha256(trim(login_id))>@auth.beyond-us.local` 형식의 내부 synthetic email을 사용한다.
- 기존 Sheet 계정은 `password_migration_required=true`로 이관한 뒤 사용자 재설정 흐름에서 새 Auth 비밀번호를 설정한다.

## 수련회 운영 정보

| table | 역할 | 주요 컬럼 |
|---|---|---|
| `retreat_attendance` | 참석, 부분참여 상태 | `profile_id`, `attendance_status`, `participation_tier`, `attended`, `updated_by`, `updated_at` |
| `groups` | 조 정보 | `id`, `group_no`, `name`, `tier`, `note` |
| `group_members` | 조 배정과 역할 | `group_id`, `profile_id`, `group_role`, `assigned_at`, `assigned_by` |

## 설정

| table | 역할 | 주요 컬럼 |
|---|---|---|
| `app_settings` | 전역 설정 | `key`, `value_json`, `value_type`, `note`, `updated_at` |
| `tab_settings` | 유저 앱 탭 표시와 상태 | `tab_key`, `label`, `enabled`, `status`, `sort_order`, `updated_at` |
| `mission_weeks` | 주차 정의 | `week_key`, `week_order`, `title`, `starts_on`, `ends_on`, `draw_threshold`, `enabled` |
| `mission_items` | 사전미션 항목 | `id`, `week_key`, `item_no`, `item_text`, `score_weight`, `category`, `enabled` |

## 이벤트와 현재 상태

| table | 역할 | 주요 컬럼 |
|---|---|---|
| `events` | 모든 변화의 원장 | `id`, `occurred_at`, `profile_id`, `event_type`, `ref_type`, `ref_id`, `amount`, `week_key`, `payload`, `source`, `created_by` |
| `user_inventory` | 카드팩과 재화 현재 잔액 | `profile_id`, `normal_pack_earned`, `normal_pack_consumed`, `normal_pack_remaining`, `special_pack_earned`, `special_pack_consumed`, `special_pack_remaining`, `updated_at` |
| `cards` | 카드 마스터 | `id`, `name`, `grade`, `image_path`, `enabled` |
| `user_cards` | 현재 카드 보유 수량 | `profile_id`, `card_id`, `quantity`, `first_obtained_at`, `updated_at` |
| `user_summary` | 유저 대시보드 캐시 | `profile_id`, `mission_count`, `total_cards`, `raffle_ticket_count`, `active_trade_count`, `last_activity_at`, `payload`, `updated_at` |

## 사전미션

| table | 역할 | 주요 컬럼 |
|---|---|---|
| `mission_submissions` | 사전미션 제출 | `id`, `profile_id`, `week_key`, `date_key`, `score`, `items_json`, `indices_json`, `request_id`, `submitted_at` |
| `mission_progress` | 유저 주차별 집계 | `profile_id`, `week_key`, `total_score`, `date_keys`, `slot_counts`, `updated_at` |

## 추첨권

| table | 역할 | 주요 컬럼 |
|---|---|---|
| `raffle_tickets` | 추첨권 번호 단위 관리 | `ticket_no`, `active`, `profile_id`, `condition_key`, `issued_at`, `revoked_at`, `revoked_reason`, `event_id` |
| `raffle_conditions` | 추첨권 조건 정의 | `condition_key`, `label`, `enabled`, `sort_order` |

## H&P

| table | 역할 | 주요 컬럼 |
|---|---|---|
| `hold_pray_entries` | H&P 본문 | `id`, `profile_id`, `week_key`, `content`, `anonymous`, `visible`, `created_at` |
| `hold_pray_guesses` | H&P 추측 | `id`, `profile_id`, `week_key`, `card_index`, `guessed_name`, `correct`, `answered_at` |
| `hold_pray_hints` | H&P 힌트 | `id`, `profile_id`, `week_key`, `card_index`, `hint_text`, `created_at` |

## BBB와 천로역정

| table | 역할 | 주요 컬럼 |
|---|---|---|
| `bbb_assignments` | 케어버디, 시크릿버디 매칭 | `profile_id`, `care_buddy_id`, `secret_buddy_id`, `secret_revealed`, `group_id`, `tier`, `updated_at` |
| `bbb_messages` | BBB 메시지 | `id`, `from_profile_id`, `to_profile_id`, `message`, `created_at`, `read_at` |
| `mission_photo_submissions` | BBB와 천로역정 사진 제출 | `id`, `profile_id`, `mission_key`, `spot_index`, `storage_path`, `approval_status`, `approved_at`, `approved_by`, `reward_event_id`, `created_at` |
| `pilgrim_spots` | 천로역정 스팟 마스터 | `spot_index`, `label`, `top_percent`, `left_percent`, `enabled` |
| `pilgrim_assignments` | 유저별 랜덤 2스팟 | `profile_id`, `spot_indices`, `assigned_at`, `completed_at`, `reward_event_id` |

## 카드 교환과 실물 수령

| table | 역할 | 주요 컬럼 |
|---|---|---|
| `trades` | 교환 요청 | `id`, `requester_id`, `requester_card_id`, `target_id`, `target_card_id`, `status`, `created_at`, `resolved_at` |
| `trade_prayers` | 교환 기도 체크 | `trade_id`, `profile_id`, `prayed_at` |
| `physical_card_receipts` | 실물 카드 수령 | `profile_id`, `card_id`, `received_qty`, `updated_by`, `updated_at` |

## 공지와 문의

| table | 역할 | 주요 컬럼 |
|---|---|---|
| `notices` | 공지 | `id`, `title`, `content`, `image_path`, `visible`, `created_at`, `updated_at` |
| `notice_reads` | 공지 읽음 상태 | `notice_id`, `profile_id`, `read_at` |
| `inquiries` | 개발자 문의 | `id`, `profile_id`, `content`, `reply`, `reply_by`, `replied_at`, `status`, `created_at`, `updated_at` |

## 이관 감사

| table | 역할 | 주요 컬럼 |
|---|---|---|
| `migration_batches` | DEV/PROD Sheet 이관 실행 단위 | `id`, `source_environment`, `source_snapshot_label`, `status`, `row_counts`, `created_at` |
| `legacy_sheet_rows` | 원본 Sheet row 보관 | `batch_id`, `source_environment`, `sheet_name`, `row_number`, `row_key`, `source_hash`, `row_payload` |
| `legacy_import_refs` | 원본 row와 Supabase 변환 row 연결 | `legacy_row_id`, `target_table`, `target_pk`, `target_event_type`, `transform_note` |
| `migration_issues` | 이관 중 발견한 충돌과 검증 실패 | `batch_id`, `severity`, `issue_code`, `message`, `payload`, `resolved` |

## Storage bucket

| bucket | 용도 |
|---|---|
| `notice-images` | 공지 이미지 |
| `mission-photos` | BBB, 천로역정 인증 사진 |
| `qt-pages` | 날짜별 QT PDF 또는 이미지 |
| `card-assets` | 카드 이미지 |
