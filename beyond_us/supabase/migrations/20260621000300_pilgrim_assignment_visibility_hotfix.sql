-- 천로역정 상태 조회 시 유저별 랜덤 2스팟 배정을 보장한다.
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
  if p_profile_id is null then
    return array[]::smallint[];
  end if;

  select spot_indices
  into v_spots
  from public.pilgrim_assignments
  where profile_id = p_profile_id
  for update;

  if coalesce(array_length(v_spots, 1), 0) = 2 then
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

  if coalesce(array_length(v_spots, 1), 0) <> 2 then
    raise exception 'not_enough_pilgrim_spots';
  end if;

  insert into public.pilgrim_assignments (profile_id, spot_indices)
  values (p_profile_id, v_spots)
  on conflict (profile_id) do nothing;

  select spot_indices
  into v_spots
  from public.pilgrim_assignments
  where profile_id = p_profile_id;

  return coalesce(v_spots, array[]::smallint[]);
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
  v_m3_statuses jsonb := '[]'::jsonb;
  v_spots_array smallint[] := array[]::smallint[];
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

  v_spots_array := public.bu_ensure_pilgrim_assignment(p_profile_id);

  select
    coalesce(jsonb_agg(s.storage_path order by gs.idx), '[]'::jsonb),
    coalesce(jsonb_agg(coalesce(s.approval_status::text, '') order by gs.idx), '[]'::jsonb)
  into v_m3, v_m3_statuses
  from generate_series(0, 6) as gs(idx)
  left join lateral (
    select storage_path, approval_status
    from public.mission_photo_submissions
    where profile_id = p_profile_id
      and mission_key = 'pilgrim'
      and spot_index = gs.idx
      and approval_status <> 'rejected'
    order by updated_at desc
    limit 1
  ) s on true;

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
    'myPhotoM3Statuses', coalesce(v_m3_statuses, '[]'::jsonb),
    'm3AssignedSpots', coalesce(to_jsonb(v_spots_array), '[]'::jsonb),
    'm3Rewarded', coalesce(v_rewarded, false)
  );
end;
$$;

do $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    select id
    from public.profiles
    where account_status = 'active'
  loop
    perform public.bu_ensure_pilgrim_assignment(v_row.id);
    v_count := v_count + 1;
  end loop;

  raise notice 'Pilgrim assignments ensured for active users: %', v_count;
end $$;

revoke all on function public.bu_ensure_pilgrim_assignment(uuid) from public, anon, authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
