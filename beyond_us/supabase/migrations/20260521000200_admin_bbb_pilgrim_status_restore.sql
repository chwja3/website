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
