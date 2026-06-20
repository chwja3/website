-- H&P 정답 판정 완화와 B.B.B. 조 명단 기반 보상/표시를 보강한다.
begin;

create or replace function public.bu_hp_answer_matches(
  p_guess text,
  p_answer text
)
returns boolean
language sql
immutable
as $$
  select public.bu_hp_answer_key(p_guess) <> '';
$$;

create or replace function public.bu_hold_pray_answer_matches(
  p_entry_id uuid,
  p_guess text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.bu_hp_answer_key(p_guess) <> '';
$$;

create or replace function public.bu_issue_special_pack_for_photo(
  p_profile_id uuid,
  p_mission_key text,
  p_admin_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
  v_mission_key text := nullif(btrim(coalesce(p_mission_key, '')), '');
begin
  if p_profile_id is null or v_mission_key is null then
    return null;
  end if;

  perform pg_advisory_xact_lock(hashtext('bbb_photo_reward:' || p_profile_id::text || ':' || v_mission_key));

  select reward_event_id
  into v_event_id
  from public.mission_photo_submissions
  where profile_id = p_profile_id
    and mission_key = v_mission_key
    and reward_event_id is not null
  order by approved_at desc nulls last, updated_at desc
  limit 1;

  if v_event_id is not null then
    return v_event_id;
  end if;

  select id
  into v_event_id
  from public.events
  where profile_id = p_profile_id
    and event_type = 'special_pack.granted'
    and ref_type = v_mission_key
  order by occurred_at desc, created_at desc
  limit 1;

  if v_event_id is not null then
    return v_event_id;
  end if;

  insert into public.user_inventory (
    profile_id,
    special_pack_earned,
    special_pack_remaining
  )
  values (
    p_profile_id,
    1,
    1
  )
  on conflict (profile_id) do update
  set special_pack_earned = public.user_inventory.special_pack_earned + 1,
      special_pack_remaining = public.user_inventory.special_pack_remaining + 1,
      updated_at = now();

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    amount,
    payload,
    source,
    created_by
  )
  values (
    p_profile_id,
    'special_pack.granted',
    v_mission_key,
    1,
    jsonb_build_object('reason', 'photo_approved', 'missionKey', v_mission_key),
    'admin',
    p_admin_id
  )
  returning id into v_event_id;

  perform public.bu_refresh_profile_summary(p_profile_id);

  return v_event_id;
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
    'secretBuddy', case
      when v_secret_profile_id is null and v_secret_roster_id is null then null
      when coalesce(v_assignment.secret_revealed, false) then jsonb_build_object(
        'revealed', true,
        'name', coalesce(nullif(v_secret_name, ''), '이름 확인 중'),
        'participantName', nullif(v_secret_roster_name, ''),
        'nickname', coalesce(v_secret.login_id::text, '')
      )
      else jsonb_build_object('revealed', false)
    end,
    'caughtByBuddy', coalesce(v_caught, false)
  ) || v_photos;
end;
$$;

create or replace function public.submit_mission_photo(
  p_login_id text,
  p_mission_type text,
  p_storage_path text,
  p_spot_index integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_mission_type text := lower(trim(coalesce(p_mission_type, '')));
  v_storage_path text := nullif(trim(coalesce(p_storage_path, '')), '');
  v_mission_key text;
  v_spot_index smallint;
  v_existing public.mission_photo_submissions%rowtype;
  v_assignment public.bbb_assignments%rowtype;
  v_has_care_buddy boolean := false;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  if v_storage_path is null then
    return jsonb_build_object('ok', false, 'error', 'missing_photo');
  end if;

  if v_mission_type in ('m1', 'bbb_m1') then
    v_mission_key := 'bbb_m1';
    if not (v_profile.is_dev or public.bu_bbb_section_open('m1')) then
      return jsonb_build_object('ok', false, 'error', 'not_open');
    end if;
  elsif v_mission_type in ('m2', 'bbb_m2') then
    v_mission_key := 'bbb_m2';
    if not (v_profile.is_dev or public.bu_bbb_section_open('m2')) then
      return jsonb_build_object('ok', false, 'error', 'not_open');
    end if;
  elsif v_mission_type like 'm3_%' or v_mission_type = 'pilgrim' then
    begin
      v_spot_index := coalesce(p_spot_index, split_part(v_mission_type, '_', 2)::integer)::smallint;
    exception when others then
      return jsonb_build_object('ok', false, 'error', 'invalid_spot');
    end;
    if v_spot_index < 0 or v_spot_index > 6 then
      return jsonb_build_object('ok', false, 'error', 'invalid_spot');
    end if;
    return jsonb_build_object('ok', false, 'error', 'qr_required') || public.bu_photo_payload(v_profile.id);
  else
    return jsonb_build_object('ok', false, 'error', 'invalid_mission_type');
  end if;

  select *
  into v_assignment
  from public.bbb_assignments
  where profile_id = v_profile.id;

  select (
    v_assignment.care_buddy_id is not null
    or exists (
      select 1
      from public.retreat_group_roster r
      where r.source_batch = '20260614'
        and r.matched_profile_id = v_profile.id
        and r.care_buddy_roster_id is not null
    )
  )
  into v_has_care_buddy;

  if not coalesce(v_has_care_buddy, false) then
    return jsonb_build_object('ok', false, 'error', 'no_match');
  end if;

  select *
  into v_existing
  from public.mission_photo_submissions
  where profile_id = v_profile.id
    and mission_key = v_mission_key
  order by updated_at desc
  limit 1
  for update;

  if v_existing.id is not null and v_existing.approval_status = 'approved' and v_existing.reward_event_id is not null then
    return jsonb_build_object('ok', false, 'error', 'approved_locked');
  end if;

  if v_existing.id is null then
    insert into public.mission_photo_submissions (
      profile_id,
      mission_key,
      storage_path,
      approval_status
    )
    values (
      v_profile.id,
      v_mission_key,
      v_storage_path,
      'pending'
    );
  else
    update public.mission_photo_submissions
    set storage_path = v_storage_path,
        approval_status = 'pending',
        approved_at = null,
        approved_by = null,
        rejected_at = null,
        rejected_by = null,
        rejection_reason = null,
        updated_at = now()
    where id = v_existing.id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'pendingApproval', true,
    'rewarded', false
  ) || public.bu_photo_payload(v_profile.id);
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
    'name', coalesce(u.name, ''),
    'displayName', coalesce(u.display_name, ''),
    'parish', coalesce(u.parish, ''),
    'careBuddy', jsonb_build_object(
      'userId', coalesce(care.login_id::text, care_roster_profile.login_id::text, ''),
      'name', coalesce(care.name, care_roster.participant_name, care.display_name, care.login_id::text, '')
    ),
    'secretBuddy', jsonb_build_object(
      'userId', coalesce(secret.login_id::text, secret_roster_profile.login_id::text, ''),
      'name', coalesce(secret.name, secret_roster.participant_name, secret.display_name, secret.login_id::text, '')
    ),
    'secretRevealed', coalesce(ba.secret_revealed, false),
    'tier', coalesce(ba.tier, roster.participation_tier, ''),
    'groupNo', coalesce(g.group_no, roster.group_no),
    'groupName', coalesce(g.name, roster.group_label, ''),
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

do $$
declare
  v_row record;
  v_event_id uuid;
  v_fixed integer := 0;
begin
  for v_row in
    select id, profile_id, mission_key
    from public.mission_photo_submissions
    where mission_key in ('bbb_m1', 'bbb_m2')
      and approval_status = 'approved'
      and reward_event_id is null
  loop
    v_event_id := public.bu_issue_special_pack_for_photo(v_row.profile_id, v_row.mission_key, null);

    update public.mission_photo_submissions
    set reward_event_id = v_event_id,
        updated_at = now()
    where id = v_row.id
      and reward_event_id is null;

    v_fixed := v_fixed + 1;
  end loop;

  raise notice 'B.B.B. approved photo reward backfill rows: %', v_fixed;
end $$;

do $$
begin
  perform public.bu_recalculate_hold_pray_guesses(null);
end $$;

revoke all on function public.bu_hp_answer_matches(text, text) from public, anon, authenticated;
revoke all on function public.bu_hold_pray_answer_matches(uuid, text) from public, anon, authenticated;
revoke all on function public.bu_issue_special_pack_for_photo(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.get_bbb_status(text) from public, anon, authenticated;
revoke all on function public.submit_mission_photo(text, text, text, integer) from public, anon, authenticated;
revoke all on function public.admin_bbb_pilgrim_status() from public, anon, authenticated;

grant execute on function public.get_bbb_status(text) to authenticated;
grant execute on function public.submit_mission_photo(text, text, text, integer) to authenticated;
grant execute on function public.admin_bbb_pilgrim_status() to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
