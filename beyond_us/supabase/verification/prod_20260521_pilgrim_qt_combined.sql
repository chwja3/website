-- PROD 2026-05-21 ???? 2?? ?? ?? ? BBB/???? ??? ?? RPC ?? ?? SQL
-- ?? ??: PROD Supabase SQL Editor
-- ?? ??:
-- - beyond_us/supabase/migrations/20260521000100_pilgrim_assignment_on_status_read.sql
-- - beyond_us/supabase/migrations/20260521000200_admin_bbb_pilgrim_status_restore.sql
-- Q.T. ???? SQL? ??? Supabase Storage beyond-us-photos/QT/YYMMDD.png? ?? ?????.

-- ============================================================================
-- BEGIN beyond_us/supabase/migrations/20260521000100_pilgrim_assignment_on_status_read.sql
-- ============================================================================
-- 천로역정 상태 조회 시 사용자별 2스팟 배정을 보장한다.

create or replace function public.bu_ensure_pilgrim_assignment(p_profile_id uuid)
returns smallint[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_spots smallint[];
begin
  select spot_indices
  into v_spots
  from public.pilgrim_assignments
  where profile_id = p_profile_id
  for update;

  if array_length(v_spots, 1) = 2 then
    return v_spots;
  end if;

  select array_agg(spot_index::smallint order by spot_index)
  into v_spots
  from (
    select spot_index
    from public.pilgrim_spots
    where enabled = true
    order by md5(p_profile_id::text || ':' || spot_index::text)
    limit 2
  ) selected_spots;

  if array_length(v_spots, 1) <> 2 then
    raise exception 'not_enough_pilgrim_spots';
  end if;

  insert into public.pilgrim_assignments (profile_id, spot_indices)
  values (p_profile_id, v_spots)
  on conflict (profile_id) do nothing;

  select spot_indices
  into v_spots
  from public.pilgrim_assignments
  where profile_id = p_profile_id;

  return v_spots;
end;
$$;

create or replace function public.bu_photo_payload(p_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m1 public.mission_photo_submissions%rowtype;
  v_m2 public.mission_photo_submissions%rowtype;
  v_m3 jsonb := '[]'::jsonb;
  v_spots smallint[];
  v_rewarded boolean := false;
begin
  select *
  into v_m1
  from public.mission_photo_submissions
  where profile_id = p_profile_id
    and mission_key = 'bbb_m1'
  order by updated_at desc
  limit 1;

  select *
  into v_m2
  from public.mission_photo_submissions
  where profile_id = p_profile_id
    and mission_key = 'bbb_m2'
  order by updated_at desc
  limit 1;

  select coalesce(jsonb_agg(s.storage_path order by gs.idx), '[]'::jsonb)
  into v_m3
  from generate_series(0, 6) as gs(idx)
  left join lateral (
    select storage_path
    from public.mission_photo_submissions
    where profile_id = p_profile_id
      and mission_key = 'pilgrim'
      and spot_index = gs.idx
      and approval_status <> 'rejected'
    order by updated_at desc
    limit 1
  ) s on true;

  v_spots := public.bu_ensure_pilgrim_assignment(p_profile_id);

  select reward_event_id is not null
  into v_rewarded
  from public.pilgrim_assignments
  where profile_id = p_profile_id;

  return jsonb_build_object(
    'myPhoto', v_m1.storage_path,
    'm1ApprovalStatus', coalesce(v_m1.approval_status::text, ''),
    'm1Rewarded', v_m1.reward_event_id is not null,
    'myPhotoM2', v_m2.storage_path,
    'm2ApprovalStatus', coalesce(v_m2.approval_status::text, ''),
    'm2Rewarded', v_m2.reward_event_id is not null,
    'myPhotoM3', coalesce(v_m3, '[]'::jsonb),
    'm3AssignedSpots', coalesce(to_jsonb(v_spots), '[]'::jsonb),
    'm3Rewarded', coalesce(v_rewarded, false)
  );
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
  v_spots smallint[];
  v_completed integer := 0;
  v_required integer := 2;
  v_rewarded boolean := false;
  v_reward_event_id uuid;
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
    v_mission_key := 'pilgrim';
    if not (v_profile.is_dev or public.bu_bbb_section_open('m3')) then
      return jsonb_build_object('ok', false, 'error', 'not_open');
    end if;
    begin
      v_spot_index := coalesce(p_spot_index, split_part(v_mission_type, '_', 2)::integer)::smallint;
    exception when others then
      return jsonb_build_object('ok', false, 'error', 'invalid_spot');
    end;
    if v_spot_index < 0 or v_spot_index > 6 then
      return jsonb_build_object('ok', false, 'error', 'invalid_spot');
    end if;
  else
    return jsonb_build_object('ok', false, 'error', 'invalid_mission_type');
  end if;

  if v_mission_key in ('bbb_m1', 'bbb_m2') then
    select *
    into v_assignment
    from public.bbb_assignments
    where profile_id = v_profile.id;

    if v_assignment.profile_id is null or v_assignment.care_buddy_id is null then
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
  end if;

  v_spots := public.bu_ensure_pilgrim_assignment(v_profile.id);

  if not (v_spot_index = any(v_spots)) then
    return jsonb_build_object('ok', false, 'error', 'not_assigned_spot');
  end if;

  select *
  into v_existing
  from public.mission_photo_submissions
  where profile_id = v_profile.id
    and mission_key = 'pilgrim'
    and spot_index = v_spot_index
  order by updated_at desc
  limit 1
  for update;

  if v_existing.id is null then
    insert into public.mission_photo_submissions (
      profile_id,
      mission_key,
      spot_index,
      storage_path,
      approval_status,
      approved_at
    )
    values (
      v_profile.id,
      'pilgrim',
      v_spot_index,
      v_storage_path,
      'approved',
      now()
    );
  else
    update public.mission_photo_submissions
    set storage_path = v_storage_path,
        approval_status = 'approved',
        approved_at = now(),
        rejected_at = null,
        rejected_by = null,
        rejection_reason = null,
        updated_at = now()
    where id = v_existing.id;
  end if;

  select count(distinct spot_index)::integer
  into v_completed
  from public.mission_photo_submissions
  where profile_id = v_profile.id
    and mission_key = 'pilgrim'
    and approval_status = 'approved'
    and spot_index = any(v_spots);

  v_required := coalesce(array_length(v_spots, 1), 2);

  if v_completed >= v_required then
    select reward_event_id
    into v_reward_event_id
    from public.pilgrim_assignments
    where profile_id = v_profile.id
    for update;

    if v_reward_event_id is null then
      if exists(select 1 from public.cards where id = 10) then
        insert into public.user_cards (
          profile_id,
          card_id,
          quantity,
          first_obtained_at
        )
        values (
          v_profile.id,
          10,
          1,
          now()
        )
        on conflict (profile_id, card_id) do update
        set quantity = public.user_cards.quantity + 1,
            first_obtained_at = coalesce(public.user_cards.first_obtained_at, now()),
            updated_at = now();
      end if;

      insert into public.events (
        profile_id,
        event_type,
        ref_type,
        ref_id,
        amount,
        payload,
        source
      )
      values (
        v_profile.id,
        'card.granted',
        'pilgrim',
        '10',
        1,
        jsonb_build_object('reason', 'pilgrim_completed', 'spots', to_jsonb(v_spots)),
        'web'
      )
      returning id into v_reward_event_id;

      update public.pilgrim_assignments
      set completed_at = coalesce(completed_at, now()),
          reward_event_id = v_reward_event_id
      where profile_id = v_profile.id;

      v_rewarded := true;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'pendingApproval', false,
    'rewarded', v_rewarded
  ) || public.bu_photo_payload(v_profile.id);
end;
$$;
-- ============================================================================
-- END beyond_us/supabase/migrations/20260521000100_pilgrim_assignment_on_status_read.sql
-- ============================================================================

-- ============================================================================
-- BEGIN beyond_us/supabase/migrations/20260521000200_admin_bbb_pilgrim_status_restore.sql
-- ============================================================================
-- BBB/천로역정 운영 현황 RPC를 재생성하고 스키마 캐시 갱신을 요청한다.

begin;

create or replace function public.bu_ensure_pilgrim_assignment(p_profile_id uuid)
returns smallint[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_spots smallint[];
begin
  select spot_indices
  into v_spots
  from public.pilgrim_assignments
  where profile_id = p_profile_id
  for update;

  if array_length(v_spots, 1) = 2 then
    return v_spots;
  end if;

  select array_agg(spot_index::smallint order by spot_index)
  into v_spots
  from (
    select spot_index
    from public.pilgrim_spots
    where enabled = true
    order by md5(p_profile_id::text || ':' || spot_index::text)
    limit 2
  ) selected_spots;

  if array_length(v_spots, 1) <> 2 then
    raise exception 'not_enough_pilgrim_spots';
  end if;

  insert into public.pilgrim_assignments (profile_id, spot_indices)
  values (p_profile_id, v_spots)
  on conflict (profile_id) do nothing;

  select spot_indices
  into v_spots
  from public.pilgrim_assignments
  where profile_id = p_profile_id;

  return v_spots;
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
      'userId', care.login_id,
      'name', coalesce(care.name, care.display_name, care.login_id::text, '')
    ),
    'secretBuddy', jsonb_build_object(
      'userId', secret.login_id,
      'name', coalesce(secret.name, secret.display_name, secret.login_id::text, '')
    ),
    'secretRevealed', coalesce(ba.secret_revealed, false),
    'tier', coalesce(ba.tier, ''),
    'groupNo', g.group_no,
    'groupName', coalesce(g.name, ''),
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
  left join public.bbb_assignments ba on ba.profile_id = u.id
  left join public.profiles care on care.id = ba.care_buddy_id
  left join public.profiles secret on secret.id = ba.secret_buddy_id
  left join public.groups g on g.id = ba.group_id
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

revoke all on function public.admin_bbb_pilgrim_status() from public, anon, authenticated;
grant execute on function public.admin_bbb_pilgrim_status() to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
-- ============================================================================
-- END beyond_us/supabase/migrations/20260521000200_admin_bbb_pilgrim_status_restore.sql
-- ============================================================================
