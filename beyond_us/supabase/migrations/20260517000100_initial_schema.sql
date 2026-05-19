-- Supabase 핵심 데이터 구조를 생성하는 초기 마이그레이션
begin;

create extension if not exists pgcrypto;
create extension if not exists citext;

do $$
begin
  create type public.profile_role as enum ('user', 'leader', 'admin', 'dev');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.account_status as enum ('active', 'inactive', 'deleted', 'blocked');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.attendance_status as enum ('pending', 'attending', 'partial', 'absent');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.group_role as enum ('member', 'leader', 'assistant');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.tab_status as enum ('open', 'closed');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.event_source as enum ('web', 'admin', 'server', 'migration', 'dev');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.approval_status as enum ('pending', 'approved', 'rejected');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.card_grade as enum ('normal', 'rare', 'hidden');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.trade_status as enum ('requested', 'accepted', 'rejected', 'cancelled', 'expired');
exception when duplicate_object then null;
end $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  participant_no integer unique check (participant_no > 0),
  participant_code text generated always as (lpad(participant_no::text, 3, '0')) stored,
  login_id citext not null unique,
  display_name text,
  name text not null,
  birth_date date,
  gender text,
  parish text not null,
  role public.profile_role not null default 'user',
  account_status public.account_status not null default 'active',
  is_dev boolean not null default false,
  is_test boolean not null default false,
  raffle_excluded boolean not null default false,
  password_migration_required boolean not null default false,
  legacy_sheet_user_id text,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_login_at timestamptz,
  deleted_at timestamptz,
  restored_at timestamptz
);

create trigger set_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create table if not exists public.profile_private_notes (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  note text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.retreat_attendance (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  attendance_status public.attendance_status not null default 'pending',
  participation_tier text,
  attended boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create trigger set_retreat_attendance_updated_at
before update on public.retreat_attendance
for each row execute function public.set_updated_at();

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  group_no integer not null unique check (group_no > 0),
  name text not null,
  tier text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_groups_updated_at
before update on public.groups
for each row execute function public.set_updated_at();

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  group_role public.group_role not null default 'member',
  assigned_at timestamptz not null default now(),
  assigned_by uuid references public.profiles(id) on delete set null,
  primary key (group_id, profile_id),
  unique (profile_id)
);

create table if not exists public.app_settings (
  key text primary key,
  value_json jsonb not null default 'null'::jsonb,
  value_type text not null default 'json',
  note text,
  updated_at timestamptz not null default now()
);

create trigger set_app_settings_updated_at
before update on public.app_settings
for each row execute function public.set_updated_at();

create table if not exists public.tab_settings (
  tab_key text primary key,
  label text not null,
  enabled boolean not null default true,
  status public.tab_status not null default 'open',
  sort_order integer not null default 0,
  updated_at timestamptz not null default now()
);

create trigger set_tab_settings_updated_at
before update on public.tab_settings
for each row execute function public.set_updated_at();

create table if not exists public.mission_weeks (
  week_key text primary key,
  week_order integer not null unique,
  title text not null,
  starts_on date,
  ends_on date,
  draw_threshold integer not null default 6,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_mission_weeks_updated_at
before update on public.mission_weeks
for each row execute function public.set_updated_at();

create table if not exists public.mission_items (
  id uuid primary key default gen_random_uuid(),
  week_key text not null references public.mission_weeks(week_key) on delete cascade,
  item_no integer not null,
  item_text text not null,
  score_weight integer not null default 1,
  category text,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (week_key, item_no)
);

create trigger set_mission_items_updated_at
before update on public.mission_items
for each row execute function public.set_updated_at();

create table if not exists public.cards (
  id smallint primary key check (id between 1 and 99),
  name text not null,
  grade public.card_grade not null default 'normal',
  image_path text,
  enabled boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_cards_updated_at
before update on public.cards
for each row execute function public.set_updated_at();

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default now(),
  profile_id uuid references public.profiles(id) on delete set null,
  event_type text not null,
  ref_type text,
  ref_id text,
  amount integer not null default 0,
  week_key text,
  payload jsonb not null default '{}'::jsonb,
  source public.event_source not null default 'web',
  request_id text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.user_inventory (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  normal_pack_earned integer not null default 0,
  normal_pack_consumed integer not null default 0,
  normal_pack_remaining integer not null default 0,
  special_pack_earned integer not null default 0,
  special_pack_consumed integer not null default 0,
  special_pack_remaining integer not null default 0,
  updated_at timestamptz not null default now(),
  check (normal_pack_earned >= 0),
  check (normal_pack_consumed >= 0),
  check (normal_pack_remaining >= 0),
  check (special_pack_earned >= 0),
  check (special_pack_consumed >= 0),
  check (special_pack_remaining >= 0)
);

create trigger set_user_inventory_updated_at
before update on public.user_inventory
for each row execute function public.set_updated_at();

create table if not exists public.user_cards (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  card_id smallint not null references public.cards(id) on delete restrict,
  quantity integer not null default 0 check (quantity >= 0),
  first_obtained_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (profile_id, card_id)
);

create trigger set_user_cards_updated_at
before update on public.user_cards
for each row execute function public.set_updated_at();

create table if not exists public.user_summary (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  mission_count integer not null default 0,
  total_cards integer not null default 0,
  raffle_ticket_count integer not null default 0,
  active_trade_count integer not null default 0,
  last_activity_at timestamptz,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create trigger set_user_summary_updated_at
before update on public.user_summary
for each row execute function public.set_updated_at();

create table if not exists public.mission_submissions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  week_key text not null references public.mission_weeks(week_key) on delete restrict,
  date_key date not null,
  score integer not null default 0,
  items_json jsonb not null default '[]'::jsonb,
  indices_json jsonb not null default '[]'::jsonb,
  request_id text,
  submitted_at timestamptz not null default now()
);

create table if not exists public.mission_progress (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  week_key text not null references public.mission_weeks(week_key) on delete cascade,
  total_score integer not null default 0,
  date_keys jsonb not null default '[]'::jsonb,
  slot_counts jsonb not null default '{}'::jsonb,
  date_slot_indices jsonb not null default '{}'::jsonb,
  submission_event_count integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (profile_id, week_key)
);

create trigger set_mission_progress_updated_at
before update on public.mission_progress
for each row execute function public.set_updated_at();

create table if not exists public.raffle_conditions (
  condition_key text primary key,
  label text not null,
  enabled boolean not null default true,
  sort_order integer not null default 0
);

create table if not exists public.raffle_tickets (
  ticket_no integer primary key check (ticket_no > 0),
  active boolean not null default false,
  profile_id uuid references public.profiles(id) on delete set null,
  condition_key text references public.raffle_conditions(condition_key) on delete set null,
  issued_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text,
  event_id uuid references public.events(id) on delete set null,
  updated_at timestamptz not null default now()
);

create trigger set_raffle_tickets_updated_at
before update on public.raffle_tickets
for each row execute function public.set_updated_at();

create table if not exists public.hold_pray_entries (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  week_key text,
  content text not null,
  anonymous boolean not null default false,
  visible boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_hold_pray_entries_updated_at
before update on public.hold_pray_entries
for each row execute function public.set_updated_at();

create table if not exists public.hold_pray_guesses (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  week_key text not null,
  card_index integer not null check (card_index >= 0),
  guessed_name text not null,
  correct boolean,
  answered_at timestamptz not null default now(),
  unique (profile_id, week_key, card_index)
);

create table if not exists public.hold_pray_hints (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  week_key text not null,
  card_index integer not null check (card_index >= 0),
  hint_text text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.bbb_assignments (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  care_buddy_id uuid references public.profiles(id) on delete set null,
  secret_buddy_id uuid references public.profiles(id) on delete set null,
  secret_revealed boolean not null default false,
  group_id uuid references public.groups(id) on delete set null,
  tier text,
  updated_at timestamptz not null default now(),
  check (profile_id is distinct from care_buddy_id),
  check (profile_id is distinct from secret_buddy_id)
);

create trigger set_bbb_assignments_updated_at
before update on public.bbb_assignments
for each row execute function public.set_updated_at();

create table if not exists public.bbb_messages (
  id uuid primary key default gen_random_uuid(),
  from_profile_id uuid not null references public.profiles(id) on delete cascade,
  to_profile_id uuid not null references public.profiles(id) on delete cascade,
  message text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create table if not exists public.pilgrim_spots (
  spot_index smallint primary key check (spot_index between 0 and 6),
  label text not null,
  top_percent numeric(5,2) not null check (top_percent >= 0 and top_percent <= 100),
  left_percent numeric(5,2) not null check (left_percent >= 0 and left_percent <= 100),
  enabled boolean not null default true
);

create table if not exists public.pilgrim_assignments (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  spot_indices smallint[] not null,
  assigned_at timestamptz not null default now(),
  completed_at timestamptz,
  reward_event_id uuid references public.events(id) on delete set null,
  check (array_length(spot_indices, 1) = 2)
);

create table if not exists public.mission_photo_submissions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  mission_key text not null,
  spot_index smallint,
  storage_path text not null,
  approval_status public.approval_status not null default 'pending',
  approved_at timestamptz,
  approved_by uuid references public.profiles(id) on delete set null,
  rejected_at timestamptz,
  rejected_by uuid references public.profiles(id) on delete set null,
  rejection_reason text,
  reward_event_id uuid references public.events(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_mission_photo_submissions_updated_at
before update on public.mission_photo_submissions
for each row execute function public.set_updated_at();

create table if not exists public.trades (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  requester_card_id smallint not null references public.cards(id) on delete restrict,
  target_id uuid not null references public.profiles(id) on delete cascade,
  target_card_id smallint not null references public.cards(id) on delete restrict,
  status public.trade_status not null default 'requested',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check (requester_id <> target_id)
);

create table if not exists public.trade_prayers (
  trade_id uuid not null references public.trades(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  prayed_at timestamptz not null default now(),
  primary key (trade_id, profile_id)
);

create table if not exists public.physical_card_receipts (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  card_id smallint not null references public.cards(id) on delete restrict,
  received_qty integer not null default 0 check (received_qty >= 0),
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (profile_id, card_id)
);

create trigger set_physical_card_receipts_updated_at
before update on public.physical_card_receipts
for each row execute function public.set_updated_at();

create table if not exists public.notices (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  content text not null,
  image_path text,
  visible boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_notices_updated_at
before update on public.notices
for each row execute function public.set_updated_at();

create table if not exists public.notice_reads (
  notice_id uuid not null references public.notices(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (notice_id, profile_id)
);

create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  content text not null,
  reply text,
  reply_by uuid references public.profiles(id) on delete set null,
  replied_at timestamptz,
  status text not null default 'open',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_inquiries_updated_at
before update on public.inquiries
for each row execute function public.set_updated_at();

create table if not exists public.qt_contents (
  content_date date primary key,
  title text,
  passage text,
  body text,
  questions jsonb not null default '[]'::jsonb,
  storage_path text,
  visible boolean not null default false,
  published_at timestamptz,
  updated_at timestamptz not null default now()
);

create trigger set_qt_contents_updated_at
before update on public.qt_contents
for each row execute function public.set_updated_at();

create unique index if not exists events_profile_request_uid
on public.events (profile_id, event_type, request_id)
where request_id is not null and request_id <> '';

create unique index if not exists mission_submissions_profile_request_uid
on public.mission_submissions (profile_id, request_id)
where request_id is not null and request_id <> '';

create unique index if not exists mission_photo_submissions_active_uid
on public.mission_photo_submissions (profile_id, mission_key, coalesce(spot_index, -1));

create index if not exists profiles_parish_idx on public.profiles (parish);
create index if not exists profiles_account_status_idx on public.profiles (account_status);
create index if not exists events_profile_occurred_idx on public.events (profile_id, occurred_at desc);
create index if not exists events_type_occurred_idx on public.events (event_type, occurred_at desc);
create index if not exists mission_submissions_profile_week_idx on public.mission_submissions (profile_id, week_key, date_key);
create index if not exists raffle_tickets_profile_idx on public.raffle_tickets (profile_id);
create index if not exists raffle_tickets_active_idx on public.raffle_tickets (active);
create index if not exists bbb_messages_to_profile_idx on public.bbb_messages (to_profile_id, created_at desc);
create index if not exists bbb_messages_from_profile_idx on public.bbb_messages (from_profile_id, created_at desc);
create index if not exists mission_photo_submissions_review_idx on public.mission_photo_submissions (mission_key, approval_status, created_at desc);
create index if not exists trades_requester_idx on public.trades (requester_id, status);
create index if not exists trades_target_idx on public.trades (target_id, status);
create index if not exists inquiries_profile_idx on public.inquiries (profile_id, created_at desc);

insert into public.cards (id, name, grade, sort_order)
values
  (1, '사랑', 'normal', 1),
  (2, '희락', 'normal', 2),
  (3, '화평', 'normal', 3),
  (4, '오래참음', 'normal', 4),
  (5, '자비', 'normal', 5),
  (6, '양선', 'normal', 6),
  (7, '충성', 'normal', 7),
  (8, '온유', 'normal', 8),
  (9, '절제', 'normal', 9),
  (10, '레어', 'rare', 10)
on conflict (id) do update
set name = excluded.name,
    grade = excluded.grade,
    sort_order = excluded.sort_order;

insert into public.raffle_conditions (condition_key, label, enabled, sort_order)
values
  ('app_signup', '앱 가입', true, 1),
  ('card_3', '카드 3종 보유', true, 2),
  ('card_5', '카드 5종 보유', true, 3),
  ('card_10', '카드 10종 보유', true, 4)
on conflict (condition_key) do update
set label = excluded.label,
    enabled = excluded.enabled,
    sort_order = excluded.sort_order;

insert into public.pilgrim_spots (spot_index, label, top_percent, left_percent, enabled)
values
  (0, '좁은문', 48, 45, true),
  (1, '십자가', 33, 65, true),
  (2, '뷰티풀하우스', 62, 48.5, true),
  (3, '사망의 음침한 골짜기', 81, 81, true),
  (4, '기쁨의 산', 16, 86, true),
  (5, '뿔라의 땅', 16, 44, true),
  (6, '천성', 44, 12, true)
on conflict (spot_index) do update
set label = excluded.label,
    top_percent = excluded.top_percent,
    left_percent = excluded.left_percent,
    enabled = excluded.enabled;

insert into public.tab_settings (tab_key, label, enabled, status, sort_order)
values
  ('notice', '공지사항', true, 'open', 10),
  ('mission', '사전미션', true, 'open', 20),
  ('prayer', 'Hold & Pray', true, 'open', 30),
  ('qt', 'Q.T. 말씀 묵상', false, 'closed', 40),
  ('bbb', 'B.B.B 미션', false, 'closed', 50),
  ('pilgrim', '천로역정', false, 'closed', 60),
  ('collection', '카드 컬렉션', true, 'open', 70),
  ('faq', 'QnA', true, 'open', 80),
  ('inquiry', '개발자 문의', true, 'open', 90),
  ('chat', '채팅방', false, 'closed', 100)
on conflict (tab_key) do update
set label = excluded.label,
    enabled = excluded.enabled,
    status = excluded.status,
    sort_order = excluded.sort_order;

insert into public.app_settings (key, value_json, value_type, note)
values
  ('current_week', '1'::jsonb, 'number', '현재 사전미션 주차'),
  ('raffle_visual_cap', '1000'::jsonb, 'number', '추첨권 시각화 최대 기준'),
  ('raffle_visual_max_fill_percent', '90'::jsonb, 'number', '추첨통 최대 채움 비율')
on conflict (key) do update
set value_json = excluded.value_json,
    value_type = excluded.value_type,
    note = excluded.note;

alter table public.profiles enable row level security;
alter table public.profile_private_notes enable row level security;
alter table public.retreat_attendance enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.app_settings enable row level security;
alter table public.tab_settings enable row level security;
alter table public.mission_weeks enable row level security;
alter table public.mission_items enable row level security;
alter table public.cards enable row level security;
alter table public.events enable row level security;
alter table public.user_inventory enable row level security;
alter table public.user_cards enable row level security;
alter table public.user_summary enable row level security;
alter table public.mission_submissions enable row level security;
alter table public.mission_progress enable row level security;
alter table public.raffle_conditions enable row level security;
alter table public.raffle_tickets enable row level security;
alter table public.hold_pray_entries enable row level security;
alter table public.hold_pray_guesses enable row level security;
alter table public.hold_pray_hints enable row level security;
alter table public.bbb_assignments enable row level security;
alter table public.bbb_messages enable row level security;
alter table public.pilgrim_spots enable row level security;
alter table public.pilgrim_assignments enable row level security;
alter table public.mission_photo_submissions enable row level security;
alter table public.trades enable row level security;
alter table public.trade_prayers enable row level security;
alter table public.physical_card_receipts enable row level security;
alter table public.notices enable row level security;
alter table public.notice_reads enable row level security;
alter table public.inquiries enable row level security;
alter table public.qt_contents enable row level security;

commit;
