# 조별 엑셀 원본을 Supabase 조 명단 import migration으로 변환한다.
from __future__ import annotations

from pathlib import Path

from match_group_profiles import GROUP_FILE, extract_group_roster, group_sort_key


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_SQL = ROOT / "beyond_us" / "supabase" / "migrations" / "20260618000200_group_roster_import.sql"
BATCH_KEY = "20260614"


def sql_string(value: object) -> str:
    if value is None:
        return "null"
    text = str(value)
    return "'" + text.replace("'", "''") + "'"


def sql_int(value: object) -> str:
    if value in (None, "", "null"):
        return "null"
    return str(int(value))


def role_to_sql(role: str) -> str:
    clean = str(role or "").strip()
    if clean == "조장":
        return "leader"
    if clean == "부조장":
        return "assistant"
    return "member"


def group_no_value(group_no: str) -> str:
    text = str(group_no or "").strip()
    if text.endswith("조") and text[:-1].isdigit():
        return text[:-1]
    return "null"


def main() -> None:
    roster = extract_group_roster(GROUP_FILE)
    group_values = []
    for no in range(1, 17):
        group_values.append(f"  ({no}, '{no}조')")

    roster_values = []
    for idx, person in enumerate(sorted(roster, key=lambda p: (group_sort_key(p.group_no), p.source_sheet, p.source_row)), start=1):
        roster_values.append(
            "  ("
            + ", ".join(
                [
                    sql_string(BATCH_KEY),
                    sql_int(idx),
                    sql_int(group_no_value(person.group_no)),
                    sql_string(person.group_no),
                    sql_string(role_to_sql(person.role)),
                    sql_string(person.role),
                    sql_string(person.name),
                    sql_string(person.birth_year),
                    sql_string(person.parish_raw),
                    sql_string(person.schedule),
                    sql_string(person.note),
                    sql_string(person.source_sheet),
                    sql_int(person.source_row),
                ]
            )
            + ")"
        )

    sql = f"""-- 조별 데이터 정리 6_14.xlsx 기준으로 B.B.B. 조 원본 명단과 앱 프로필 매칭을 구성한다.
begin;

create table if not exists public.retreat_group_roster (
  id uuid primary key default gen_random_uuid(),
  source_batch text not null,
  roster_order integer not null,
  group_no integer,
  group_label text not null,
  group_id uuid references public.groups(id) on delete set null,
  group_role public.group_role not null default 'member',
  raw_role text,
  participant_name text not null,
  name_norm text not null default '',
  birth_year text,
  parish_raw text,
  parish_norm text,
  participation_schedule text,
  participation_tier text,
  note text,
  source_sheet text,
  source_row integer,
  matched_profile_id uuid references public.profiles(id) on delete set null,
  match_status text not null default 'pending',
  match_detail text,
  candidate_profiles jsonb not null default '[]'::jsonb,
  care_buddy_roster_id uuid,
  secret_buddy_roster_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_batch, roster_order)
);

alter table public.retreat_group_roster
add column if not exists care_buddy_roster_id uuid;

alter table public.retreat_group_roster
add column if not exists secret_buddy_roster_id uuid;

create index if not exists retreat_group_roster_batch_idx
on public.retreat_group_roster (source_batch, group_no, roster_order);

create index if not exists retreat_group_roster_profile_idx
on public.retreat_group_roster (matched_profile_id)
where matched_profile_id is not null;

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'set_retreat_group_roster_updated_at'
      and tgrelid = 'public.retreat_group_roster'::regclass
  ) then
    create trigger set_retreat_group_roster_updated_at
    before update on public.retreat_group_roster
    for each row execute function public.set_updated_at();
  end if;
end;
$$;

alter table public.retreat_group_roster enable row level security;
revoke all on public.retreat_group_roster from public, anon, authenticated;

comment on table public.retreat_group_roster is '조 편성 원본 명단. 앱 가입자가 없어도 admin BBB 매칭 화면에 조원으로 표시한다.';
comment on column public.retreat_group_roster.match_status is 'matched, matched_by_parish, nickname_missing, duplicate_same_parish, duplicate_roster_same_parish, duplicate_needs_check 등 앱 가입자 매칭 상태.';

create or replace function public.bu_group_roster_normalize_name(p_value text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(coalesce(p_value, ''), '\\s+', '', 'g'));
$$;

create or replace function public.bu_group_roster_normalize_parish(p_value text)
returns text
language sql
immutable
as $$
  select case
    when regexp_replace(upper(coalesce(p_value, '')), '\\s+', '', 'g') like '%VIP%' then 'VIP'
    when regexp_replace(coalesce(p_value, ''), '\\s+', '', 'g') like '%교회학교%' then '교회학교'
    when regexp_replace(coalesce(p_value, ''), '\\s+', '', 'g') like '%목양%' then '목양교구'
    when regexp_replace(coalesce(p_value, ''), '\\s+', '', 'g') ~ '1(청|교구|청년)' then '1청'
    when regexp_replace(coalesce(p_value, ''), '\\s+', '', 'g') ~ '2(청|교구|청년)' then '2청'
    when regexp_replace(coalesce(p_value, ''), '\\s+', '', 'g') ~ '3(청|교구|청년)' then '3청'
    when regexp_replace(coalesce(p_value, ''), '\\s+', '', 'g') ~ '4(청|교구|청년)' then '4청'
    else trim(coalesce(p_value, ''))
  end;
$$;

create or replace function public.bu_group_roster_tier(p_schedule text)
returns text
language sql
immutable
as $$
  select case
    when regexp_replace(coalesce(p_schedule, ''), '\\s+', '', 'g') like '%전체참석%' then '전참'
    when regexp_replace(coalesce(p_schedule, ''), '\\s+', '', 'g') like '%토요일%' then '토참'
    when regexp_replace(coalesce(p_schedule, ''), '\\s+', '', 'g') like '%주일%' then '일참'
    else '전참'
  end;
$$;

insert into public.groups (group_no, name)
values
{",\n".join(group_values)}
on conflict (group_no) do update
set name = excluded.name,
    updated_at = now();

delete from public.retreat_group_roster
where source_batch = {sql_string(BATCH_KEY)};

insert into public.retreat_group_roster (
  source_batch,
  roster_order,
  group_no,
  group_label,
  group_role,
  raw_role,
  participant_name,
  birth_year,
  parish_raw,
  participation_schedule,
  note,
  source_sheet,
  source_row
)
values
{",\n".join(roster_values)};

update public.retreat_group_roster r
set group_id = g.id,
    name_norm = public.bu_group_roster_normalize_name(r.participant_name),
    parish_norm = public.bu_group_roster_normalize_parish(r.parish_raw),
    participation_tier = public.bu_group_roster_tier(r.participation_schedule)
from public.groups g
where r.source_batch = {sql_string(BATCH_KEY)}
  and r.group_no = g.group_no;

update public.retreat_group_roster r
set name_norm = public.bu_group_roster_normalize_name(r.participant_name),
    parish_norm = public.bu_group_roster_normalize_parish(r.parish_raw),
    participation_tier = public.bu_group_roster_tier(r.participation_schedule)
where r.source_batch = {sql_string(BATCH_KEY)}
  and r.group_no is null;

with roster_duplicates as (
  select
    r.id as roster_id,
    count(*) over (partition by r.name_norm)::integer as roster_name_count,
    count(*) over (partition by r.name_norm, r.parish_norm)::integer as roster_same_parish_count
  from public.retreat_group_roster r
  where r.source_batch = {sql_string(BATCH_KEY)}
),
candidate_stats as (
  select
    r.id as roster_id,
    max(rd.roster_name_count)::integer as roster_name_count,
    max(rd.roster_same_parish_count)::integer as roster_same_parish_count,
    count(p.id)::integer as candidate_count,
    count(p.id) filter (
      where public.bu_group_roster_normalize_parish(p.parish) = r.parish_norm
    )::integer as same_parish_count,
    (array_agg(p.id order by p.parish, p.name, p.login_id::text) filter (
      where p.id is not null
    ))[1] as single_candidate_id,
    (array_agg(p.id order by p.parish, p.name, p.login_id::text) filter (
      where p.id is not null
        and public.bu_group_roster_normalize_parish(p.parish) = r.parish_norm
    ))[1] as same_parish_candidate_id,
    coalesce(jsonb_agg(
      jsonb_build_object(
        'profileId', p.id,
        'loginId', p.login_id,
        'name', p.name,
        'displayName', p.display_name,
        'parish', p.parish,
        'participantCode', p.participant_code
      )
      order by p.parish, p.name, p.login_id::text
    ) filter (where p.id is not null), '[]'::jsonb) as candidates
  from public.retreat_group_roster r
  join roster_duplicates rd on rd.roster_id = r.id
  left join public.profiles p
    on public.bu_group_roster_normalize_name(p.name) = r.name_norm
   and p.account_status = 'active'
   and p.is_dev = false
   and p.is_test = false
  where r.source_batch = {sql_string(BATCH_KEY)}
  group by r.id
)
update public.retreat_group_roster r
set candidate_profiles = c.candidates,
    matched_profile_id = case
      when c.roster_same_parish_count > 1 then null
      when c.candidate_count = 1 and c.roster_name_count = 1 then c.single_candidate_id
      when c.same_parish_count = 1 then c.same_parish_candidate_id
      else null
    end,
    match_status = case
      when c.roster_same_parish_count > 1 then 'duplicate_roster_same_parish'
      when c.candidate_count = 0 then 'nickname_missing'
      when c.candidate_count = 1 and c.roster_name_count = 1 then 'matched'
      when c.same_parish_count = 1 then 'matched_by_parish'
      when c.same_parish_count > 1 then 'duplicate_same_parish'
      else 'duplicate_needs_check'
    end,
    match_detail = case
      when c.roster_same_parish_count > 1 then '이름 중복 확인필요 - 조 명단 같은 청 중복'
      when c.candidate_count = 0 then '닉네임 없음'
      when c.candidate_count = 1 and c.roster_name_count = 1 then '매칭'
      when c.same_parish_count = 1 then '교구 기준 매칭'
      when c.same_parish_count > 1 then '이름 중복 확인필요 - 같은 청'
      else '이름 중복 확인필요 - 다른 청 후보'
    end,
    updated_at = now()
from candidate_stats c
where r.id = c.roster_id;

create or replace function public.bu_sync_group_roster_profile_matches(
  p_source_batch text default {sql_string(BATCH_KEY)}
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_matched integer := 0;
  v_group_members integer := 0;
  v_assignments integer := 0;
begin
  with roster_duplicates as (
    select
      r.id as roster_id,
      count(*) over (partition by r.name_norm)::integer as roster_name_count,
      count(*) over (partition by r.name_norm, r.parish_norm)::integer as roster_same_parish_count
    from public.retreat_group_roster r
    where r.source_batch = p_source_batch
  ),
  candidate_stats as (
    select
      r.id as roster_id,
      max(rd.roster_name_count)::integer as roster_name_count,
      max(rd.roster_same_parish_count)::integer as roster_same_parish_count,
      count(p.id)::integer as candidate_count,
      count(p.id) filter (
        where public.bu_group_roster_normalize_parish(p.parish) = r.parish_norm
      )::integer as same_parish_count,
      (array_agg(p.id order by p.parish, p.name, p.login_id::text) filter (
        where p.id is not null
      ))[1] as single_candidate_id,
      (array_agg(p.id order by p.parish, p.name, p.login_id::text) filter (
        where p.id is not null
          and public.bu_group_roster_normalize_parish(p.parish) = r.parish_norm
      ))[1] as same_parish_candidate_id,
      coalesce(jsonb_agg(
        jsonb_build_object(
          'profileId', p.id,
          'loginId', p.login_id,
          'name', p.name,
          'displayName', p.display_name,
          'parish', p.parish,
          'participantCode', p.participant_code
        )
        order by p.parish, p.name, p.login_id::text
      ) filter (where p.id is not null), '[]'::jsonb) as candidates
    from public.retreat_group_roster r
    join roster_duplicates rd on rd.roster_id = r.id
    left join public.profiles p
      on public.bu_group_roster_normalize_name(p.name) = r.name_norm
     and p.account_status = 'active'
     and p.is_dev = false
     and p.is_test = false
    where r.source_batch = p_source_batch
    group by r.id
  ),
  updated as (
    update public.retreat_group_roster r
    set candidate_profiles = c.candidates,
        matched_profile_id = case
          when r.match_status = 'matched_manual' then r.matched_profile_id
          when c.roster_same_parish_count > 1 then null
          when c.candidate_count = 1 and c.roster_name_count = 1 then c.single_candidate_id
          when c.same_parish_count = 1 then c.same_parish_candidate_id
          else null
        end,
        match_status = case
          when r.match_status = 'matched_manual' then r.match_status
          when c.roster_same_parish_count > 1 then 'duplicate_roster_same_parish'
          when c.candidate_count = 0 then 'nickname_missing'
          when c.candidate_count = 1 and c.roster_name_count = 1 then 'matched'
          when c.same_parish_count = 1 then 'matched_by_parish'
          when c.same_parish_count > 1 then 'duplicate_same_parish'
          else 'duplicate_needs_check'
        end,
        match_detail = case
          when r.match_status = 'matched_manual' then r.match_detail
          when c.roster_same_parish_count > 1 then '이름 중복 확인필요 - 조 명단 같은 청 중복'
          when c.candidate_count = 0 then '닉네임 없음'
          when c.candidate_count = 1 and c.roster_name_count = 1 then '매칭'
          when c.same_parish_count = 1 then '교구 기준 매칭'
          when c.same_parish_count > 1 then '이름 중복 확인필요 - 같은 청'
          else '이름 중복 확인필요 - 다른 청 후보'
        end,
        updated_at = now()
    from candidate_stats c
    where r.id = c.roster_id
    returning r.id
  )
  select count(*)::integer into v_matched from updated;

  insert into public.group_members (
    group_id,
    profile_id,
    group_role,
    assigned_at
  )
  select
    r.group_id,
    r.matched_profile_id,
    r.group_role,
    now()
  from public.retreat_group_roster r
  where r.source_batch = p_source_batch
    and r.group_id is not null
    and r.matched_profile_id is not null
  on conflict (profile_id) do update
  set group_id = excluded.group_id,
      group_role = excluded.group_role,
      assigned_at = now();

  get diagnostics v_group_members = row_count;

  insert into public.bbb_assignments (
    profile_id,
    care_buddy_id,
    group_id,
    tier,
    updated_at
  )
  select
    r.matched_profile_id,
    care.matched_profile_id,
    r.group_id,
    coalesce(r.participation_tier, '전참'),
    now()
  from public.retreat_group_roster r
  join public.retreat_group_roster care
    on care.id = r.care_buddy_roster_id
  where r.source_batch = p_source_batch
    and r.matched_profile_id is not null
    and care.matched_profile_id is not null
  on conflict (profile_id) do update
  set care_buddy_id = excluded.care_buddy_id,
      group_id = excluded.group_id,
      tier = excluded.tier,
      updated_at = now();

  get diagnostics v_assignments = row_count;

  insert into public.bbb_assignments (
    profile_id,
    secret_buddy_id,
    group_id,
    tier,
    updated_at
  )
  select
    secret.matched_profile_id,
    r.matched_profile_id,
    secret.group_id,
    coalesce(secret.participation_tier, '전참'),
    now()
  from public.retreat_group_roster r
  join public.retreat_group_roster secret
    on secret.id = r.care_buddy_roster_id
  where r.source_batch = p_source_batch
    and r.matched_profile_id is not null
    and secret.matched_profile_id is not null
  on conflict (profile_id) do update
  set secret_buddy_id = excluded.secret_buddy_id,
      group_id = excluded.group_id,
      tier = excluded.tier,
      updated_at = now();

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'sourceBatch', p_source_batch,
    'matchedRowsTouched', v_matched,
    'groupMembersTouched', v_group_members,
    'assignmentsTouched', v_assignments
  );
end;
$$;

revoke all on function public.bu_sync_group_roster_profile_matches(text) from public, anon, authenticated;
grant execute on function public.bu_sync_group_roster_profile_matches(text) to authenticated;

create or replace function public.bu_sync_group_roster_profile_matches_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.bu_sync_group_roster_profile_matches({sql_string(BATCH_KEY)});
  return new;
end;
$$;

drop trigger if exists sync_group_roster_profile_after_change on public.profiles;
create trigger sync_group_roster_profile_after_change
after insert or update of name, parish, account_status, is_dev, is_test
on public.profiles
for each row execute function public.bu_sync_group_roster_profile_matches_trigger();

select public.bu_sync_group_roster_profile_matches({sql_string(BATCH_KEY)});

delete from public.group_members gm
using public.groups g
where gm.group_id = g.id
  and g.group_no between 1 and 16
  and not exists (
    select 1
    from public.retreat_group_roster r
    where r.source_batch = {sql_string(BATCH_KEY)}
      and r.matched_profile_id = gm.profile_id
      and r.group_id = gm.group_id
  );

insert into public.group_members (
  group_id,
  profile_id,
  group_role,
  assigned_at
)
select
  group_id,
  matched_profile_id,
  group_role,
  now()
from public.retreat_group_roster
where source_batch = {sql_string(BATCH_KEY)}
  and group_id is not null
  and matched_profile_id is not null
on conflict (profile_id) do update
set group_id = excluded.group_id,
    group_role = excluded.group_role,
    assigned_at = now();

create or replace function public.admin_get_bbb_matching_matrix()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_batch text := {sql_string(BATCH_KEY)};
  v_rows jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  with roster_rows as (
    select
      jsonb_build_object(
        'rowType', 'roster',
        'rosterId', r.id,
        'sourceBatch', r.source_batch,
        'profileId', u.id,
        'canMatch', true,
        'hasProfile', u.id is not null,
        'loginId', u.login_id,
        'userId', u.login_id,
        'name', r.participant_name,
        'displayName', coalesce(u.display_name, ''),
        'participantCode', coalesce(u.participant_code, ''),
        'parish', coalesce(u.parish, r.parish_raw, ''),
        'rosterParish', coalesce(r.parish_raw, ''),
        'parishNorm', coalesce(r.parish_norm, ''),
        'groupId', r.group_id,
        'groupNo', r.group_no,
        'groupLabel', r.group_label,
        'groupName', case when r.group_no is null then r.group_label else coalesce(g.name, r.group_label) end,
        'groupTier', coalesce(g.tier, ''),
        'groupRole', coalesce(r.group_role::text, ''),
        'rawRole', coalesce(r.raw_role, ''),
        'participationTier', coalesce(r.participation_tier, ''),
        'matchingTier', coalesce(r.participation_tier, ''),
        'participationSchedule', coalesce(r.participation_schedule, ''),
        'attendanceStatus', coalesce(ra.attendance_status::text, ''),
        'matchStatus', r.match_status,
        'matchDetail', coalesce(r.match_detail, ''),
        'candidateProfiles', r.candidate_profiles,
        'careBuddyRosterId', r.care_buddy_roster_id,
        'careBuddyId', coalesce(ba.care_buddy_id, care_roster.matched_profile_id),
        'careBuddyLoginId', coalesce(care.login_id, care_roster_profile.login_id),
        'careBuddyName', coalesce(care.name, care_roster.participant_name, ''),
        'careBuddyDisplayName', coalesce(care.display_name, care_roster_profile.display_name, ''),
        'careBuddyMatchStatus', coalesce(care_roster.match_status, ''),
        'secretBuddyRosterId', r.secret_buddy_roster_id,
        'secretBuddyId', coalesce(ba.secret_buddy_id, secret_roster.matched_profile_id),
        'secretBuddyLoginId', coalesce(secret.login_id, secret_roster_profile.login_id),
        'secretBuddyName', coalesce(secret.name, secret_roster.participant_name, ''),
        'secretBuddyDisplayName', coalesce(secret.display_name, secret_roster_profile.display_name, ''),
        'secretBuddyMatchStatus', coalesce(secret_roster.match_status, ''),
        'updatedAt', ba.updated_at,
        'sortGroup', coalesce(r.group_no, 998),
        'sortRole', case r.group_role when 'leader' then 0 when 'assistant' then 1 else 2 end,
        'sortOrder', r.roster_order
      ) as row_json,
      coalesce(r.group_no, 998) as sort_group,
      case r.group_role when 'leader' then 0 when 'assistant' then 1 else 2 end as sort_role,
      r.roster_order as sort_order
    from public.retreat_group_roster r
    left join public.groups g on g.id = r.group_id
    left join public.profiles u on u.id = r.matched_profile_id
    left join public.retreat_attendance ra on ra.profile_id = u.id
    left join public.bbb_assignments ba on ba.profile_id = u.id
    left join public.profiles care on care.id = ba.care_buddy_id
    left join public.profiles secret on secret.id = ba.secret_buddy_id
    left join public.retreat_group_roster care_roster on care_roster.id = r.care_buddy_roster_id
    left join public.profiles care_roster_profile on care_roster_profile.id = care_roster.matched_profile_id
    left join public.retreat_group_roster secret_roster on secret_roster.id = r.secret_buddy_roster_id
    left join public.profiles secret_roster_profile on secret_roster_profile.id = secret_roster.matched_profile_id
    where r.source_batch = v_batch
  ),
  roster_names as (
    select distinct name_norm
    from public.retreat_group_roster
    where source_batch = v_batch
  ),
  matched_profiles as (
    select matched_profile_id as profile_id
    from public.retreat_group_roster
    where source_batch = v_batch
      and matched_profile_id is not null
  ),
  non_attendee_rows as (
    select
      jsonb_build_object(
        'rowType', 'non_attendee',
        'profileId', u.id,
        'canMatch', false,
        'loginId', u.login_id,
        'userId', u.login_id,
        'name', coalesce(u.name, ''),
        'displayName', coalesce(u.display_name, ''),
        'participantCode', coalesce(u.participant_code, ''),
        'parish', coalesce(u.parish, ''),
        'rosterParish', '',
        'parishNorm', public.bu_group_roster_normalize_parish(u.parish),
        'groupId', null,
        'groupNo', null,
        'groupLabel', '미참',
        'groupName', '미참',
        'groupTier', '',
        'groupRole', '',
        'rawRole', '',
        'participationTier', '미참',
        'matchingTier', '미참',
        'participationSchedule', '',
        'attendanceStatus', '',
        'matchStatus', 'non_attendee',
        'matchDetail', '앱 가입은 했지만 조 편성 명단에는 없음',
        'candidateProfiles', '[]'::jsonb,
        'careBuddyId', null,
        'careBuddyLoginId', null,
        'careBuddyName', '',
        'careBuddyDisplayName', '',
        'secretBuddyId', null,
        'secretBuddyLoginId', null,
        'secretBuddyName', '',
        'secretBuddyDisplayName', '',
        'updatedAt', null,
        'sortGroup', 999,
        'sortRole', 2,
        'sortOrder', 10000
      ) as row_json,
      999 as sort_group,
      2 as sort_role,
      row_number() over (order by public.bu_group_roster_normalize_parish(u.parish), u.name, u.login_id::text) + 10000 as sort_order
    from public.profiles u
    where u.account_status = 'active'
      and u.is_dev = false
      and u.is_test = false
      and not exists (select 1 from matched_profiles mp where mp.profile_id = u.id)
      and not exists (
        select 1
        from roster_names rn
        where rn.name_norm = public.bu_group_roster_normalize_name(u.name)
      )
  ),
  all_rows as (
    select * from roster_rows
    union all
    select * from non_attendee_rows
  )
  select coalesce(jsonb_agg(row_json order by sort_group, sort_role, sort_order), '[]'::jsonb)
  into v_rows
  from all_rows;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'sourceBatch', v_batch,
    'rows', v_rows
  );
end;
$$;

revoke all on function public.admin_get_bbb_matching_matrix() from public, anon, authenticated;
grant execute on function public.admin_get_bbb_matching_matrix() to authenticated;

create or replace function public.admin_set_bbb_care_buddy(
  p_profile_id uuid,
  p_care_buddy_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_care_profile public.profiles%rowtype;
  v_old_care_buddy_id uuid;
  v_profile_group_id uuid;
  v_profile_tier text;
  v_care_group_id uuid;
  v_care_tier text;
  v_batch text := {sql_string(BATCH_KEY)};
begin
  v_admin := public.bu_admin_profile();

  select *
  into v_profile
  from public.profiles
  where id = p_profile_id
    and account_status = 'active';

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'profile_not_found');
  end if;

  select r.group_id, r.participation_tier
  into v_profile_group_id, v_profile_tier
  from public.retreat_group_roster r
  where r.source_batch = v_batch
    and r.matched_profile_id = p_profile_id
    and r.group_id is not null
  order by r.roster_order
  limit 1;

  if v_profile_group_id is null then
    select gm.group_id, public.bu_bbb_matching_tier(ra.participation_tier, ra.attendance_status)
    into v_profile_group_id, v_profile_tier
    from public.profiles p
    left join public.group_members gm on gm.profile_id = p.id
    left join public.retreat_attendance ra on ra.profile_id = p.id
    where p.id = p_profile_id;
  end if;

  if p_care_buddy_id is not null then
    select *
    into v_care_profile
    from public.profiles
    where id = p_care_buddy_id
      and account_status = 'active';

    if v_care_profile.id is null then
      return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'care_buddy_not_found');
    end if;

    if p_profile_id = p_care_buddy_id then
      return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'self_matching_not_allowed');
    end if;

    select r.group_id, r.participation_tier
    into v_care_group_id, v_care_tier
    from public.retreat_group_roster r
    where r.source_batch = v_batch
      and r.matched_profile_id = p_care_buddy_id
      and r.group_id is not null
    order by r.roster_order
    limit 1;

    if v_care_group_id is null then
      select gm.group_id, public.bu_bbb_matching_tier(ra.participation_tier, ra.attendance_status)
      into v_care_group_id, v_care_tier
      from public.profiles p
      left join public.group_members gm on gm.profile_id = p.id
      left join public.retreat_attendance ra on ra.profile_id = p.id
      where p.id = p_care_buddy_id;
    end if;

    if v_profile_group_id is distinct from v_care_group_id then
      return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'different_group_not_allowed');
    end if;

    if coalesce(v_profile_tier, '전참') is distinct from coalesce(v_care_tier, '전참') then
      return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'different_tier_not_allowed');
    end if;
  end if;

  select care_buddy_id
  into v_old_care_buddy_id
  from public.bbb_assignments
  where profile_id = p_profile_id;

  if v_old_care_buddy_id is not null and v_old_care_buddy_id is distinct from p_care_buddy_id then
    update public.bbb_assignments
    set secret_buddy_id = null,
        updated_at = now()
    where profile_id = v_old_care_buddy_id
      and secret_buddy_id = p_profile_id;
  end if;

  if p_care_buddy_id is not null then
    update public.bbb_assignments
    set care_buddy_id = null,
        updated_at = now()
    where care_buddy_id = p_care_buddy_id
      and profile_id <> p_profile_id;
  end if;

  insert into public.bbb_assignments (
    profile_id,
    care_buddy_id,
    group_id,
    tier,
    updated_at
  )
  values (
    p_profile_id,
    p_care_buddy_id,
    v_profile_group_id,
    coalesce(v_profile_tier, '전참'),
    now()
  )
  on conflict (profile_id) do update
  set care_buddy_id = excluded.care_buddy_id,
      group_id = excluded.group_id,
      tier = excluded.tier,
      updated_at = now();

  if p_care_buddy_id is not null then
    insert into public.bbb_assignments (
      profile_id,
      secret_buddy_id,
      group_id,
      tier,
      updated_at
    )
    values (
      p_care_buddy_id,
      p_profile_id,
      v_care_group_id,
      coalesce(v_care_tier, '전참'),
      now()
    )
    on conflict (profile_id) do update
    set secret_buddy_id = excluded.secret_buddy_id,
        group_id = excluded.group_id,
        tier = excluded.tier,
        updated_at = now();
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'profileId', p_profile_id,
    'careBuddyId', p_care_buddy_id,
    'oldCareBuddyId', v_old_care_buddy_id,
    'matchingTier', coalesce(v_profile_tier, '전참')
  );
end;
$$;

revoke all on function public.admin_set_bbb_care_buddy(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_set_bbb_care_buddy(uuid, uuid) to authenticated;

create or replace function public.admin_set_bbb_care_buddy_roster(
  p_roster_id uuid,
  p_care_buddy_roster_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_roster public.retreat_group_roster%rowtype;
  v_care_roster public.retreat_group_roster%rowtype;
  v_old_care_roster_id uuid;
  v_old_care_profile_id uuid;
begin
  v_admin := public.bu_admin_profile();

  select *
  into v_roster
  from public.retreat_group_roster
  where id = p_roster_id;

  if v_roster.id is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'roster_not_found');
  end if;

  v_old_care_roster_id := v_roster.care_buddy_roster_id;

  if p_care_buddy_roster_id is not null then
    select *
    into v_care_roster
    from public.retreat_group_roster
    where id = p_care_buddy_roster_id
      and source_batch = v_roster.source_batch;

    if v_care_roster.id is null then
      return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'care_buddy_roster_not_found');
    end if;

    if p_roster_id = p_care_buddy_roster_id then
      return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'self_matching_not_allowed');
    end if;

    if v_roster.group_id is distinct from v_care_roster.group_id then
      return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'different_group_not_allowed');
    end if;

    if coalesce(v_roster.participation_tier, '전참') is distinct from coalesce(v_care_roster.participation_tier, '전참') then
      return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'different_tier_not_allowed');
    end if;
  end if;

  if v_old_care_roster_id is not null and v_old_care_roster_id is distinct from p_care_buddy_roster_id then
    select matched_profile_id
    into v_old_care_profile_id
    from public.retreat_group_roster
    where id = v_old_care_roster_id;

    update public.retreat_group_roster
    set secret_buddy_roster_id = null,
        updated_at = now()
    where id = v_old_care_roster_id
      and secret_buddy_roster_id = p_roster_id;

    if v_roster.matched_profile_id is not null and v_old_care_profile_id is not null then
      update public.bbb_assignments
      set secret_buddy_id = null,
          updated_at = now()
      where profile_id = v_old_care_profile_id
        and secret_buddy_id = v_roster.matched_profile_id;
    end if;
  end if;

  if p_care_buddy_roster_id is not null then
    with cleared as (
      update public.retreat_group_roster
      set care_buddy_roster_id = null,
          updated_at = now()
      where source_batch = v_roster.source_batch
        and care_buddy_roster_id = p_care_buddy_roster_id
        and id <> p_roster_id
      returning matched_profile_id
    )
    update public.bbb_assignments ba
    set care_buddy_id = null,
        updated_at = now()
    from cleared
    where cleared.matched_profile_id is not null
      and ba.profile_id = cleared.matched_profile_id;

    update public.retreat_group_roster
    set secret_buddy_roster_id = p_roster_id,
        updated_at = now()
    where id = p_care_buddy_roster_id;
  end if;

  update public.retreat_group_roster
  set care_buddy_roster_id = p_care_buddy_roster_id,
      updated_at = now()
  where id = p_roster_id;

  if v_roster.matched_profile_id is not null then
    update public.bbb_assignments
    set care_buddy_id = null,
        updated_at = now()
    where profile_id = v_roster.matched_profile_id;
  end if;

  perform public.bu_sync_group_roster_profile_matches(v_roster.source_batch);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'rosterId', p_roster_id,
    'careBuddyRosterId', p_care_buddy_roster_id
  );
end;
$$;

revoke all on function public.admin_set_bbb_care_buddy_roster(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_set_bbb_care_buddy_roster(uuid, uuid) to authenticated;

create or replace function public.admin_auto_assign_bbb_buddies(
  p_group_no integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_batch text := {sql_string(BATCH_KEY)};
  v_assigned_rows integer := 0;
  v_secret_rows integer := 0;
  v_group_members integer := 0;
  v_assignments integer := 0;
  v_bucket_count integer := 0;
  v_skipped_singletons integer := 0;
begin
  v_admin := public.bu_admin_profile();

  with buckets as (
    select
      group_id,
      coalesce(participation_tier, '전참') as participation_tier,
      count(*)::integer as member_count
    from public.retreat_group_roster
    where source_batch = v_batch
      and group_id is not null
      and (p_group_no is null or group_no = p_group_no)
    group by group_id, coalesce(participation_tier, '전참')
  )
  select
    count(*)::integer,
    count(*) filter (where member_count = 1)::integer
  into v_bucket_count, v_skipped_singletons
  from buckets;

  with scope as (
    select id, matched_profile_id
    from public.retreat_group_roster
    where source_batch = v_batch
      and group_id is not null
      and (p_group_no is null or group_no = p_group_no)
  ),
  cleared as (
    update public.retreat_group_roster r
    set care_buddy_roster_id = null,
        secret_buddy_roster_id = null,
        updated_at = now()
    from scope s
    where r.id = s.id
    returning s.matched_profile_id
  )
  update public.bbb_assignments ba
  set care_buddy_id = null,
      secret_buddy_id = null,
      updated_at = now()
  from cleared
  where cleared.matched_profile_id is not null
    and ba.profile_id = cleared.matched_profile_id;

  with ordered as (
    select
      r.id,
      r.group_id,
      coalesce(r.participation_tier, '전참') as participation_tier,
      row_number() over (
        partition by r.group_id, coalesce(r.participation_tier, '전참')
        order by
          case r.group_role when 'leader' then 0 when 'assistant' then 1 else 2 end,
          r.roster_order,
          r.participant_name
      )::integer as rn,
      count(*) over (
        partition by r.group_id, coalesce(r.participation_tier, '전참')
      )::integer as cnt
    from public.retreat_group_roster r
    where r.source_batch = v_batch
      and r.group_id is not null
      and (p_group_no is null or r.group_no = p_group_no)
  ),
  paired as (
    select
      owner.id,
      buddy.id as care_buddy_roster_id
    from ordered owner
    join ordered buddy
      on buddy.group_id = owner.group_id
     and buddy.participation_tier = owner.participation_tier
     and buddy.rn = case when owner.rn = owner.cnt then 1 else owner.rn + 1 end
    where owner.cnt > 1
  ),
  updated as (
    update public.retreat_group_roster r
    set care_buddy_roster_id = paired.care_buddy_roster_id,
        updated_at = now()
    from paired
    where r.id = paired.id
    returning r.id
  )
  select count(*)::integer into v_assigned_rows from updated;

  with owners as (
    select id, care_buddy_roster_id
    from public.retreat_group_roster
    where source_batch = v_batch
      and group_id is not null
      and care_buddy_roster_id is not null
      and (p_group_no is null or group_no = p_group_no)
  ),
  updated as (
    update public.retreat_group_roster target
    set secret_buddy_roster_id = owners.id,
        updated_at = now()
    from owners
    where target.id = owners.care_buddy_roster_id
    returning target.id
  )
  select count(*)::integer into v_secret_rows from updated;

  select (result->>'groupMembersTouched')::integer,
         (result->>'assignmentsTouched')::integer
  into v_group_members,
       v_assignments
  from (
    select public.bu_sync_group_roster_profile_matches(v_batch) as result
  ) synced;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'sourceBatch', v_batch,
    'groupNo', p_group_no,
    'bucketCount', coalesce(v_bucket_count, 0),
    'skippedSingletonBuckets', coalesce(v_skipped_singletons, 0),
    'assignedRows', coalesce(v_assigned_rows, 0),
    'secretRows', coalesce(v_secret_rows, 0),
    'groupMembersTouched', coalesce(v_group_members, 0),
    'assignmentsTouched', coalesce(v_assignments, 0)
  );
end;
$$;

revoke all on function public.admin_auto_assign_bbb_buddies(integer) from public, anon, authenticated;
grant execute on function public.admin_auto_assign_bbb_buddies(integer) to authenticated;

create or replace function public.admin_resolve_group_roster_profile(
  p_roster_id uuid,
  p_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_roster public.retreat_group_roster%rowtype;
  v_profile public.profiles%rowtype;
  v_existing_roster_id uuid;
begin
  v_admin := public.bu_admin_profile();

  select *
  into v_roster
  from public.retreat_group_roster
  where id = p_roster_id;

  if v_roster.id is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'roster_not_found');
  end if;

  select *
  into v_profile
  from public.profiles
  where id = p_profile_id
    and account_status = 'active'
    and is_dev = false
    and is_test = false;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'profile_not_found');
  end if;

  if public.bu_group_roster_normalize_name(v_profile.name) is distinct from v_roster.name_norm then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'name_mismatch');
  end if;

  select r.id
  into v_existing_roster_id
  from public.retreat_group_roster r
  where r.source_batch = v_roster.source_batch
    and r.matched_profile_id = p_profile_id
    and r.id <> p_roster_id
  order by r.roster_order
  limit 1;

  if v_existing_roster_id is not null then
    return jsonb_build_object(
      'ok', false,
      'source', 'supabase',
      'error', 'profile_already_matched',
      'existingRosterId', v_existing_roster_id
    );
  end if;

  update public.retreat_group_roster
  set matched_profile_id = p_profile_id,
      match_status = 'matched_manual',
      match_detail = '관리자 수동 매칭',
      updated_at = now()
  where id = p_roster_id;

  if v_roster.group_id is not null then
    insert into public.group_members (
      group_id,
      profile_id,
      group_role,
      assigned_at
    )
    values (
      v_roster.group_id,
      p_profile_id,
      v_roster.group_role,
      now()
    )
    on conflict (profile_id) do update
    set group_id = excluded.group_id,
        group_role = excluded.group_role,
        assigned_at = now();
  end if;

  perform public.bu_sync_group_roster_profile_matches(v_roster.source_batch);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'rosterId', p_roster_id,
    'profileId', p_profile_id,
    'matchStatus', 'matched_manual'
  );
end;
$$;

revoke all on function public.admin_resolve_group_roster_profile(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_resolve_group_roster_profile(uuid, uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
"""

    OUTPUT_SQL.write_text(sql, encoding="utf-8")
    print(f"wrote {OUTPUT_SQL} rows={len(roster_values)}")


if __name__ == "__main__":
    main()
