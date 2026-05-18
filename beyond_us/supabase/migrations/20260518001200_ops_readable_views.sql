-- Supabase 운영자가 유저 귀속 행을 닉네임과 함께 읽도록 보조 view를 만든다.
begin;

drop view if exists public.ops_qt_contents;
drop view if exists public.ops_inquiries;
drop view if exists public.ops_notice_reads;
drop view if exists public.ops_notices;
drop view if exists public.ops_physical_card_receipts;
drop view if exists public.ops_trade_prayers;
drop view if exists public.ops_trades;
drop view if exists public.ops_mission_photo_submissions;
drop view if exists public.ops_pilgrim_assignments;
drop view if exists public.ops_bbb_messages;
drop view if exists public.ops_bbb_assignments;
drop view if exists public.ops_hold_pray_hints;
drop view if exists public.ops_hold_pray_guesses;
drop view if exists public.ops_hold_pray_entries;
drop view if exists public.ops_raffle_tickets;
drop view if exists public.ops_mission_progress;
drop view if exists public.ops_mission_submissions;
drop view if exists public.ops_user_summary;
drop view if exists public.ops_user_cards;
drop view if exists public.ops_user_inventory;
drop view if exists public.ops_events;
drop view if exists public.ops_group_members;
drop view if exists public.ops_groups;
drop view if exists public.ops_retreat_attendance;
drop view if exists public.ops_profile_private_notes;
drop view if exists public.ops_tab_settings;
drop view if exists public.ops_app_settings;
drop view if exists public.ops_mission_items;
drop view if exists public.ops_mission_weeks;
drop view if exists public.ops_cards;
drop view if exists public.ops_profiles;

create or replace view public.ops_profiles
with (security_invoker = true)
as
select
  p.participant_code,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.birth_date,
  p.gender,
  p.parish,
  p.role,
  p.account_status,
  p.is_dev,
  p.is_test,
  p.raffle_excluded,
  p.password_migration_required,
  p.legacy_sheet_user_id,
  p.admin_note,
  p.last_login_at,
  p.created_at,
  p.updated_at,
  p.deleted_at,
  p.restored_at,
  p.id,
  p.auth_user_id
from public.profiles p
order by p.created_at desc nulls last, p.participant_no desc nulls last;

comment on view public.ops_profiles is '운영용 프로필 목록. Table Editor에서 최신 가입자와 닉네임을 먼저 확인한다.';

create or replace view public.ops_profile_private_notes
with (security_invoker = true)
as
select
  n.created_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  n.note,
  creator.login_id::text as created_by_login_id,
  creator.display_name as created_by_display_name,
  n.id,
  n.profile_id,
  n.created_by
from public.profile_private_notes n
join public.profiles p on p.id = n.profile_id
left join public.profiles creator on creator.id = n.created_by
order by n.created_at desc, n.id desc;

create or replace view public.ops_retreat_attendance
with (security_invoker = true)
as
select
  a.updated_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  a.attendance_status,
  a.participation_tier,
  a.attended,
  updater.login_id::text as updated_by_login_id,
  updater.display_name as updated_by_display_name,
  a.profile_id,
  a.updated_by
from public.retreat_attendance a
join public.profiles p on p.id = a.profile_id
left join public.profiles updater on updater.id = a.updated_by
order by a.updated_at desc nulls last, p.login_id;

create or replace view public.ops_groups
with (security_invoker = true)
as
select
  g.group_no,
  g.name,
  g.tier,
  g.note,
  g.created_at,
  g.updated_at,
  g.id
from public.groups g
order by g.updated_at desc, g.group_no;

create or replace view public.ops_group_members
with (security_invoker = true)
as
select
  gm.assigned_at,
  g.group_no,
  g.name as group_name,
  g.tier as group_tier,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  gm.group_role,
  assigner.login_id::text as assigned_by_login_id,
  assigner.display_name as assigned_by_display_name,
  gm.group_id,
  gm.profile_id,
  gm.assigned_by
from public.group_members gm
join public.groups g on g.id = gm.group_id
join public.profiles p on p.id = gm.profile_id
left join public.profiles assigner on assigner.id = gm.assigned_by
order by gm.assigned_at desc, g.group_no, p.login_id;

create or replace view public.ops_app_settings
with (security_invoker = true)
as
select key, value_json, value_type, note, updated_at
from public.app_settings
order by updated_at desc, key;

create or replace view public.ops_tab_settings
with (security_invoker = true)
as
select tab_key, label, enabled, status, sort_order, updated_at
from public.tab_settings
order by sort_order, tab_key;

create or replace view public.ops_mission_weeks
with (security_invoker = true)
as
select week_key, week_order, title, starts_on, ends_on, draw_threshold, enabled, created_at, updated_at
from public.mission_weeks
order by week_order;

create or replace view public.ops_mission_items
with (security_invoker = true)
as
select week_key, item_no, item_text, score_weight, category, enabled, created_at, updated_at, id
from public.mission_items
order by updated_at desc, week_key, item_no;

create or replace view public.ops_cards
with (security_invoker = true)
as
select id, name, grade, image_path, enabled, sort_order, created_at, updated_at
from public.cards
order by sort_order, id;

create or replace view public.ops_events
with (security_invoker = true)
as
select
  e.occurred_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  e.event_type,
  e.ref_type,
  e.ref_id,
  e.amount,
  e.week_key,
  e.source,
  e.request_id,
  creator.login_id::text as created_by_login_id,
  creator.display_name as created_by_display_name,
  e.payload,
  e.created_at,
  e.id,
  e.profile_id,
  e.created_by
from public.events e
left join public.profiles p on p.id = e.profile_id
left join public.profiles creator on creator.id = e.created_by
order by e.occurred_at desc, e.created_at desc, e.id desc;

comment on view public.ops_events is 'Events 로그를 닉네임, 이름, 교구와 함께 최신순으로 보는 운영용 view.';

create or replace view public.ops_user_inventory
with (security_invoker = true)
as
select
  i.updated_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  i.normal_pack_earned,
  i.normal_pack_consumed,
  i.normal_pack_remaining,
  i.special_pack_earned,
  i.special_pack_consumed,
  i.special_pack_remaining,
  i.profile_id
from public.user_inventory i
join public.profiles p on p.id = i.profile_id
order by i.updated_at desc, p.login_id;

create or replace view public.ops_user_cards
with (security_invoker = true)
as
select
  uc.updated_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  uc.card_id,
  c.name as card_name,
  c.grade as card_grade,
  uc.quantity,
  uc.first_obtained_at,
  uc.profile_id
from public.user_cards uc
join public.profiles p on p.id = uc.profile_id
join public.cards c on c.id = uc.card_id
order by uc.updated_at desc, p.login_id, uc.card_id;

create or replace view public.ops_user_summary
with (security_invoker = true)
as
select
  s.updated_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  s.mission_count,
  s.total_cards,
  s.raffle_ticket_count,
  s.active_trade_count,
  s.last_activity_at,
  s.payload,
  s.profile_id
from public.user_summary s
join public.profiles p on p.id = s.profile_id
order by s.updated_at desc, p.login_id;

create or replace view public.ops_mission_submissions
with (security_invoker = true)
as
select
  ms.submitted_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  ms.week_key,
  ms.date_key,
  ms.score,
  ms.items_json,
  ms.indices_json,
  ms.request_id,
  ms.id,
  ms.profile_id
from public.mission_submissions ms
join public.profiles p on p.id = ms.profile_id
order by ms.submitted_at desc, ms.date_key desc, p.login_id;

create or replace view public.ops_mission_progress
with (security_invoker = true)
as
select
  mp.updated_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  mp.week_key,
  mp.total_score,
  mp.date_keys,
  mp.slot_counts,
  mp.date_slot_indices,
  mp.submission_event_count,
  mp.profile_id
from public.mission_progress mp
join public.profiles p on p.id = mp.profile_id
order by mp.updated_at desc, mp.week_key, p.login_id;

create or replace view public.ops_raffle_tickets
with (security_invoker = true)
as
select
  rt.updated_at,
  rt.ticket_no,
  rt.active,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  rt.condition_key,
  rc.label as condition_label,
  rt.issued_at,
  rt.revoked_at,
  rt.revoked_reason,
  rt.event_id,
  rt.profile_id
from public.raffle_tickets rt
left join public.profiles p on p.id = rt.profile_id
left join public.raffle_conditions rc on rc.condition_key = rt.condition_key
order by rt.updated_at desc, rt.ticket_no;

comment on view public.ops_raffle_tickets is '추첨권 번호의 활성 상태와 현재 귀속 유저를 닉네임으로 보는 운영용 view.';

create or replace view public.ops_hold_pray_entries
with (security_invoker = true)
as
select
  h.created_at,
  h.updated_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  h.week_key,
  h.content,
  h.anonymous,
  h.visible,
  h.id,
  h.profile_id
from public.hold_pray_entries h
left join public.profiles p on p.id = h.profile_id
order by h.created_at desc, h.id desc;

create or replace view public.ops_hold_pray_guesses
with (security_invoker = true)
as
select
  g.answered_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  g.week_key,
  g.card_index,
  g.guessed_name,
  g.correct,
  g.id,
  g.profile_id
from public.hold_pray_guesses g
join public.profiles p on p.id = g.profile_id
order by g.answered_at desc, g.id desc;

create or replace view public.ops_hold_pray_hints
with (security_invoker = true)
as
select
  h.created_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  h.week_key,
  h.card_index,
  h.hint_text,
  h.id,
  h.profile_id
from public.hold_pray_hints h
join public.profiles p on p.id = h.profile_id
order by h.created_at desc, h.id desc;

create or replace view public.ops_bbb_assignments
with (security_invoker = true)
as
select
  ba.updated_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  care.login_id::text as care_buddy_login_id,
  care.display_name as care_buddy_display_name,
  care.name as care_buddy_name,
  secret.login_id::text as secret_buddy_login_id,
  secret.display_name as secret_buddy_display_name,
  secret.name as secret_buddy_name,
  ba.secret_revealed,
  g.group_no,
  g.name as group_name,
  ba.tier,
  ba.profile_id,
  ba.care_buddy_id,
  ba.secret_buddy_id,
  ba.group_id
from public.bbb_assignments ba
join public.profiles p on p.id = ba.profile_id
left join public.profiles care on care.id = ba.care_buddy_id
left join public.profiles secret on secret.id = ba.secret_buddy_id
left join public.groups g on g.id = ba.group_id
order by ba.updated_at desc, p.login_id;

create or replace view public.ops_bbb_messages
with (security_invoker = true)
as
select
  m.created_at,
  from_p.login_id::text as from_login_id,
  from_p.display_name as from_display_name,
  from_p.name as from_name,
  to_p.login_id::text as to_login_id,
  to_p.display_name as to_display_name,
  to_p.name as to_name,
  m.message,
  m.read_at,
  m.id,
  m.from_profile_id,
  m.to_profile_id
from public.bbb_messages m
join public.profiles from_p on from_p.id = m.from_profile_id
join public.profiles to_p on to_p.id = m.to_profile_id
order by m.created_at desc, m.id desc;

create or replace view public.ops_pilgrim_assignments
with (security_invoker = true)
as
select
  pa.assigned_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  pa.spot_indices,
  pa.completed_at,
  pa.reward_event_id,
  pa.profile_id
from public.pilgrim_assignments pa
join public.profiles p on p.id = pa.profile_id
order by coalesce(pa.completed_at, pa.assigned_at) desc, p.login_id;

create or replace view public.ops_mission_photo_submissions
with (security_invoker = true)
as
select
  ps.created_at,
  ps.updated_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  ps.mission_key,
  ps.spot_index,
  ps.approval_status,
  ps.storage_path,
  approver.login_id::text as approved_by_login_id,
  approver.display_name as approved_by_display_name,
  ps.approved_at,
  rejecter.login_id::text as rejected_by_login_id,
  rejecter.display_name as rejected_by_display_name,
  ps.rejected_at,
  ps.rejection_reason,
  ps.reward_event_id,
  ps.id,
  ps.profile_id,
  ps.approved_by,
  ps.rejected_by
from public.mission_photo_submissions ps
join public.profiles p on p.id = ps.profile_id
left join public.profiles approver on approver.id = ps.approved_by
left join public.profiles rejecter on rejecter.id = ps.rejected_by
order by ps.created_at desc, ps.id desc;

create or replace view public.ops_trades
with (security_invoker = true)
as
select
  t.created_at,
  requester.login_id::text as requester_login_id,
  requester.display_name as requester_display_name,
  requester.name as requester_name,
  t.requester_card_id,
  requester_card.name as requester_card_name,
  target.login_id::text as target_login_id,
  target.display_name as target_display_name,
  target.name as target_name,
  t.target_card_id,
  target_card.name as target_card_name,
  t.status,
  t.resolved_at,
  t.id,
  t.requester_id,
  t.target_id
from public.trades t
join public.profiles requester on requester.id = t.requester_id
join public.profiles target on target.id = t.target_id
join public.cards requester_card on requester_card.id = t.requester_card_id
join public.cards target_card on target_card.id = t.target_card_id
order by t.created_at desc, t.id desc;

create or replace view public.ops_trade_prayers
with (security_invoker = true)
as
select
  tp.prayed_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  t.status as trade_status,
  requester.login_id::text as requester_login_id,
  target.login_id::text as target_login_id,
  tp.trade_id,
  tp.profile_id
from public.trade_prayers tp
join public.profiles p on p.id = tp.profile_id
join public.trades t on t.id = tp.trade_id
join public.profiles requester on requester.id = t.requester_id
join public.profiles target on target.id = t.target_id
order by tp.prayed_at desc, tp.trade_id;

create or replace view public.ops_physical_card_receipts
with (security_invoker = true)
as
select
  r.updated_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  r.card_id,
  c.name as card_name,
  r.received_qty,
  updater.login_id::text as updated_by_login_id,
  updater.display_name as updated_by_display_name,
  r.profile_id,
  r.updated_by
from public.physical_card_receipts r
join public.profiles p on p.id = r.profile_id
join public.cards c on c.id = r.card_id
left join public.profiles updater on updater.id = r.updated_by
order by r.updated_at desc, p.login_id, r.card_id;

create or replace view public.ops_notices
with (security_invoker = true)
as
select id, title, content, image_path, visible, created_at, updated_at
from public.notices
order by created_at desc, id desc;

create or replace view public.ops_notice_reads
with (security_invoker = true)
as
select
  nr.read_at,
  n.title as notice_title,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  nr.notice_id,
  nr.profile_id
from public.notice_reads nr
join public.notices n on n.id = nr.notice_id
join public.profiles p on p.id = nr.profile_id
order by nr.read_at desc, n.created_at desc;

create or replace view public.ops_inquiries
with (security_invoker = true)
as
select
  i.created_at,
  i.updated_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  i.status,
  i.content,
  i.reply,
  replier.login_id::text as reply_by_login_id,
  replier.display_name as reply_by_display_name,
  i.replied_at,
  i.id,
  i.profile_id,
  i.reply_by
from public.inquiries i
left join public.profiles p on p.id = i.profile_id
left join public.profiles replier on replier.id = i.reply_by
order by i.created_at desc, i.id desc;

create or replace view public.ops_qt_contents
with (security_invoker = true)
as
select content_date, title, passage, visible, published_at, updated_at, storage_path, questions
from public.qt_contents
order by content_date desc;

revoke all on table
  public.ops_profiles,
  public.ops_profile_private_notes,
  public.ops_retreat_attendance,
  public.ops_groups,
  public.ops_group_members,
  public.ops_app_settings,
  public.ops_tab_settings,
  public.ops_mission_weeks,
  public.ops_mission_items,
  public.ops_cards,
  public.ops_events,
  public.ops_user_inventory,
  public.ops_user_cards,
  public.ops_user_summary,
  public.ops_mission_submissions,
  public.ops_mission_progress,
  public.ops_raffle_tickets,
  public.ops_hold_pray_entries,
  public.ops_hold_pray_guesses,
  public.ops_hold_pray_hints,
  public.ops_bbb_assignments,
  public.ops_bbb_messages,
  public.ops_pilgrim_assignments,
  public.ops_mission_photo_submissions,
  public.ops_trades,
  public.ops_trade_prayers,
  public.ops_physical_card_receipts,
  public.ops_notices,
  public.ops_notice_reads,
  public.ops_inquiries,
  public.ops_qt_contents
from public, anon, authenticated;

commit;
