-- DEV Sheet 이관 결과를 Supabase 정규 테이블과 대조하는 검증 쿼리

-- 1. 최근 이관 batch 상태를 확인한다.
select
  source_environment,
  source_snapshot_label,
  status,
  row_counts->'source' as source_counts,
  row_counts->'targets' as target_counts,
  created_at,
  completed_at,
  notes
from public.migration_batches
where source_environment = 'dev'
order by created_at desc
limit 5;

-- 2. 원본 Sheet row 수와 정규 테이블 row 수를 비교한다.
with legacy_counts as (
  select sheet_name, count(*)::integer as row_count
  from public.legacy_sheet_rows
  where source_environment = 'dev'
  group by sheet_name
),
target_counts as (
  select * from (
    values
      ('Users', 'profiles', (select count(*)::integer from public.profiles)),
      ('Events', 'events', (select count(*)::integer from public.events)),
      ('RaffleTickets', 'raffle_tickets', (select count(*)::integer from public.raffle_tickets)),
      ('Collection', 'user_inventory', (select count(*)::integer from public.user_inventory)),
      ('UserDashboard', 'user_summary', (select count(*)::integer from public.user_summary)),
      ('MissionProgress', 'mission_progress', (select count(*)::integer from public.mission_progress)),
      ('HoldPray', 'hold_pray_entries', (select count(*)::integer from public.hold_pray_entries)),
      ('HPGuesses', 'hold_pray_guesses', (select count(*)::integer from public.hold_pray_guesses)),
      ('BBB', 'bbb_assignments', (select count(*)::integer from public.bbb_assignments)),
      ('BBBMessages', 'bbb_messages', (select count(*)::integer from public.bbb_messages)),
      ('BBBPhotos', 'mission_photo_submissions', (select count(*)::integer from public.mission_photo_submissions)),
      ('CardReceived', 'physical_card_receipts', (select count(*)::integer from public.physical_card_receipts)),
      ('Trades', 'trades', (select count(*)::integer from public.trades)),
      ('Notices', 'notices', (select count(*)::integer from public.notices)),
      ('Inquiries', 'inquiries', (select count(*)::integer from public.inquiries)),
      ('MissionDefinitions', 'mission_items', (select count(*)::integer from public.mission_items))
  ) as rows(sheet_name, target_table, target_count)
)
select
  target_counts.sheet_name,
  target_counts.target_table,
  coalesce(legacy_counts.row_count, 0) as legacy_rows,
  target_counts.target_count,
  case
    when coalesce(legacy_counts.row_count, 0) = target_counts.target_count then 'ok'
    else 'mismatch'
  end as status
from target_counts
left join legacy_counts using (sheet_name)
order by target_counts.sheet_name;

-- 3. Events의 이벤트 타입별 count를 비교한다.
with expected as (
  select
    row_payload->'object'->>'type' as event_type,
    count(*)::integer as event_count
  from public.legacy_sheet_rows
  where source_environment = 'dev'
    and sheet_name = 'Events'
  group by row_payload->'object'->>'type'
),
actual as (
  select event_type, count(*)::integer as event_count
  from public.events
  group by event_type
)
select
  coalesce(expected.event_type, actual.event_type) as event_type,
  coalesce(expected.event_count, 0) as sheet_count,
  coalesce(actual.event_count, 0) as db_count,
  case
    when coalesce(expected.event_count, 0) = coalesce(actual.event_count, 0) then 'ok'
    else 'mismatch'
  end as status
from expected
full join actual using (event_type)
order by event_type;

-- 4. 예상 밖 migration issue가 있는지 확인한다.
select
  severity,
  issue_code,
  sheet_name,
  row_number,
  message,
  payload,
  created_at
from public.migration_issues
where source_environment = 'dev'
  and not (
    issue_code = 'duplicate_tab_key'
    and payload->>'key' in ('qt', 'pilgrim')
  )
order by created_at desc
limit 50;

-- 5. 예상된 duplicate_tab_key 경고만 따로 확인한다.
select
  severity,
  issue_code,
  sheet_name,
  row_number,
  message,
  payload
from public.migration_issues
where source_environment = 'dev'
  and issue_code = 'duplicate_tab_key'
order by row_number;

-- 6. Collection의 카드팩 잔액과 user_inventory를 비교한다.
with src as (
  select
    row_number,
    row_payload->'object' as obj
  from public.legacy_sheet_rows
  where source_environment = 'dev'
    and sheet_name = 'Collection'
),
expected as (
  select
    src.row_number,
    obj->>'userId' as login_id,
    coalesce(nullif(obj->>'누적뽑기권', '')::integer, 0) as normal_pack_earned,
    coalesce(nullif(obj->>'실제뽑은개수', '')::integer, 0) as normal_pack_consumed,
    coalesce(nullif(obj->>'남은개수', '')::integer, 0) as normal_pack_remaining,
    coalesce(nullif(obj->>'specialPackEarned', '')::integer, 0) as special_pack_earned,
    coalesce(nullif(obj->>'specialPackConsumed', '')::integer, 0) as special_pack_consumed,
    coalesce(nullif(obj->>'specialPackRemaining', '')::integer, 0) as special_pack_remaining
  from src
)
select
  expected.login_id,
  expected.row_number,
  expected.normal_pack_earned as sheet_normal_earned,
  inventory.normal_pack_earned as db_normal_earned,
  expected.normal_pack_consumed as sheet_normal_consumed,
  inventory.normal_pack_consumed as db_normal_consumed,
  expected.normal_pack_remaining as sheet_normal_remaining,
  inventory.normal_pack_remaining as db_normal_remaining,
  expected.special_pack_earned as sheet_special_earned,
  inventory.special_pack_earned as db_special_earned,
  expected.special_pack_consumed as sheet_special_consumed,
  inventory.special_pack_consumed as db_special_consumed,
  expected.special_pack_remaining as sheet_special_remaining,
  inventory.special_pack_remaining as db_special_remaining
from expected
join public.profiles profiles on profiles.login_id = expected.login_id
left join public.user_inventory inventory on inventory.profile_id = profiles.id
where
  expected.normal_pack_earned is distinct from inventory.normal_pack_earned
  or expected.normal_pack_consumed is distinct from inventory.normal_pack_consumed
  or expected.normal_pack_remaining is distinct from inventory.normal_pack_remaining
  or expected.special_pack_earned is distinct from inventory.special_pack_earned
  or expected.special_pack_consumed is distinct from inventory.special_pack_consumed
  or expected.special_pack_remaining is distinct from inventory.special_pack_remaining
order by expected.login_id
limit 50;

-- 7. Collection의 카드 보유량과 user_cards를 비교한다.
with src as (
  select
    row_number,
    row_payload->'object' as obj
  from public.legacy_sheet_rows
  where source_environment = 'dev'
    and sheet_name = 'Collection'
),
expected as (
  select
    profiles.id as profile_id,
    profiles.login_id,
    cards.card_id,
    cards.quantity
  from src
  join public.profiles profiles on profiles.login_id = src.obj->>'userId'
  cross join lateral (
    values
      (1, coalesce(nullif(src.obj->>'사랑', '')::integer, 0)),
      (2, coalesce(nullif(src.obj->>'희락', '')::integer, 0)),
      (3, coalesce(nullif(src.obj->>'화평', '')::integer, 0)),
      (4, coalesce(nullif(src.obj->>'오래참음', '')::integer, 0)),
      (5, coalesce(nullif(src.obj->>'자비', '')::integer, 0)),
      (6, coalesce(nullif(src.obj->>'양선', '')::integer, 0)),
      (7, coalesce(nullif(src.obj->>'충성', '')::integer, 0)),
      (8, coalesce(nullif(src.obj->>'온유', '')::integer, 0)),
      (9, coalesce(nullif(src.obj->>'절제', '')::integer, 0)),
      (10, coalesce(nullif(src.obj->>'히든', '')::integer, 0))
  ) as cards(card_id, quantity)
  where cards.quantity > 0
),
actual as (
  select profile_id, card_id, quantity
  from public.user_cards
  where quantity > 0
)
select
  coalesce(expected.login_id, profiles.login_id) as login_id,
  coalesce(expected.card_id, actual.card_id) as card_id,
  coalesce(expected.quantity, 0) as sheet_quantity,
  coalesce(actual.quantity, 0) as db_quantity
from expected
full join actual
  on actual.profile_id = expected.profile_id
 and actual.card_id = expected.card_id
left join public.profiles profiles on profiles.id = actual.profile_id
where coalesce(expected.quantity, 0) <> coalesce(actual.quantity, 0)
order by login_id, card_id
limit 50;

-- 8. RaffleTickets의 활성 추첨권 수를 유저별로 비교한다.
with expected as (
  select
    row_payload->'object'->>'userId' as login_id,
    count(*)::integer as active_tickets
  from public.legacy_sheet_rows
  where source_environment = 'dev'
    and sheet_name = 'RaffleTickets'
    and lower(coalesce(row_payload->'object'->>'active', '')) in ('1', 'true', 'yes', 'y', 'checked', '✓')
  group by row_payload->'object'->>'userId'
),
actual as (
  select
    profiles.login_id,
    count(*)::integer as active_tickets
  from public.raffle_tickets tickets
  join public.profiles profiles on profiles.id = tickets.profile_id
  where tickets.active = true
  group by profiles.login_id
)
select
  coalesce(expected.login_id, actual.login_id) as login_id,
  coalesce(expected.active_tickets, 0) as sheet_active_tickets,
  coalesce(actual.active_tickets, 0) as db_active_tickets
from expected
full join actual using (login_id)
where coalesce(expected.active_tickets, 0) <> coalesce(actual.active_tickets, 0)
order by login_id
limit 50;

-- 9. MissionProgress projection을 비교한다.
with expected as (
  select
    row_payload->'object'->>'userId' as login_id,
    row_payload->'object'->>'weekKey' as week_key,
    coalesce(nullif(row_payload->'object'->>'totalScore', '')::integer, 0) as total_score,
    coalesce(nullif(row_payload->'object'->>'submissionEventCount', '')::integer, 0) as submission_event_count
  from public.legacy_sheet_rows
  where source_environment = 'dev'
    and sheet_name = 'MissionProgress'
),
actual as (
  select
    profiles.login_id,
    progress.week_key,
    progress.total_score,
    progress.submission_event_count
  from public.mission_progress progress
  join public.profiles profiles on profiles.id = progress.profile_id
)
select
  coalesce(expected.login_id, actual.login_id) as login_id,
  coalesce(expected.week_key, actual.week_key) as week_key,
  coalesce(expected.total_score, 0) as sheet_total_score,
  coalesce(actual.total_score, 0) as db_total_score,
  coalesce(expected.submission_event_count, 0) as sheet_submission_event_count,
  coalesce(actual.submission_event_count, 0) as db_submission_event_count
from expected
full join actual using (login_id, week_key)
where
  coalesce(expected.total_score, 0) <> coalesce(actual.total_score, 0)
  or coalesce(expected.submission_event_count, 0) <> coalesce(actual.submission_event_count, 0)
order by login_id, week_key
limit 50;

-- 10. UserDashboard의 주요 요약값과 user_summary를 비교한다.
with expected as (
  select
    row_payload->'object'->>'userId' as login_id,
    coalesce(nullif(row_payload->'object'->>'missionCount', '')::integer, 0) as mission_count,
    coalesce(nullif(row_payload->'object'->>'totalCards', '')::integer, 0) as total_cards,
    coalesce(nullif(row_payload->'object'->>'activeTrades', '')::integer, 0) as active_trade_count
  from public.legacy_sheet_rows
  where source_environment = 'dev'
    and sheet_name = 'UserDashboard'
),
actual as (
  select
    profiles.login_id,
    summary.mission_count,
    summary.total_cards,
    summary.active_trade_count
  from public.user_summary summary
  join public.profiles profiles on profiles.id = summary.profile_id
)
select
  coalesce(expected.login_id, actual.login_id) as login_id,
  coalesce(expected.mission_count, 0) as sheet_mission_count,
  coalesce(actual.mission_count, 0) as db_mission_count,
  coalesce(expected.total_cards, 0) as sheet_total_cards,
  coalesce(actual.total_cards, 0) as db_total_cards,
  coalesce(expected.active_trade_count, 0) as sheet_active_trade_count,
  coalesce(actual.active_trade_count, 0) as db_active_trade_count
from expected
full join actual using (login_id)
where
  coalesce(expected.mission_count, 0) <> coalesce(actual.mission_count, 0)
  or coalesce(expected.total_cards, 0) <> coalesce(actual.total_cards, 0)
  or coalesce(expected.active_trade_count, 0) <> coalesce(actual.active_trade_count, 0)
order by login_id
limit 50;

-- 11. 추첨권 제외 유저에게 활성 추첨권이 남아있는지 확인한다.
select
  profiles.login_id,
  profiles.name,
  profiles.parish,
  count(tickets.ticket_no) as active_tickets
from public.profiles profiles
join public.raffle_tickets tickets on tickets.profile_id = profiles.id
where profiles.raffle_excluded = true
  and tickets.active = true
group by profiles.login_id, profiles.name, profiles.parish
order by profiles.login_id;

-- 12. Auth 사용자 연결 상태를 확인한다.
select
  count(*)::integer as profiles,
  count(auth_user_id)::integer as linked_profiles,
  (count(*) - count(auth_user_id))::integer as missing_auth_links
from public.profiles;

select
  participant_no,
  login_id,
  name,
  role,
  account_status,
  password_migration_required
from public.profiles
where auth_user_id is null
order by participant_no
limit 20;
