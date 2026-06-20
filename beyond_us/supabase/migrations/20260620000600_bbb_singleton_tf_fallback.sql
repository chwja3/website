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
