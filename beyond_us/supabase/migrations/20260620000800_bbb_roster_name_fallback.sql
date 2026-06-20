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
