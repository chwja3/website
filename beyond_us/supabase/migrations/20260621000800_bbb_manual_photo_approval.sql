-- BBB Mission 1, 2를 사진 없이도 운영자가 수동 성공 처리할 수 있게 한다.
begin;

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
    'myPhoto', case when coalesce(v_m1.storage_path, '') like 'admin_manual://%' then null else v_m1.storage_path end,
    'm1ApprovalStatus', coalesce(v_m1.approval_status::text, ''),
    'm1Rewarded', v_m1.reward_event_id is not null,
    'myPhotoM2', case when coalesce(v_m2.storage_path, '') like 'admin_manual://%' then null else v_m2.storage_path end,
    'm2ApprovalStatus', coalesce(v_m2.approval_status::text, ''),
    'm2Rewarded', v_m2.reward_event_id is not null,
    'myPhotoM3', coalesce(v_m3, '[]'::jsonb),
    'myPhotoM3Statuses', coalesce(v_m3_statuses, '[]'::jsonb),
    'm3AssignedSpots', coalesce(to_jsonb(v_spots_array), '[]'::jsonb),
    'm3Rewarded', coalesce(v_rewarded, false)
  );
end;
$$;

create or replace function public.admin_review_mission_photo(
  p_login_id text,
  p_mission_type text,
  p_decision text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_mission_type text := lower(trim(coalesce(p_mission_type, '')));
  v_decision text := lower(trim(coalesce(p_decision, '')));
  v_mission_key text;
  v_spot_index smallint;
  v_submission public.mission_photo_submissions%rowtype;
  v_spots smallint[];
  v_event_id uuid;
  v_before_reward_id uuid;
  v_rewarded boolean := false;
begin
  v_admin := public.bu_admin_profile();

  select *
  into v_profile
  from public.profiles
  where login_id = p_login_id
    and account_status = 'active'
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'error', 'user_not_found');
  end if;

  if v_decision not in ('approve', 'reject') then
    return jsonb_build_object('ok', false, 'error', 'invalid_decision');
  end if;

  if v_mission_type in ('m1', 'bbb_m1') then
    v_mission_key := 'bbb_m1';
  elsif v_mission_type in ('m2', 'bbb_m2') then
    v_mission_key := 'bbb_m2';
  elsif v_mission_type like 'm3_%' or v_mission_type = 'pilgrim' then
    v_mission_key := 'pilgrim';
    begin
      v_spot_index := split_part(v_mission_type, '_', 2)::integer::smallint;
    exception when others then
      return jsonb_build_object('ok', false, 'error', 'invalid_spot');
    end;
    if v_spot_index < 0 or v_spot_index > 6 then
      return jsonb_build_object('ok', false, 'error', 'invalid_spot');
    end if;
    v_spots := public.bu_ensure_pilgrim_assignment(v_profile.id);
    if not (v_spot_index = any(v_spots)) then
      return jsonb_build_object('ok', false, 'error', 'not_assigned_spot');
    end if;
  else
    return jsonb_build_object('ok', false, 'error', 'invalid_mission_type');
  end if;

  select *
  into v_submission
  from public.mission_photo_submissions
  where profile_id = v_profile.id
    and mission_key = v_mission_key
    and (v_mission_key <> 'pilgrim' or spot_index = v_spot_index)
  order by updated_at desc
  limit 1
  for update;

  if v_submission.id is null then
    if v_decision = 'approve' and v_mission_key in ('bbb_m1', 'bbb_m2') then
      insert into public.mission_photo_submissions (
        profile_id,
        mission_key,
        storage_path,
        approval_status,
        approved_at,
        approved_by,
        created_at,
        updated_at
      )
      values (
        v_profile.id,
        v_mission_key,
        'admin_manual://' || v_mission_key || '/' || v_profile.login_id,
        'approved',
        now(),
        v_admin.id,
        now(),
        now()
      )
      returning * into v_submission;
    else
      return jsonb_build_object('ok', false, 'error', 'photo_not_found');
    end if;
  end if;

  if v_decision = 'reject' then
    if v_submission.approval_status = 'approved' and v_submission.reward_event_id is not null then
      return jsonb_build_object('ok', false, 'error', 'approved_locked');
    end if;

    update public.mission_photo_submissions
    set approval_status = 'rejected',
        rejected_at = now(),
        rejected_by = v_admin.id,
        rejection_reason = 'admin_rejected',
        updated_at = now()
    where id = v_submission.id;

    return jsonb_build_object('ok', true, 'source', 'supabase', 'rejected', true) || public.bu_photo_payload(v_profile.id);
  end if;

  if v_mission_key in ('bbb_m1', 'bbb_m2') then
    if v_submission.reward_event_id is null then
      v_event_id := public.bu_issue_special_pack_for_photo(v_profile.id, v_submission.mission_key, v_admin.id);
      v_rewarded := true;
    else
      v_event_id := v_submission.reward_event_id;
    end if;

    update public.mission_photo_submissions
    set approval_status = 'approved',
        approved_at = coalesce(approved_at, now()),
        approved_by = coalesce(approved_by, v_admin.id),
        rejected_at = null,
        rejected_by = null,
        rejection_reason = null,
        reward_event_id = v_event_id,
        updated_at = now()
    where id = v_submission.id;
  else
    select reward_event_id
    into v_before_reward_id
    from public.pilgrim_assignments
    where profile_id = v_profile.id;

    update public.mission_photo_submissions
    set approval_status = 'approved',
        approved_at = now(),
        approved_by = v_admin.id,
        rejected_at = null,
        rejected_by = null,
        rejection_reason = null,
        updated_at = now()
    where id = v_submission.id;

    v_event_id := public.bu_issue_pilgrim_completion_reward(v_profile.id, v_admin.id);
    v_rewarded := v_before_reward_id is null and v_event_id is not null;

    if v_event_id is not null then
      update public.mission_photo_submissions
      set reward_event_id = coalesce(reward_event_id, v_event_id),
          updated_at = now()
      where profile_id = v_profile.id
        and mission_key = 'pilgrim'
        and approval_status = 'approved'
        and spot_index = any(public.bu_ensure_pilgrim_assignment(v_profile.id));
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'rewarded', v_rewarded,
    'rewardEventId', v_event_id,
    'manual', coalesce(v_submission.storage_path, '') like 'admin_manual://%'
  ) || public.bu_photo_payload(v_profile.id);
end;
$$;

revoke all on function public.bu_photo_payload(uuid) from public, anon, authenticated;
revoke all on function public.admin_review_mission_photo(text, text, text) from public, anon, authenticated;
grant execute on function public.bu_photo_payload(uuid) to authenticated;
grant execute on function public.admin_review_mission_photo(text, text, text) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
