-- BBB ? ??, ?? ????, ?? fallback, ?? ????? ? ?? ???? ?? ?? ??.
-- Supabase SQL Editor?? ? ?? ??? ?? ??? ????.
-- ?? ??: 006 -> 007 -> 008 -> 009.


-- ============================================================
-- 006 singleton TF fallback
-- source: beyond_us/supabase/migrations/20260620000600_bbb_singleton_tf_fallback.sql
-- ============================================================
-- BBB 단독 부분참여자에게 전참 케어버디와 TF 시크릿버디를 배정한다.
begin;

create table if not exists public.bbb_extra_care_roster_links (
  id uuid primary key default gen_random_uuid(),
  source_batch text not null,
  care_giver_roster_id uuid not null references public.retreat_group_roster(id) on delete cascade,
  care_receiver_roster_id uuid not null references public.retreat_group_roster(id) on delete cascade,
  reason text not null default 'singleton_partial_tf',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_batch, care_giver_roster_id, care_receiver_roster_id),
  check (care_giver_roster_id is distinct from care_receiver_roster_id)
);

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'set_bbb_extra_care_roster_links_updated_at'
      and tgrelid = 'public.bbb_extra_care_roster_links'::regclass
  ) then
    create trigger set_bbb_extra_care_roster_links_updated_at
    before update on public.bbb_extra_care_roster_links
    for each row execute function public.set_updated_at();
  end if;
end;
$$;

alter table public.bbb_extra_care_roster_links enable row level security;
revoke all on public.bbb_extra_care_roster_links from public, anon, authenticated;

comment on table public.bbb_extra_care_roster_links is '토참/일참 단독 참여자를 TF가 추가로 케어해야 할 때 사용하는 다중 케어버디 링크.';

create or replace function public.bu_sync_bbb_assignments_from_roster(
  p_source_batch text default '20260614'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignments integer := 0;
begin
  insert into public.bbb_assignments (
    profile_id,
    care_buddy_id,
    secret_buddy_id,
    group_id,
    tier,
    updated_at
  )
  select distinct on (r.matched_profile_id)
    r.matched_profile_id,
    care.matched_profile_id,
    secret.matched_profile_id,
    r.group_id,
    coalesce(r.participation_tier, '전참'),
    now()
  from public.retreat_group_roster r
  left join public.retreat_group_roster care
    on care.id = r.care_buddy_roster_id
  left join public.retreat_group_roster secret
    on secret.id = r.secret_buddy_roster_id
  where r.source_batch = p_source_batch
    and r.matched_profile_id is not null
  order by
    r.matched_profile_id,
    case r.group_role
      when 'leader' then 0
      when 'assistant' then 1
      else 2
    end,
    r.group_no nulls last,
    r.roster_order nulls last,
    r.id
  on conflict (profile_id) do update
  set care_buddy_id = excluded.care_buddy_id,
      secret_buddy_id = excluded.secret_buddy_id,
      group_id = excluded.group_id,
      tier = excluded.tier,
      updated_at = now();

  get diagnostics v_assignments = row_count;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'sourceBatch', p_source_batch,
    'assignmentsTouched', coalesce(v_assignments, 0)
  );
end;
$$;

create or replace function public.bu_sync_group_roster_profile_matches(
  p_source_batch text default '20260614'
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
  v_assignment_result jsonb := '{}'::jsonb;
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
          'participantCode', p.participant_code,
          'isDev', coalesce(p.is_dev, false),
          'isTest', coalesce(p.is_test, false)
        )
        order by p.parish, p.name, p.login_id::text
      ) filter (where p.id is not null), '[]'::jsonb) as candidates
    from public.retreat_group_roster r
    join roster_duplicates rd on rd.roster_id = r.id
    left join public.profiles p
      on public.bu_group_roster_normalize_name(p.name) = r.name_norm
     and p.account_status = 'active'
    where r.source_batch = p_source_batch
    group by r.id, r.name_norm, r.parish_norm
  ),
  updated as (
    update public.retreat_group_roster r
    set candidate_profiles = c.candidates,
        matched_profile_id = case
          when r.match_status = 'matched_manual' then r.matched_profile_id
          when r.match_status = 'manual_unmatched' then null
          when c.roster_same_parish_count > 1 then null
          when c.candidate_count = 1 and c.roster_name_count = 1 then c.single_candidate_id
          when c.same_parish_count = 1 then c.same_parish_candidate_id
          else null
        end,
        match_status = case
          when r.match_status = 'matched_manual' then r.match_status
          when r.match_status = 'manual_unmatched' then r.match_status
          when c.roster_same_parish_count > 1 then 'duplicate_roster_same_parish'
          when c.candidate_count = 0 then 'nickname_missing'
          when c.candidate_count = 1 and c.roster_name_count = 1 then 'matched'
          when c.same_parish_count = 1 then 'matched_by_parish'
          when c.same_parish_count > 1 then 'duplicate_same_parish'
          else 'duplicate_needs_check'
        end,
        match_detail = case
          when r.match_status = 'matched_manual' then r.match_detail
          when r.match_status = 'manual_unmatched' then r.match_detail
          when c.roster_same_parish_count > 1 then '이름 중복 확인필요 - 조 명단 같은 청 중복'
          when c.candidate_count = 0 then '닉네임 없음'
          when c.candidate_count = 1 and c.roster_name_count = 1 then '매칭'
          when c.same_parish_count = 1 then '교구 기준 매칭'
          when c.same_parish_count > 1 then '이름 중복 확인필요 - 같은 청 후보'
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
  select distinct on (r.matched_profile_id)
    r.group_id,
    r.matched_profile_id,
    r.group_role,
    now()
  from public.retreat_group_roster r
  where r.source_batch = p_source_batch
    and r.group_id is not null
    and r.matched_profile_id is not null
  order by
    r.matched_profile_id,
    case r.group_role
      when 'leader' then 0
      when 'assistant' then 1
      else 2
    end,
    r.group_no nulls last,
    r.roster_order nulls last,
    r.id
  on conflict (profile_id) do update
  set group_id = excluded.group_id,
      group_role = excluded.group_role,
      assigned_at = now();

  get diagnostics v_group_members = row_count;

  v_assignment_result := public.bu_sync_bbb_assignments_from_roster(p_source_batch);
  v_assignments := coalesce((v_assignment_result->>'assignmentsTouched')::integer, 0);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'sourceBatch', p_source_batch,
    'matchedRowsTouched', coalesce(v_matched, 0),
    'groupMembersTouched', coalesce(v_group_members, 0),
    'assignmentsTouched', coalesce(v_assignments, 0),
    'devProfilesAllowed', true,
    'directSecretRosterSync', true
  );
end;
$$;

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
  end if;

  if v_old_care_roster_id is not null and v_old_care_roster_id is distinct from p_care_buddy_roster_id then
    update public.retreat_group_roster
    set secret_buddy_roster_id = null,
        updated_at = now()
    where id = v_old_care_roster_id
      and secret_buddy_roster_id = p_roster_id;
  end if;

  if p_care_buddy_roster_id is not null then
    update public.retreat_group_roster
    set care_buddy_roster_id = null,
        updated_at = now()
    where source_batch = v_roster.source_batch
      and care_buddy_roster_id = p_care_buddy_roster_id
      and id <> p_roster_id;

    update public.retreat_group_roster
    set secret_buddy_roster_id = p_roster_id,
        updated_at = now()
    where id = p_care_buddy_roster_id;
  end if;

  update public.retreat_group_roster
  set care_buddy_roster_id = p_care_buddy_roster_id,
      updated_at = now()
  where id = p_roster_id;

  perform public.bu_sync_group_roster_profile_matches(v_roster.source_batch);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'rosterId', p_roster_id,
    'careBuddyRosterId', p_care_buddy_roster_id,
    'crossGroupAllowed', true
  );
end;
$$;

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
  v_batch text := '20260614';
  v_assigned_rows integer := 0;
  v_secret_rows integer := 0;
  v_singleton_rows integer := 0;
  v_tf_extra_rows integer := 0;
  v_group_members integer := 0;
  v_assignments integer := 0;
  v_bucket_count integer := 0;
  v_unresolved_singletons integer := 0;
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
  select count(*)::integer
  into v_bucket_count
  from buckets;

  with scope as (
    select id, matched_profile_id
    from public.retreat_group_roster
    where source_batch = v_batch
      and group_id is not null
      and (p_group_no is null or group_no = p_group_no)
  ),
  cleared_roster as (
    update public.retreat_group_roster r
    set care_buddy_roster_id = null,
        secret_buddy_roster_id = null,
        updated_at = now()
    from scope s
    where r.id = s.id
    returning r.id, s.matched_profile_id
  ),
  cleared_extra as (
    delete from public.bbb_extra_care_roster_links l
    using scope s
    where l.source_batch = v_batch
      and (
        l.care_giver_roster_id = s.id
        or l.care_receiver_roster_id = s.id
      )
    returning l.id
  )
  update public.bbb_assignments ba
  set care_buddy_id = null,
      secret_buddy_id = null,
      updated_at = now()
  from cleared_roster cr
  where cr.matched_profile_id is not null
    and ba.profile_id = cr.matched_profile_id;

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
  updated_care as (
    update public.retreat_group_roster r
    set care_buddy_roster_id = paired.care_buddy_roster_id,
        updated_at = now()
    from paired
    where r.id = paired.id
    returning r.id
  ),
  owners as (
    select id, care_buddy_roster_id
    from public.retreat_group_roster
    where source_batch = v_batch
      and group_id is not null
      and care_buddy_roster_id is not null
      and (p_group_no is null or group_no = p_group_no)
  ),
  updated_secret as (
    update public.retreat_group_roster target
    set secret_buddy_roster_id = owners.id,
        updated_at = now()
    from owners
    where target.id = owners.care_buddy_roster_id
    returning target.id
  )
  select
    (select count(*) from updated_care)::integer,
    (select count(*) from updated_secret)::integer
  into v_assigned_rows, v_secret_rows;

  with ordered as (
    select
      r.*,
      count(*) over (
        partition by r.group_id, coalesce(r.participation_tier, '전참')
      )::integer as tier_member_count
    from public.retreat_group_roster r
    where r.source_batch = v_batch
      and r.group_id is not null
      and (p_group_no is null or r.group_no = p_group_no)
  ),
  singleton as (
    select *
    from ordered
    where tier_member_count = 1
      and coalesce(participation_tier, '전참') in ('토참', '일참')
  ),
  resolved as (
    select
      s.id,
      full_candidate.id as full_care_roster_id,
      tf_candidate.id as tf_secret_roster_id
    from singleton s
    left join lateral (
      select c.id
      from public.retreat_group_roster c
      where c.source_batch = v_batch
        and c.group_id = s.group_id
        and c.id <> s.id
        and coalesce(c.participation_tier, '전참') = '전참'
      order by md5(s.id::text || ':full:' || c.id::text)
      limit 1
    ) full_candidate on true
    left join lateral (
      select tf.id
      from public.retreat_group_roster tf
      join public.profiles p on p.id = tf.matched_profile_id
      where tf.source_batch = v_batch
        and tf.id <> s.id
        and p.account_status = 'active'
        and (p.role in ('admin', 'dev') or p.is_dev = true)
      order by
        case when tf.group_id = s.group_id then 0 else 1 end,
        md5(s.id::text || ':tf:' || tf.id::text)
      limit 1
    ) tf_candidate on true
  ),
  updated_singletons as (
    update public.retreat_group_roster r
    set care_buddy_roster_id = resolved.full_care_roster_id,
        secret_buddy_roster_id = resolved.tf_secret_roster_id,
        updated_at = now()
    from resolved
    where r.id = resolved.id
      and resolved.full_care_roster_id is not null
      and resolved.tf_secret_roster_id is not null
    returning r.id, resolved.tf_secret_roster_id
  ),
  extra_links as (
    insert into public.bbb_extra_care_roster_links (
      source_batch,
      care_giver_roster_id,
      care_receiver_roster_id,
      reason
    )
    select
      v_batch,
      us.tf_secret_roster_id,
      us.id,
      'singleton_partial_tf'
    from updated_singletons us
    on conflict (source_batch, care_giver_roster_id, care_receiver_roster_id) do update
    set reason = excluded.reason,
        updated_at = now()
    returning id
  )
  select
    (select count(*) from updated_singletons)::integer,
    (select count(*) from extra_links)::integer,
    (select count(*) from resolved where full_care_roster_id is null or tf_secret_roster_id is null)::integer
  into v_singleton_rows, v_tf_extra_rows, v_unresolved_singletons;

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
    'unresolvedSingletonBuckets', coalesce(v_unresolved_singletons, 0),
    'assignedRows', coalesce(v_assigned_rows, 0) + coalesce(v_singleton_rows, 0),
    'standardAssignedRows', coalesce(v_assigned_rows, 0),
    'singletonFallbackRows', coalesce(v_singleton_rows, 0),
    'tfExtraCareRows', coalesce(v_tf_extra_rows, 0),
    'secretRows', coalesce(v_secret_rows, 0) + coalesce(v_singleton_rows, 0),
    'groupMembersTouched', coalesce(v_group_members, 0),
    'assignmentsTouched', coalesce(v_assignments, 0)
  );
end;
$$;

create or replace function public.get_bbb_status(p_login_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_assignment public.bbb_assignments%rowtype;
  v_care public.profiles%rowtype;
  v_secret public.profiles%rowtype;
  v_roster_id uuid;
  v_care_roster_id uuid;
  v_secret_roster_id uuid;
  v_care_roster_name text := '';
  v_secret_roster_name text := '';
  v_care_profile_id uuid;
  v_secret_profile_id uuid;
  v_care_name text := '';
  v_secret_name text := '';
  v_extra_care_buddies jsonb := '[]'::jsonb;
  v_photos jsonb := '{}'::jsonb;
  v_caught boolean := false;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  v_photos := public.bu_photo_payload(v_profile.id);

  select *
  into v_assignment
  from public.bbb_assignments
  where profile_id = v_profile.id;

  select
    r.id,
    care.id,
    secret.id,
    coalesce(care.participant_name, ''),
    coalesce(secret.participant_name, ''),
    care.matched_profile_id,
    secret.matched_profile_id
  into
    v_roster_id,
    v_care_roster_id,
    v_secret_roster_id,
    v_care_roster_name,
    v_secret_roster_name,
    v_care_profile_id,
    v_secret_profile_id
  from public.retreat_group_roster r
  left join public.retreat_group_roster care on care.id = r.care_buddy_roster_id
  left join public.retreat_group_roster secret on secret.id = r.secret_buddy_roster_id
  where r.source_batch = '20260614'
    and r.matched_profile_id = v_profile.id
  order by r.roster_order
  limit 1;

  v_care_profile_id := coalesce(v_assignment.care_buddy_id, v_care_profile_id);
  v_secret_profile_id := coalesce(v_assignment.secret_buddy_id, v_secret_profile_id);

  if v_assignment.profile_id is null and v_roster_id is null then
    return jsonb_build_object(
      'ok', false,
      'source', 'supabase',
      'error', 'no_match'
    ) || v_photos;
  end if;

  if v_care_profile_id is not null then
    select *
    into v_care
    from public.profiles
    where id = v_care_profile_id;
  end if;

  if v_secret_profile_id is not null then
    select *
    into v_secret
    from public.profiles
    where id = v_secret_profile_id;
  end if;

  if v_roster_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'name', coalesce(nullif(btrim(receiver.participant_name), ''), nullif(btrim(rp.name), ''), nullif(btrim(rp.display_name), ''), nullif(btrim(rp.login_id::text), ''), '이름 확인 중'),
      'participantName', nullif(btrim(receiver.participant_name), ''),
      'nickname', coalesce(rp.login_id::text, ''),
      'groupNo', receiver.group_no,
      'tier', coalesce(receiver.participation_tier, '')
    ) order by receiver.group_no, receiver.roster_order), '[]'::jsonb)
    into v_extra_care_buddies
    from public.bbb_extra_care_roster_links link
    join public.retreat_group_roster receiver on receiver.id = link.care_receiver_roster_id
    left join public.profiles rp on rp.id = receiver.matched_profile_id
    where link.source_batch = '20260614'
      and link.care_giver_roster_id = v_roster_id;
  end if;

  v_care_name := coalesce(
    nullif(btrim(v_care.name), ''),
    nullif(btrim(v_care_roster_name), ''),
    nullif(btrim(v_care.display_name), ''),
    nullif(btrim(v_care.login_id::text), ''),
    '이름 확인 중'
  );

  v_secret_name := coalesce(
    nullif(btrim(v_secret.name), ''),
    nullif(btrim(v_secret_roster_name), ''),
    nullif(btrim(v_secret.display_name), ''),
    nullif(btrim(v_secret.login_id::text), ''),
    ''
  );

  select exists(
    select 1
    from public.bbb_assignments other_assignment
    where other_assignment.care_buddy_id = v_profile.id
      and other_assignment.secret_revealed = true
  )
  into v_caught;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'careBuddy', jsonb_build_object(
      'name', v_care_name,
      'participantName', nullif(v_care_roster_name, ''),
      'nickname', coalesce(v_care.login_id::text, '')
    ),
    'extraCareBuddies', coalesce(v_extra_care_buddies, '[]'::jsonb),
    'secretBuddy', case
      when v_secret_profile_id is null and v_secret_roster_id is null then null
      when coalesce(v_assignment.secret_revealed, false) then jsonb_build_object(
        'revealed', true,
        'name', v_secret_name,
        'participantName', nullif(v_secret_roster_name, ''),
        'nickname', coalesce(v_secret.login_id::text, '')
      )
      else jsonb_build_object(
        'revealed', false,
        'hint', '아직 비밀이에요'
      )
    end,
    'caughtByBuddy', v_caught
  ) || v_photos;
end;
$$;

revoke all on function public.bu_sync_bbb_assignments_from_roster(text) from public, anon, authenticated;
revoke all on function public.bu_sync_group_roster_profile_matches(text) from public, anon, authenticated;
revoke all on function public.admin_set_bbb_care_buddy_roster(uuid, uuid) from public, anon, authenticated;
revoke all on function public.admin_auto_assign_bbb_buddies(integer) from public, anon, authenticated;
revoke all on function public.get_bbb_status(text) from public, anon, authenticated;

grant execute on function public.bu_sync_group_roster_profile_matches(text) to authenticated;
grant execute on function public.admin_set_bbb_care_buddy_roster(uuid, uuid) to authenticated;
grant execute on function public.admin_auto_assign_bbb_buddies(integer) to authenticated;
grant execute on function public.get_bbb_status(text) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;


-- ============================================================
-- 007 latest roster patch
-- source: beyond_us/supabase/migrations/20260620000700_bbb_roster_latest_xlsx_patch.sql
-- ============================================================
-- 최신 조별 엑셀 기준으로 BBB roster를 보정하고 기존 매칭을 최대한 보존한다.
begin;

create table if not exists public.retreat_group_roster_removed (
  id uuid primary key,
  source_batch text not null,
  participant_name text not null,
  birth_year text,
  removed_reason text not null,
  replacement_roster_id uuid,
  roster_snapshot jsonb not null,
  removed_at timestamptz not null default now()
);

create temp table latest_bbb_roster_patch (
  desired_order integer not null,
  group_no integer not null,
  group_label text not null,
  group_role text not null,
  raw_role text,
  participant_name text not null,
  birth_year text,
  parish_raw text,
  participation_schedule text,
  note text,
  source_sheet text not null,
  source_row integer not null,
  name_norm text generated always as (public.bu_group_roster_normalize_name(participant_name)) stored,
  parish_norm text generated always as (public.bu_group_roster_normalize_parish(parish_raw)) stored,
  participation_tier text generated always as (public.bu_group_roster_tier(participation_schedule)) stored,
  stable_key text generated always as (public.bu_group_roster_normalize_name(participant_name) || '|' || coalesce(birth_year, '')) stored
) on commit drop;

insert into latest_bbb_roster_patch (
  desired_order,
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
  (1, 1, '1조', 'leader', '조장', '장한나', '2000', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 8),
  (2, 1, '1조', 'member', '1', '김희창', '1986', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 9),
  (3, 1, '1조', 'member', '2', '최시온', '2000', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 10),
  (4, 1, '1조', 'member', '3', '조진형', '2006', '1교구 (유광훈 전도사)', '전체참석 / 토 ~ 월요일 오전', '', '1~8조', 11),
  (5, 1, '1조', 'member', '4', '전승민', '2004', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 12),
  (6, 1, '1조', 'member', '5', '유하영', '2002', '2교구 (임동표 목사)', '전체참석 / 토 오후 ~ 월요일 오전', '', '1~8조', 13),
  (7, 1, '1조', 'member', '6', '곽지섭', '1996', '3교구 (현성수 목사)', '전체참석 / 토 오후 ~ 월요일 오전', '', '1~8조', 14),
  (8, 1, '1조', 'member', '7', '이민지', '2000', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '햇빛알러지로 인해 야외 활동이 불가능', '1~8조', 15),
  (9, 1, '1조', 'member', '8', '유지인', '2007', '1교구 (유광훈 전도사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 16),
  (10, 1, '1조', 'member', '9', '김형태', '1997', '잘 모르겠다', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 17),
  (11, 1, '1조', 'member', '10', '정에스더', '1988', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 18),
  (12, 1, '1조', 'member', '11', '박주명', '1997', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 19),
  (13, 1, '1조', 'member', '12', '유강현', '1996', '3교구 (현성수 목사)', '부분참석 / 토요일 오후(12시) ~ 토요일 오후(23시)', '', '1~8조', 20),
  (14, 1, '1조', 'member', '13', '오성경', '1997', '3교구 (현성수 목사)', '부분참석 / 토요일 오후(12시) ~ 토요일 오후(23시)', '', '1~8조', 21),
  (15, 1, '1조', 'member', '14', '허완', '1991', '4교구 (남우진 목사)', '부분참석 / 주일 오전(7시) ~ 월요일 오전(10시)', '', '1~8조', 22),
  (16, 1, '1조', 'member', '15', '정준무', '1994', '4교구 (남우진 목사)', '부분참석 / 주일 오전(7시) ~ 월요일 새벽', '추가인원', '1~8조', 23),
  (17, 2, '2조', 'leader', '조장', '김희근', '2002', '2교구 (임동표 목사)', '4', '', '1~8조', 32),
  (18, 2, '2조', 'member', '1', '김빛나래', '1984', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 33),
  (19, 2, '2조', 'member', '2', '김윤지', '2004', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 34),
  (20, 2, '2조', 'member', '3', '김경채', '2006', '잘 모르겠다', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 35),
  (21, 2, '2조', 'member', '3', '이다윗', '2001', '잘 모르겠다', '전체참석 /  토 ~ 월요일 오전', '참석취소인원', '1~8조', 36),
  (22, 2, '2조', 'member', '5', '안성재', '1994', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 37),
  (23, 2, '2조', 'member', '6', '김주리', '1992', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 38),
  (24, 2, '2조', 'member', '7', '장현준', '2007', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '해산물 알러지', '1~8조', 39),
  (25, 2, '2조', 'member', '8', '정대현', '2002', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '유당불내증', '1~8조', 40),
  (26, 2, '2조', 'member', '9', '이희찬', '1997', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 41),
  (27, 2, '2조', 'member', '10', '정보빈', '1989', '4교구(남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 42),
  (28, 2, '2조', 'member', '11', '김규리', '2002', '1교구 (유광훈 전도사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '추가인원', '1~8조', 43),
  (29, 2, '2조', 'member', '12', '전준재', '1997', '3교구 (현성수 목사)', '부분참석 / 토요일 오전 ~ 주일 오전(11시)', '', '1~8조', 44),
  (30, 2, '2조', 'member', '13', '황은택', '1999', '2교구 (임동표 목사)', '부분참석 / 토요일 오후(18시) ~ 주일 오후(16시)', '', '1~8조', 45),
  (31, 2, '2조', 'member', '14', '박민혁', '1996', '3교구 (현성수 목사)', '부분참석 / 주일 오전(7시) ~ 월요일 오전(10시)', '', '1~8조', 46),
  (32, 3, '3조', 'leader', '조장', '손민경', '1986', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 오후(19시)', '', '1~8조', 54),
  (33, 3, '3조', 'member', '1', '백온유', '1998', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 55),
  (34, 3, '3조', 'member', '2', '김응현', '2000', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 56),
  (35, 3, '3조', 'member', '3', '김예담', '2002', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 57),
  (36, 3, '3조', 'member', '4', '최지호', '1987', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 58),
  (37, 3, '3조', 'member', '5', '천은경', '1996', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 59),
  (38, 3, '3조', 'member', '6', '이경은', '2004', '잘 모르겠다', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 60),
  (39, 3, '3조', 'member', '7', '박은별', '1994', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '어깨 부상으로 치료중. 체육대회 참여불가', '1~8조', 61),
  (40, 3, '3조', 'member', '8', '조학준', '1999', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 62),
  (41, 3, '3조', 'member', '9', '양다니엘', '1996', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 63),
  (42, 3, '3조', 'member', '10', '김혜원', '1995', '3교구 (현성수 목사)', '전체참석 /  토 오후 ~ 주일 밤 (월요일 새벽)', '오이알러지', '1~8조', 64),
  (43, 3, '3조', 'member', '11', '오윤택', '1998', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 65),
  (44, 3, '3조', 'member', '12', '김동욱', '1980', '4교구 (남우진 목사)', '부분참석 / 토요일 오전~주일 오전(11시)', '양압기 착용중. 전기콘센트 근처 취침 희망', '1~8조', 66),
  (45, 3, '3조', 'member', '13', '김지민', '2004', '잘 모르겠다', '부분참석 / 주일 오전(7시) ~ 월요일 새벽', '', '1~8조', 67),
  (46, 3, '3조', 'member', '14', '이은서', '1998', '3교구 (현성수 목사)', '부분참석 / 주일 오후 (16시) ~ 주일 오후 (23시)', '', '1~8조', 68),
  (47, 4, '4조', 'leader', '조장', '지윤성', '1997', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 76),
  (48, 4, '4조', 'member', '1', '김정숙', '1988', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 77),
  (49, 4, '4조', 'member', '2', '양예지', '1995', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 78),
  (50, 4, '4조', 'member', '3', '정혜진', '1996', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 79),
  (51, 4, '4조', 'member', '4', '김예서', '2004', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 80),
  (52, 4, '4조', 'member', '5', '박교은', '2004', '1교구 (유광훈 전도사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 81),
  (53, 4, '4조', 'member', '6', '이건희', '2006', '1교구 (유광훈 전도사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '갑각류 알레르기', '1~8조', 82),
  (54, 4, '4조', 'member', '7', '조인택', '2006', '1교구 (유광훈 전도사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 83),
  (55, 4, '4조', 'member', '8', '전도현', '1994', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 84),
  (56, 4, '4조', 'member', '9', '이평화', '1997', '3교구 (현성수 목사)', '전체참석 / 토요일 오후 (20시) ~ 월요일 오전(9시)', '', '1~8조', 85),
  (57, 4, '4조', 'member', '10', '유하영', '1994', '3교구 (현성수 목사)', '전체참석 / 토요일 오후(19시) ~ 주일 오후 (23시)', '토마토, 씨있는 과일, 갑각류 알러지', '1~8조', 86),
  (58, 4, '4조', 'member', '11', '유하진', '1991', '4교구 (남우진 목사)', '전체참석 / 토요일 오후(19시) ~ 주일 오후 (23시)', '허리디스크', '1~8조', 87),
  (59, 4, '4조', 'member', '12', '이상윤', '1996', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '추가인원', '1~8조', 88),
  (60, 4, '4조', 'member', '13', '민혜진', '1997', '3교구 (현성수 목사)', '부분참석 / 토요일 오전~주일 오전(11시)', '', '1~8조', 89),
  (61, 4, '4조', 'member', '14', '천신원', '1996', '3교구 (현성수 목사)', '부분참석 / 토요일 오전~주일 오전(11시)', '', '1~8조', 90),
  (62, 5, '5조', 'leader', '조장', '손정범', '1998', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 8),
  (63, 5, '5조', 'member', '1', '전준우', '1995', '3교구 (현성수 목사)', '전체참석 /  토 오후 ~ 월요일 오전', '', '1~8조', 9),
  (64, 5, '5조', 'member', '2', '조현진', '2002', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 10),
  (65, 5, '5조', 'member', '3', '김태현', '2003', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 11),
  (66, 5, '5조', 'member', '4', '김이수', '2005', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 12),
  (67, 5, '5조', 'member', '5', '권혜민', '2005', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 13),
  (68, 5, '5조', 'member', '6', '조예서', '2006', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 14),
  (69, 5, '5조', 'member', '8', '윤지강', '2007', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 16),
  (70, 5, '5조', 'member', '9', '이재선', '1983', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 17),
  (71, 5, '5조', 'member', '10', '임하련', '1988', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 18),
  (72, 5, '5조', 'member', '11', '김성애', '1983', '잘 모르겠다', '부분참석 / 토요일 오전 ~ 주일 오전(11시)', '', '1~8조', 19),
  (73, 5, '5조', 'member', '12', '손승현', '2006', '1교구 (유광훈 전도사)', '부분참석 / 토요일 오전~주일 오전(11시)', '', '1~8조', 20),
  (74, 5, '5조', 'member', '14', '김주형', '2007', '1교구 (유광훈 전도사)', '부분참석 / 주일 ~ 월요일', '', '1~8조', 22),
  (75, 5, '5조', 'member', '15', '이강산', '1999', '1교구 (유광훈 전도사)', '부분참석 / 토요일 오전~토요일 밤', '추가인원', '1~8조', 23),
  (76, 5, '5조', 'member', '16', '박진용', '1995', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '추가인원', '1~8조', 24),
  (77, 6, '6조', 'leader', '조장', '서현덕', '1998', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 32),
  (78, 6, '6조', 'member', '1', '지윤호', '1998', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 33),
  (79, 6, '6조', 'member', '2', '김은수', '2002', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 34),
  (80, 6, '6조', 'member', '3', '김현진', '1997', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 35),
  (81, 6, '6조', 'member', '4', '윤영록', '1994', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 36),
  (82, 6, '6조', 'member', '5', '김영은', '2005', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 37),
  (83, 6, '6조', 'member', '6', '서유진', '2005', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 38),
  (84, 6, '6조', 'member', '7', '주세현', '2003', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 39),
  (85, 6, '6조', 'member', '8', '서찬영', '2003', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 40),
  (86, 6, '6조', 'member', '9', '임다혜', '1999', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 41),
  (87, 6, '6조', 'member', '10', '백지원', '1993', '3교구 (현성수 목사)', '부분참석 / 토요일 오전 ~ 주일 오전(11시)', '', '1~8조', 42),
  (88, 6, '6조', 'member', '11', '진형철', '1997', '3교구 (현성수 목사)', '부분참석 / 토요일 오전 ~ 주일 오전(11시)', '', '1~8조', 43),
  (89, 6, '6조', 'member', '13', '정하경', '1999', '2교구 (임동표 목사)', '부분참석 / 주일 오전(7시) ~ 월요일 새벽', '', '1~8조', 45),
  (90, 6, '6조', 'member', '14', '윤시환', '1996', '3교구 (현성수 목사)', '부분참석 / 주일 오전(7시) ~ 월요일 새벽', '', '1~8조', 46),
  (91, 6, '6조', 'member', '15', '허경웅', '1987', '4교구 (남우진 목사)', '부분참석 / 주일 오전(7시) ~ 월요일 오전(10시)', '', '1~8조', 47),
  (92, 7, '7조', 'leader', '조장', '한정인', '1999', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 54),
  (93, 7, '7조', 'member', '1', '이경룡', '1995', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 55),
  (94, 7, '7조', 'member', '2', '애니', '2007', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 56),
  (95, 7, '7조', 'member', '3', '석상은', '2001', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 57),
  (96, 7, '7조', 'member', '5', '마문도', '2004', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 58),
  (97, 7, '7조', 'member', '6', '정대호', '1999', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 59),
  (98, 7, '7조', 'member', '7', '김지원', '1998', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 60),
  (99, 7, '7조', 'member', '9', '최현아', '2001', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 62),
  (100, 7, '7조', 'member', '10', '배진형', '1985', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 63),
  (101, 7, '7조', 'member', '11', '천혜영', '1984', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 64),
  (102, 7, '7조', 'member', '12', 'Luke/Nyan Lynn Htet', '1997', '3교구 (현성수 목사)', '부분참석 /  토요일 오전(8시) ~ 토요일 오후(23시)', '', '1~8조', 65),
  (103, 7, '7조', 'member', '13', '송정연', '1996', '3교구 (현성수 목사)', '부분참석 / 주일 오전 9시 ~ 월요일 오전', '', '1~8조', 66),
  (104, 7, '7조', 'member', '14', 'Cheng jia shan', '2001', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 67),
  (105, 7, '7조', 'member', '15', '서규원', '2002', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '추가인원', '1~8조', 68),
  (106, 8, '8조', 'leader', '조장', '최미나', '1999', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 76),
  (107, 8, '8조', 'member', '1', '서가영', '2000', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 77),
  (108, 8, '8조', 'member', '2', '김지훈', '1997', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 78),
  (109, 8, '8조', 'member', '3', '주진호', '2005', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 79),
  (110, 8, '8조', 'member', '4', '김준희', '2002', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 80),
  (111, 8, '8조', 'member', '5', '김민경', '1988', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '1~8조', 81),
  (112, 8, '8조', 'member', '6', '유하은', '1998', '2교구 (임동표 목사)', '전체참석 / 토요일 오후(19시) ~ 주일 오후 (23시)', '', '1~8조', 82),
  (113, 8, '8조', 'member', '7', '여인규', '1998', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 83),
  (114, 8, '8조', 'member', '8', '김민설', '1993', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 84),
  (115, 8, '8조', 'member', '9', '전수호', '2005', '1교구 (유광훈 전도사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 85),
  (116, 8, '8조', 'member', '10', '최계은', '1988', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '1~8조', 86),
  (117, 8, '8조', 'member', '11', '이가희', '1985', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤(23시)', '', '1~8조', 87),
  (118, 8, '8조', 'member', '12', '신상희', '1993', '4교구 (남우진 목사)', '부분참석 / 토요일 오후 ~ 주일 오후(7시)', '', '1~8조', 88),
  (119, 8, '8조', 'member', '13', '이시환', '2001', '2교구 (임동표 목사)', '부분참석 / 주일 오후 (19시) ~ 주일 밤 (23)출발', '', '1~8조', 89),
  (120, 8, '8조', 'member', '14', '권혁준', '2004', '1교구 (유광훈 전도사)', '부분참석 / 주일 오전(7시) ~ 월요일 오전(10시)', '추가인원', '1~8조', 90),
  (121, 9, '9조', 'leader', '조장', '위유림', '1999', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 8),
  (122, 9, '9조', 'member', '1', '서채운', '2000', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 9),
  (123, 9, '9조', 'member', '2', '최한나', '1995', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 10),
  (124, 9, '9조', 'member', '3', '유하람', '1991', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 11),
  (125, 9, '9조', 'member', '4', '정명화', '1986', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 12),
  (126, 9, '9조', 'member', '5', '김용한', '1993', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 13),
  (127, 9, '9조', 'member', '6', '김도원', '2006', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 14),
  (128, 9, '9조', 'member', '7', '주건호', '2006', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 15),
  (129, 9, '9조', 'member', '8', '전준규', '1997', '3교구 (현성수 목사)', '전체참석 /  토 오후 ~ 월요일 오전', '', '9~16조', 16),
  (130, 9, '9조', 'member', '9', '허하은', '1999', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 17),
  (131, 9, '9조', 'member', '10', '김소영', '1998', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 18),
  (132, 9, '9조', 'member', '11', '김은정', '1995', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 19),
  (133, 9, '9조', 'member', '12', '손정인', '1999', '2교구 (임동표 목사)', '전체참석 / 토 오후 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 20),
  (134, 9, '9조', 'member', '13', '박신혜', '1988', '4교구 (남우진 목사)', '전체참석 / 토요일 오후(19시) ~ 월요일 새벽', '', '9~16조', 21),
  (135, 9, '9조', 'member', '14', '박은혜', '1987', '4교구 (남우진 목사)', '전체참석 / 토요일 오후(19시) ~ 월요일 새벽', '', '9~16조', 22),
  (136, 9, '9조', 'member', '15', '안진홍', '1997', '3교구 (현성수 목사)', '부분참석 / 토요일 오전~주일 오전(11시)', '', '9~16조', 23),
  (137, 10, '10조', 'leader', '조장', '신라엘', '1999', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 30),
  (138, 10, '10조', 'member', '1', '박세은', '2001', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 31),
  (139, 10, '10조', 'member', '2', '석재남', '2006', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 32),
  (140, 10, '10조', 'member', '3', '박소영', '2003', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 33),
  (141, 10, '10조', 'member', '4', '이성영', '1989', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 34),
  (142, 10, '10조', 'member', '5', '권영서', '2003', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 35),
  (143, 10, '10조', 'member', '6', '김동규', '2004', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 36),
  (144, 10, '10조', 'member', '7', '이주광', '1999', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 37),
  (145, 10, '10조', 'member', '8', '임지훈', '1995', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 38),
  (146, 10, '10조', 'member', '9', '김성은', '1997', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 39),
  (147, 10, '10조', 'member', '10', '조은산', '2000', '교구 미배정', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 40),
  (148, 10, '10조', 'member', '11', '이세희', '1990', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '추가인원', '9~16조', 41),
  (149, 10, '10조', 'member', '12', '홍수연', '1998', '2교구 (임동표 목사)', '부분참석 / 주일 오전(7시) ~ 월요일 새벽', '', '9~16조', 42),
  (150, 10, '10조', 'member', '13', '이지은', '1997', '3교구 (현성수 목사)', '부분참석 / 토 ~ 토요일 밤(23시)', '', '9~16조', 43),
  (151, 11, '11조', 'leader', '조장', '안지인', '1992', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 49),
  (152, 11, '11조', 'member', '1', '김병진', '1986', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 오후 (19시)', '', '9~16조', 50),
  (153, 11, '11조', 'member', '2', '한은지', '1990', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 51),
  (154, 11, '11조', 'member', '3', '정승호', '1979', '잘 모르겠다', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 52),
  (155, 11, '11조', 'member', '4', '전유나', '1992', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '조개, 새우 등 갑각류 알레르기', '9~16조', 53),
  (156, 11, '11조', 'member', '5', '조현규', '1996', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '갑각류 알레르기', '9~16조', 54),
  (157, 11, '11조', 'member', '6', '김시진', '1995', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 55),
  (158, 11, '11조', 'member', '7', '염수진', '1992', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 56),
  (159, 11, '11조', 'member', '8', '김현', '2002', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '천식,피부 알레르기', '9~16조', 57),
  (160, 11, '11조', 'member', '9', '권영빈', '1995', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 58),
  (161, 11, '11조', 'member', '10', '김아현', '1996', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '햇빛 알레르기', '9~16조', 59),
  (162, 11, '11조', 'member', '11', '최지호', '2004', '1교구 (유광훈 전도사)', '부분참석 / 토요일 오전~주일 오전(11시)', '', '9~16조', 60),
  (163, 11, '11조', 'member', '12', '소수엽', '1995', '3교구 (현성수 목사)', '부분참석 / 주일 오전(7시) ~ 월요일 새벽', '', '9~16조', 61),
  (164, 11, '11조', 'member', '13', '나성진', '1993', '잘 모르겠다', '부분참석 /  주일 오전(7시) ~ 월요일 오전(10시)', '', '9~16조', 62),
  (165, 11, '11조', 'member', '14', '박미지', '1993', '3교구 (현성수 목사)', '부분참석 / 주일 오전(9시) ~ 주일 오후(23시)', '', '9~16조', 63),
  (166, 12, '12조', 'leader', '조장', '신영호', '1996', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 71),
  (167, 12, '12조', 'member', '1', '장진아', '2001', '잘 모르겠다', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 72),
  (168, 12, '12조', 'member', '2', '이현기', '1997', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 73),
  (169, 12, '12조', 'member', '3', '문지수', '2001', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 74),
  (170, 12, '12조', 'member', '4', '송예린', '2007', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 75),
  (171, 12, '12조', 'member', '5', '박유나', '2000', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 76),
  (172, 12, '12조', 'member', '6', '이찬영', '1996', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 77),
  (173, 12, '12조', 'member', '7', '박예은', '2000', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 78),
  (174, 12, '12조', 'member', '8', '안이삭', '1998', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 79),
  (175, 12, '12조', 'member', '10', '유영수', '2003', '1교구 (유광훈 전도사)', '부분참석 / 토요일 오전~주일 오전(11시)', '', '9~16조', 81),
  (176, 12, '12조', 'member', '11', '허세빈', '1999', '2교구 (임동표 목사)', '부분참석 / 토요일 오전~주일 오후(16시)', '', '9~16조', 82),
  (177, 12, '12조', 'member', '12', '전승훈', '1989', '4교구 (남우진 목사)', '부분참석 / 토요일 오후 ~ 주일 오후(7시)', '', '9~16조', 83),
  (178, 12, '12조', 'member', '13', '이상은', '2005', '1교구 (유광훈 전도사)', '부분참석 / 주일 오전(7시) ~ 월요일 오전(10시)', '', '9~16조', 84),
  (179, 12, '12조', 'member', '14', '김영훈', '1995', '3교구 (현성수 목사)', '부분참석 / 주일 오전(10시) ~ 주일 오후(23시)', '', '9~16조', 85),
  (180, 12, '12조', 'member', '16', '이예인', '2000', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '추가인원', '9~16조', 87),
  (181, 13, '13조', 'leader', '조장', '조연주', '1994', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 8),
  (182, 13, '13조', 'member', '1', '김진웅', '1993', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 9),
  (183, 13, '13조', 'member', '2', '김태훈', '2001', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 10),
  (184, 13, '13조', 'member', '3', '박재균', '2002', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 11),
  (185, 13, '13조', 'member', '4', '성예림', '2004', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 12),
  (186, 13, '13조', 'member', '5', '권수민', '2003', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 13),
  (187, 13, '13조', 'member', '6', '정다운', '1990', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 14),
  (188, 13, '13조', 'member', '7', '최승원', '1989', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 15),
  (189, 13, '13조', 'member', '8', '서다예', '1996', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '갑각류 해산물 알레르기 / 피부질환 비오거나 습하면 심해짐', '9~16조', 16),
  (190, 13, '13조', 'member', '9', '이예은', '1995', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 17),
  (191, 13, '13조', 'member', '10', '고서윤', '1999', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 18),
  (192, 13, '13조', 'member', '11', '최원경', '1993', '4교구 (남우진 목사)', '전체참석 /  토 오후 (17시) ~ 주일 밤', '', '9~16조', 19),
  (193, 13, '13조', 'member', '12', '마단단', '1997', '3교구 (현성수 목사)', '부분참석 / 주일 오전 9시 ~ 월요일 오전', '', '9~16조', 20),
  (194, 13, '13조', 'member', '13', '이제형', '2002', '1교구 (유광훈 전도사)', '부분참석 / 토요일 오전~주일 오전(11시)', '', '9~16조', 21),
  (195, 13, '13조', 'member', '14', '전승아', '2002', '3교구 (현성수 목사)', '부분참석 / 토 (17~23시), 주일 (18시~23시)', '', '9~16조', 22),
  (196, 13, '13조', 'member', '15', '김승현', '1995', '3교구 (현성수 목사)', '부분참석 / 토 (17~23시), 주일 (18시~23시)', '', '9~16조', 23),
  (197, 14, '14조', 'leader', '조장', '박원진', '1988', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 29),
  (198, 14, '14조', 'member', '1', '신소희', '1991', '4교구 (남우진 목사)', '전체참석 /  토 오후 ~ 월요일 오전', '', '9~16조', 30),
  (199, 14, '14조', 'member', '2', '여창민', '1989', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 31),
  (200, 14, '14조', 'member', '3', '최가은', '2001', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 32),
  (201, 14, '14조', 'member', '4', '김다정', '2001', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 33),
  (202, 14, '14조', 'member', '5', '이원철', '1996', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 34),
  (203, 14, '14조', 'member', '6', '이서정', '2001', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 35),
  (204, 14, '14조', 'member', '7', '노희예', '1996', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 36),
  (205, 14, '14조', 'member', '8', '김광희', '1993', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 37),
  (206, 14, '14조', 'member', '9', '주대현', '2001', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 38),
  (207, 14, '14조', 'member', '10', '김은서', '1993', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 39),
  (208, 14, '14조', 'member', '11', '이돈영', '2002', '2교구 (임동표 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 40),
  (209, 14, '14조', 'member', '12', '김예닮', '1997', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 41),
  (210, 14, '14조', 'member', '13', '박현우', '1993', '4교구 (남우진 목사)', '부분참석 / 토요일 오후 (18시 ~  22시)', '', '9~16조', 42),
  (211, 15, '15조', 'leader', '조장', '설예랑', '1991', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 48),
  (212, 15, '15조', 'member', '1', '이성호', '1992', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 49),
  (213, 15, '15조', 'member', '2', '신보라', '2006', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '햇빛알레르기, 먼지알레르기', '9~16조', 50),
  (214, 15, '15조', 'member', '3', '김지유', '2006', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 51),
  (215, 15, '15조', 'member', '4', '김해솔', '2000', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 52),
  (216, 15, '15조', 'member', '5', '손희성', '2006', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 53),
  (217, 15, '15조', 'member', '6', '박성온', '1993', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 54),
  (218, 15, '15조', 'member', '7', '황영조', '1995', '잘 모르겠다', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 55),
  (219, 15, '15조', 'member', '8', '김민석', '1995', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 56),
  (220, 15, '15조', 'member', '9', '이진성', '1992', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 57),
  (221, 15, '15조', 'member', '10', '하나은', '1995', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 58),
  (222, 15, '15조', 'member', '11', '유형준', '1983', '4교구 (남우진 목사)', '부분참석 / 토 점심 (12시) ~ 주일 오후 (16시)', '', '9~16조', 59),
  (223, 15, '15조', 'member', '12', '황주원', '1994', '3교구 (현성수 목사)', '부분참석 / 토요일 오후 (18시 ~22시)', '', '9~16조', 60),
  (224, 15, '15조', 'member', '13', '김보희', '1995', '3교구 (현성수 목사)', '부분참석 /  주일 오전(7시) ~ 월요일 오전(10시)', '', '9~16조', 61),
  (225, 15, '15조', 'member', '14', '최보슬', '1999', '2교구 (임동표 목사)', '부분참석 / 주일 오후(20시) ~ 월요일 오전', '', '9~16조', 62),
  (226, 15, '15조', 'member', '15', '하선엽', '1994', '3교구 (현성수 목사)', '전체참석 / 토 오후 (15시) ~ 주일 오후 (22시)', '', '9~16조', 63),
  (227, 16, '16조', 'leader', '조장', '김서라', '1992', '4교구 (남우진 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 71),
  (228, 16, '16조', 'member', '1', '공다영', '1994', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 72),
  (229, 16, '16조', 'member', '2', '김영진', '1994', '3교구 (현성수 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 73),
  (230, 16, '16조', 'member', '3', '문진우', '1990', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 74),
  (231, 16, '16조', 'member', '4', '윤별', '1993', '4교구 (남우진 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 75),
  (232, 16, '16조', 'member', '6', '한별', '1998', '2교구 (임동표 목사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 77),
  (233, 16, '16조', 'member', '7', '박성호', '2004', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '', '9~16조', 78),
  (234, 16, '16조', 'member', '8', '김미경', '1994', '3교구 (현성수 목사)', '전체참석 / 토 ~ 주일 밤 (월요일 새벽)', '', '9~16조', 79),
  (235, 16, '16조', 'member', '9', '신혜지', '1998', '잘 모르겠다', '전체참석 / 토 ~ 주일저녁', '척추측만증 허리 불편', '9~16조', 80),
  (236, 16, '16조', 'member', '10', '김주와', '2007', '1교구 (유광훈 전도사)', '부분참석 / 토요일 오전~주일 오전(11시)', '', '9~16조', 81),
  (237, 16, '16조', 'member', '11', '정요안', '1991', '4교구 (남우진 목사)', '부분참석 / 토요일 저녁 ~ 주일 오후(23시)', '', '9~16조', 82),
  (238, 16, '16조', 'member', '12', '김빛아름', '1989', '4교구 (남우진 목사)', '부분참석 / 주일 오전(7시) ~ 주일 밤(23시)', '', '9~16조', 83),
  (239, 16, '16조', 'member', '13', '김민희', '1984', '4교구 (남우진 목사)', '부분참석 / 주일 오전(7시) ~ 주일 밤(23시)', '', '9~16조', 84),
  (240, 16, '16조', 'member', '14', '김재원', '2005', '1교구 (유광훈 전도사)', '부분참석 /  주일 오전(7시) ~ 월요일 오전(10시)', '', '9~16조', 85),
  (241, 16, '16조', 'member', '15', '전지호', '2007', '1교구 (유광훈 전도사)', '부분참석 / 토요일 오후(7시) ~주일 밤', '추가인원', '9~16조', 86),
  (242, 16, '16조', 'member', '16', '안재신', '1988', '4교구 (남우진 목사)', '부분참석 /  주일 오전(7시) ~ 월요일 새벽', '추가인원', '9~16조', 87),
  (243, 16, '16조', 'member', '18', '임재민', '2002', '1교구 (유광훈 전도사)', '전체참석 /  토 ~ 월요일 오전', '추가인원', '9~16조', 89);

create temp table latest_bbb_roster_match as
with ranked as (
  select
    d.stable_key,
    r.id as roster_id,
    row_number() over (
      partition by d.stable_key
      order by
        case when r.group_no = d.group_no then 0 else 1 end,
        case when r.group_no is not null then 0 else 1 end,
        case when regexp_replace(coalesce(r.note, ''), '\s+', '', 'g') like '%' || '조에서제외' || '%' then 1 else 0 end,
        r.roster_order
    ) as rn
  from latest_bbb_roster_patch d
  join public.retreat_group_roster r
    on r.source_batch = '20260614'
   and r.name_norm = d.name_norm
   and coalesce(r.birth_year, '') = coalesce(d.birth_year, '')
)
select stable_key, roster_id
from ranked
where rn = 1;

create temp table latest_bbb_roster_replacement as
select
  r.id as old_roster_id,
  m.roster_id as replacement_roster_id
from public.retreat_group_roster r
join latest_bbb_roster_patch d
  on d.name_norm = r.name_norm
 and coalesce(d.birth_year, '') = coalesce(r.birth_year, '')
join latest_bbb_roster_match m
  on m.stable_key = d.stable_key
where r.source_batch = '20260614'
  and r.id <> m.roster_id;

insert into public.retreat_group_roster_removed (
  id,
  source_batch,
  participant_name,
  birth_year,
  removed_reason,
  replacement_roster_id,
  roster_snapshot,
  removed_at
)
select
  r.id,
  r.source_batch,
  r.participant_name,
  r.birth_year,
  case
    when rep.replacement_roster_id is not null then 'latest_xlsx_duplicate_or_moved_replaced'
    else 'latest_xlsx_removed_or_auxiliary_row'
  end,
  rep.replacement_roster_id,
  to_jsonb(r),
  now()
from public.retreat_group_roster r
left join latest_bbb_roster_match m on m.roster_id = r.id
left join latest_bbb_roster_replacement rep on rep.old_roster_id = r.id
where r.source_batch = '20260614'
  and m.roster_id is null
on conflict (id) do update
set removed_reason = excluded.removed_reason,
    replacement_roster_id = excluded.replacement_roster_id,
    roster_snapshot = excluded.roster_snapshot,
    removed_at = now();

update public.retreat_group_roster r
set care_buddy_roster_id = rep.replacement_roster_id,
    updated_at = now()
from public.retreat_group_roster_removed rem
left join latest_bbb_roster_replacement rep on rep.old_roster_id = rem.id
where r.source_batch = '20260614'
  and r.care_buddy_roster_id = rem.id;

update public.retreat_group_roster r
set secret_buddy_roster_id = rep.replacement_roster_id,
    updated_at = now()
from public.retreat_group_roster_removed rem
left join latest_bbb_roster_replacement rep on rep.old_roster_id = rem.id
where r.source_batch = '20260614'
  and r.secret_buddy_roster_id = rem.id;

do $$
begin
  if to_regclass('public.bbb_extra_care_roster_links') is not null then
    execute $dyn$
      update public.bbb_extra_care_roster_links l
      set care_giver_roster_id = rep.replacement_roster_id,
          updated_at = now()
      from latest_bbb_roster_replacement rep
      where l.care_giver_roster_id = rep.old_roster_id
        and rep.replacement_roster_id is not null
    $dyn$;

    execute $dyn$
      update public.bbb_extra_care_roster_links l
      set care_receiver_roster_id = rep.replacement_roster_id,
          updated_at = now()
      from latest_bbb_roster_replacement rep
      where l.care_receiver_roster_id = rep.old_roster_id
        and rep.replacement_roster_id is not null
    $dyn$;

    execute $dyn$
      delete from public.bbb_extra_care_roster_links l
      using public.retreat_group_roster_removed rem
      where l.care_giver_roster_id = rem.id
         or l.care_receiver_roster_id = rem.id
    $dyn$;
  end if;
end;
$$;

delete from public.retreat_group_roster r
using public.retreat_group_roster_removed rem
where r.id = rem.id
  and r.source_batch = '20260614';

update public.retreat_group_roster r
set roster_order = -100000 - abs(r.roster_order),
    updated_at = now()
where r.source_batch = '20260614';

update public.retreat_group_roster r
set roster_order = d.desired_order,
    group_no = d.group_no,
    group_label = d.group_label,
    group_id = g.id,
    group_role = d.group_role::public.group_role,
    raw_role = d.raw_role,
    participant_name = d.participant_name,
    name_norm = d.name_norm,
    birth_year = d.birth_year,
    parish_raw = d.parish_raw,
    parish_norm = d.parish_norm,
    participation_schedule = d.participation_schedule,
    participation_tier = d.participation_tier,
    note = d.note,
    source_sheet = d.source_sheet,
    source_row = d.source_row,
    updated_at = now()
from latest_bbb_roster_patch d
join latest_bbb_roster_match m on m.stable_key = d.stable_key
left join public.groups g on g.group_no = d.group_no
where r.id = m.roster_id;

insert into public.retreat_group_roster (
  source_batch,
  roster_order,
  group_no,
  group_label,
  group_id,
  group_role,
  raw_role,
  participant_name,
  name_norm,
  birth_year,
  parish_raw,
  parish_norm,
  participation_schedule,
  participation_tier,
  note,
  source_sheet,
  source_row
)
select
  '20260614',
  d.desired_order,
  d.group_no,
  d.group_label,
  g.id,
  d.group_role::public.group_role,
  d.raw_role,
  d.participant_name,
  d.name_norm,
  d.birth_year,
  d.parish_raw,
  d.parish_norm,
  d.participation_schedule,
  d.participation_tier,
  d.note,
  d.source_sheet,
  d.source_row
from latest_bbb_roster_patch d
left join latest_bbb_roster_match m on m.stable_key = d.stable_key
left join public.groups g on g.group_no = d.group_no
where m.roster_id is null;

create temp table latest_bbb_roster_final_cleanup as
select
  r.id as old_roster_id,
  rep.replacement_roster_id
from public.retreat_group_roster r
left join latest_bbb_roster_patch exact
  on exact.desired_order = r.roster_order
 and exact.group_no is not distinct from r.group_no
 and exact.name_norm = r.name_norm
 and coalesce(exact.birth_year, '') = coalesce(r.birth_year, '')
left join latest_bbb_roster_replacement rep
  on rep.old_roster_id = r.id
where r.source_batch = '20260614'
  and exact.stable_key is null;

insert into public.retreat_group_roster_removed (
  id,
  source_batch,
  participant_name,
  birth_year,
  removed_reason,
  replacement_roster_id,
  roster_snapshot,
  removed_at
)
select
  r.id,
  r.source_batch,
  r.participant_name,
  r.birth_year,
  case
    when f.replacement_roster_id is not null then 'latest_xlsx_final_cleanup_duplicate_or_moved_replaced'
    else 'latest_xlsx_final_cleanup_not_in_desired'
  end,
  f.replacement_roster_id,
  to_jsonb(r),
  now()
from public.retreat_group_roster r
join latest_bbb_roster_final_cleanup f on f.old_roster_id = r.id
on conflict (id) do update
set removed_reason = excluded.removed_reason,
    replacement_roster_id = excluded.replacement_roster_id,
    roster_snapshot = excluded.roster_snapshot,
    removed_at = now();

update public.retreat_group_roster r
set care_buddy_roster_id = f.replacement_roster_id,
    updated_at = now()
from latest_bbb_roster_final_cleanup f
where r.source_batch = '20260614'
  and r.care_buddy_roster_id = f.old_roster_id;

update public.retreat_group_roster r
set secret_buddy_roster_id = f.replacement_roster_id,
    updated_at = now()
from latest_bbb_roster_final_cleanup f
where r.source_batch = '20260614'
  and r.secret_buddy_roster_id = f.old_roster_id;

do $$
begin
  if to_regclass('public.bbb_extra_care_roster_links') is not null then
    execute $dyn$
      delete from public.bbb_extra_care_roster_links l
      using latest_bbb_roster_final_cleanup f
      where l.care_giver_roster_id = f.old_roster_id
         or l.care_receiver_roster_id = f.old_roster_id
    $dyn$;
  end if;
end;
$$;

delete from public.retreat_group_roster r
using latest_bbb_roster_final_cleanup f
where r.id = f.old_roster_id
  and r.source_batch = '20260614';

select public.bu_sync_group_roster_profile_matches('20260614') as sync_result;

delete from public.group_members gm
using public.groups g
where gm.group_id = g.id
  and g.group_no between 1 and 16
  and not exists (
    select 1
    from public.retreat_group_roster r
    where r.source_batch = '20260614'
      and r.matched_profile_id = gm.profile_id
      and r.group_id = gm.group_id
  );

with validation as (
  select
    (select count(*) from latest_bbb_roster_patch) as desired_rows,
    (select count(*) from public.retreat_group_roster where source_batch = '20260614') as actual_rows,
    (select count(*) from public.retreat_group_roster where source_batch = '20260614' and group_no is null) as null_group_rows,
    (select count(*) from public.retreat_group_roster where source_batch = '20260614' and regexp_replace(coalesce(note, ''), '\s+', '', 'g') like '%' || '조에서제외' || '%') as excluded_note_rows,
    (select count(*) from (
      select name_norm, coalesce(birth_year, '') as birth_year, count(*) as row_count
      from public.retreat_group_roster
      where source_batch = '20260614'
      group by name_norm, coalesce(birth_year, '')
      having count(*) > 1
    ) duplicated_identity) as duplicate_identity_rows,
    (select count(*) from public.retreat_group_roster_removed where source_batch = '20260614') as removed_snapshot_rows,
    (select count(*) from latest_bbb_roster_match) as reused_rows,
    (select count(*) from latest_bbb_roster_patch d left join latest_bbb_roster_match m on m.stable_key = d.stable_key where m.roster_id is null) as inserted_rows,
    (select count(*) from latest_bbb_roster_final_cleanup) as final_cleanup_rows
)
select
  case when desired_rows = actual_rows and null_group_rows = 0 and excluded_note_rows = 0 and duplicate_identity_rows = 0 then true else false end as ok,
  desired_rows,
  actual_rows,
  reused_rows,
  inserted_rows,
  final_cleanup_rows,
  removed_snapshot_rows,
  null_group_rows,
  excluded_note_rows,
  duplicate_identity_rows
from validation;

commit;


-- ============================================================
-- 008 roster name fallback
-- source: beyond_us/supabase/migrations/20260620000800_bbb_roster_name_fallback.sql
-- ============================================================
-- B.B.B. 케어버디와 시크릿버디 표시 이름을 조 명단 이름 기준으로 보정한다.
begin;

create or replace function public.bu_clean_display_text(p_value text)
returns text
language sql
immutable
as $$
  select case
    when p_value is null then null
    when btrim(p_value) = '' then null
    when lower(btrim(p_value)) in ('null', 'undefined') then null
    else btrim(p_value)
  end;
$$;

create or replace function public.get_bbb_status(p_login_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_assignment public.bbb_assignments%rowtype;
  v_care public.profiles%rowtype;
  v_secret public.profiles%rowtype;
  v_roster_id uuid;
  v_care_roster_id uuid;
  v_secret_roster_id uuid;
  v_care_roster_name text := '';
  v_secret_roster_name text := '';
  v_care_profile_id uuid;
  v_secret_profile_id uuid;
  v_care_name text := '';
  v_secret_name text := '';
  v_extra_care_buddies jsonb := '[]'::jsonb;
  v_photos jsonb := '{}'::jsonb;
  v_caught boolean := false;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  v_photos := public.bu_photo_payload(v_profile.id);

  select *
  into v_assignment
  from public.bbb_assignments
  where profile_id = v_profile.id;

  select
    r.id,
    care.id,
    secret.id,
    public.bu_clean_display_text(care.participant_name),
    public.bu_clean_display_text(secret.participant_name),
    care.matched_profile_id,
    secret.matched_profile_id
  into
    v_roster_id,
    v_care_roster_id,
    v_secret_roster_id,
    v_care_roster_name,
    v_secret_roster_name,
    v_care_profile_id,
    v_secret_profile_id
  from public.retreat_group_roster r
  left join public.retreat_group_roster care on care.id = r.care_buddy_roster_id
  left join public.retreat_group_roster secret on secret.id = r.secret_buddy_roster_id
  where r.source_batch = '20260614'
    and r.matched_profile_id = v_profile.id
  order by r.roster_order
  limit 1;

  v_care_profile_id := coalesce(v_assignment.care_buddy_id, v_care_profile_id);
  v_secret_profile_id := coalesce(v_assignment.secret_buddy_id, v_secret_profile_id);

  if v_assignment.profile_id is null and v_roster_id is null then
    return jsonb_build_object(
      'ok', false,
      'source', 'supabase',
      'error', 'no_match'
    ) || v_photos;
  end if;

  if v_care_profile_id is not null then
    select *
    into v_care
    from public.profiles
    where id = v_care_profile_id;
  end if;

  if v_secret_profile_id is not null then
    select *
    into v_secret
    from public.profiles
    where id = v_secret_profile_id;
  end if;

  if v_roster_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'name', coalesce(
        public.bu_clean_display_text(receiver.participant_name),
        public.bu_clean_display_text(rp.name),
        public.bu_clean_display_text(rp.display_name),
        public.bu_clean_display_text(rp.login_id::text),
        '이름 확인 중'
      ),
      'participantName', public.bu_clean_display_text(receiver.participant_name),
      'displayName', public.bu_clean_display_text(rp.display_name),
      'nickname', coalesce(public.bu_clean_display_text(rp.login_id::text), ''),
      'groupNo', receiver.group_no,
      'tier', coalesce(receiver.participation_tier, '')
    ) order by receiver.group_no, receiver.roster_order), '[]'::jsonb)
    into v_extra_care_buddies
    from public.bbb_extra_care_roster_links link
    join public.retreat_group_roster receiver on receiver.id = link.care_receiver_roster_id
    left join public.profiles rp on rp.id = receiver.matched_profile_id
    where link.source_batch = '20260614'
      and link.care_giver_roster_id = v_roster_id;
  end if;

  v_care_name := coalesce(
    public.bu_clean_display_text(v_care_roster_name),
    public.bu_clean_display_text(v_care.name),
    public.bu_clean_display_text(v_care.display_name),
    public.bu_clean_display_text(v_care.login_id::text),
    '이름 확인 중'
  );

  v_secret_name := coalesce(
    public.bu_clean_display_text(v_secret_roster_name),
    public.bu_clean_display_text(v_secret.name),
    public.bu_clean_display_text(v_secret.display_name),
    public.bu_clean_display_text(v_secret.login_id::text),
    ''
  );

  select exists(
    select 1
    from public.bbb_assignments other_assignment
    where other_assignment.care_buddy_id = v_profile.id
      and other_assignment.secret_revealed = true
  )
  into v_caught;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'careBuddy', jsonb_build_object(
      'name', v_care_name,
      'participantName', public.bu_clean_display_text(v_care_roster_name),
      'displayName', public.bu_clean_display_text(v_care.display_name),
      'nickname', coalesce(public.bu_clean_display_text(v_care.login_id::text), '')
    ),
    'extraCareBuddies', coalesce(v_extra_care_buddies, '[]'::jsonb),
    'secretBuddy', case
      when v_secret_profile_id is null and v_secret_roster_id is null then null
      when coalesce(v_assignment.secret_revealed, false) then jsonb_build_object(
        'revealed', true,
        'name', coalesce(public.bu_clean_display_text(v_secret_name), '이름 확인 중'),
        'participantName', public.bu_clean_display_text(v_secret_roster_name),
        'displayName', public.bu_clean_display_text(v_secret.display_name),
        'nickname', coalesce(public.bu_clean_display_text(v_secret.login_id::text), '')
      )
      else jsonb_build_object(
        'revealed', false,
        'hint', '아직 비밀이에요'
      )
    end,
    'caughtByBuddy', v_caught
  ) || v_photos;
end;
$$;

create or replace function public.admin_bbb_pilgrim_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_rows jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  with active_users as (
    select p.*
    from public.profiles p
    where p.account_status = 'active'
  ),
  ensured_assignments as (
    select
      u.id as profile_id,
      public.bu_ensure_pilgrim_assignment(u.id) as spot_indices
    from active_users u
  ),
  latest_photos as (
    select distinct on (s.profile_id, s.mission_key, s.spot_index)
      s.profile_id,
      s.mission_key,
      s.spot_index,
      s.storage_path,
      s.approval_status,
      s.reward_event_id,
      s.created_at,
      s.updated_at
    from public.mission_photo_submissions s
    where s.mission_key in ('bbb_m1', 'bbb_m2', 'pilgrim')
    order by s.profile_id, s.mission_key, s.spot_index, s.updated_at desc, s.id desc
  ),
  bbb_photo_summary as (
    select
      profile_id,
      coalesce((jsonb_agg(jsonb_build_object(
        'status', approval_status,
        'storagePath', storage_path,
        'rewarded', reward_event_id is not null,
        'uploadedAt', created_at,
        'updatedAt', updated_at
      ) order by updated_at desc) filter (where mission_key = 'bbb_m1'))->0, '{}'::jsonb) as m1,
      coalesce((jsonb_agg(jsonb_build_object(
        'status', approval_status,
        'storagePath', storage_path,
        'rewarded', reward_event_id is not null,
        'uploadedAt', created_at,
        'updatedAt', updated_at
      ) order by updated_at desc) filter (where mission_key = 'bbb_m2'))->0, '{}'::jsonb) as m2
    from latest_photos
    where mission_key in ('bbb_m1', 'bbb_m2')
    group by profile_id
  ),
  pilgrim_photo_summary as (
    select
      profile_id,
      coalesce(jsonb_agg(jsonb_build_object(
        'spotIndex', spot_index,
        'status', approval_status,
        'storagePath', storage_path,
        'uploadedAt', created_at,
        'updatedAt', updated_at
      ) order by spot_index) filter (where mission_key = 'pilgrim'), '[]'::jsonb) as spot_photos,
      coalesce(jsonb_agg(spot_index order by spot_index) filter (where mission_key = 'pilgrim' and approval_status = 'approved'), '[]'::jsonb) as completed_spots
    from latest_photos
    where mission_key = 'pilgrim'
    group by profile_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'userId', u.login_id,
    'name', coalesce(public.bu_clean_display_text(u.name), ''),
    'displayName', coalesce(public.bu_clean_display_text(u.display_name), ''),
    'parish', coalesce(public.bu_clean_display_text(u.parish), ''),
    'careBuddy', jsonb_build_object(
      'userId', coalesce(
        public.bu_clean_display_text(care.login_id::text),
        public.bu_clean_display_text(care_roster_profile.login_id::text),
        ''
      ),
      'name', coalesce(
        public.bu_clean_display_text(care_roster.participant_name),
        public.bu_clean_display_text(care.name),
        public.bu_clean_display_text(care_roster_profile.name),
        public.bu_clean_display_text(care.display_name),
        public.bu_clean_display_text(care_roster_profile.display_name),
        public.bu_clean_display_text(care.login_id::text),
        public.bu_clean_display_text(care_roster_profile.login_id::text),
        ''
      )
    ),
    'secretBuddy', jsonb_build_object(
      'userId', coalesce(
        public.bu_clean_display_text(secret.login_id::text),
        public.bu_clean_display_text(secret_roster_profile.login_id::text),
        ''
      ),
      'name', coalesce(
        public.bu_clean_display_text(secret_roster.participant_name),
        public.bu_clean_display_text(secret.name),
        public.bu_clean_display_text(secret_roster_profile.name),
        public.bu_clean_display_text(secret.display_name),
        public.bu_clean_display_text(secret_roster_profile.display_name),
        public.bu_clean_display_text(secret.login_id::text),
        public.bu_clean_display_text(secret_roster_profile.login_id::text),
        ''
      )
    ),
    'secretRevealed', coalesce(ba.secret_revealed, false),
    'tier', coalesce(public.bu_clean_display_text(ba.tier), public.bu_clean_display_text(roster.participation_tier), ''),
    'groupNo', coalesce(g.group_no, roster.group_no),
    'groupName', coalesce(public.bu_clean_display_text(g.name), public.bu_clean_display_text(roster.group_label), ''),
    'm1', coalesce(bps.m1, '{}'::jsonb),
    'm2', coalesce(bps.m2, '{}'::jsonb),
    'pilgrimAssignedSpots', coalesce(to_jsonb(ea.spot_indices), '[]'::jsonb),
    'pilgrimCompletedSpots', coalesce(pps.completed_spots, '[]'::jsonb),
    'pilgrimSpotPhotos', coalesce(pps.spot_photos, '[]'::jsonb),
    'pilgrimCompleted', pa.completed_at is not null,
    'pilgrimCompletedAt', pa.completed_at,
    'pilgrimRewarded', pa.reward_event_id is not null
  ) order by
    coalesce(array_position(array['1청','2청','3청','4청','VIP','교회학교','목양교구'], u.parish), 99),
    u.name nulls last,
    u.login_id), '[]'::jsonb)
  into v_rows
  from active_users u
  left join ensured_assignments ea on ea.profile_id = u.id
  left join lateral (
    select r.*
    from public.retreat_group_roster r
    where r.source_batch = '20260614'
      and r.matched_profile_id = u.id
    order by r.roster_order
    limit 1
  ) roster on true
  left join public.retreat_group_roster care_roster on care_roster.id = roster.care_buddy_roster_id
  left join public.retreat_group_roster secret_roster on secret_roster.id = roster.secret_buddy_roster_id
  left join public.profiles care_roster_profile on care_roster_profile.id = care_roster.matched_profile_id
  left join public.profiles secret_roster_profile on secret_roster_profile.id = secret_roster.matched_profile_id
  left join public.bbb_assignments ba on ba.profile_id = u.id
  left join public.profiles care on care.id = ba.care_buddy_id
  left join public.profiles secret on secret.id = ba.secret_buddy_id
  left join public.groups g on g.id = coalesce(ba.group_id, roster.group_id)
  left join public.pilgrim_assignments pa on pa.profile_id = u.id
  left join bbb_photo_summary bps on bps.profile_id = u.id
  left join pilgrim_photo_summary pps on pps.profile_id = u.id;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_bbb_status(text) from public, anon, authenticated;
revoke all on function public.admin_bbb_pilgrim_status() from public, anon, authenticated;
grant execute on function public.get_bbb_status(text) to authenticated;
grant execute on function public.admin_bbb_pilgrim_status() to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;


-- ============================================================
-- 009 manual profile reassign
-- source: beyond_us/supabase/migrations/20260620000900_bbb_manual_profile_reassign.sql
-- ============================================================
-- B.B.B. 조 명단 수동 매칭에서 이미 매칭된 앱 계정을 새 row로 이동할 수 있게 한다.
begin;

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
  v_existing_roster_ids uuid[] := array[]::uuid[];
  v_reassigned integer := 0;
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
    and account_status = 'active';

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'profile_not_found');
  end if;

  if public.bu_group_roster_normalize_name(v_profile.name) is distinct from v_roster.name_norm then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'name_mismatch');
  end if;

  select coalesce(array_agg(r.id order by r.roster_order), array[]::uuid[])
  into v_existing_roster_ids
  from public.retreat_group_roster r
  where r.source_batch = v_roster.source_batch
    and r.matched_profile_id = p_profile_id
    and r.id <> p_roster_id;

  if coalesce(array_length(v_existing_roster_ids, 1), 0) > 0 then
    update public.retreat_group_roster r
    set matched_profile_id = null,
        match_status = 'manual_unmatched',
        match_detail = '관리자 수동 매칭 이동으로 기존 연결 해제',
        updated_at = now()
    where r.id = any(v_existing_roster_ids);

    get diagnostics v_reassigned = row_count;
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

  perform public.bu_sync_bbb_assignments_from_roster(v_roster.source_batch);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'rosterId', p_roster_id,
    'profileId', p_profile_id,
    'matchStatus', 'matched_manual',
    'reassignedFromRosterIds', to_jsonb(v_existing_roster_ids),
    'reassignedRows', coalesce(v_reassigned, 0)
  );
end;
$$;

revoke all on function public.admin_resolve_group_roster_profile(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_resolve_group_roster_profile(uuid, uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
