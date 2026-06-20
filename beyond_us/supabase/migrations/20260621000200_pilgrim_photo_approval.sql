-- 천로역정 인증을 QR 즉시 완료에서 사진 업로드 후 관리자 승인 방식으로 전환한다.
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
  v_spots jsonb := '[]'::jsonb;
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

  select coalesce(to_jsonb(spot_indices), '[]'::jsonb),
         reward_event_id is not null
  into v_spots, v_rewarded
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
    'm3AssignedSpots', coalesce(v_spots, '[]'::jsonb),
    'm3Rewarded', coalesce(v_rewarded, false)
  );
end;
$$;

create or replace function public.bu_issue_pilgrim_completion_reward(
  p_profile_id uuid,
  p_admin_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_spots smallint[];
  v_required integer := 2;
  v_completed integer := 0;
  v_reward_event_id uuid;
begin
  if p_profile_id is null then
    return null;
  end if;

  perform pg_advisory_xact_lock(hashtext('pilgrim_reward:' || p_profile_id::text));

  v_spots := public.bu_ensure_pilgrim_assignment(p_profile_id);
  v_required := coalesce(array_length(v_spots, 1), 2);

  select count(distinct spot_index)::integer
  into v_completed
  from public.mission_photo_submissions
  where profile_id = p_profile_id
    and mission_key = 'pilgrim'
    and approval_status = 'approved'
    and spot_index = any(v_spots);

  if v_completed < v_required then
    return null;
  end if;

  select reward_event_id
  into v_reward_event_id
  from public.pilgrim_assignments
  where profile_id = p_profile_id
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
        p_profile_id,
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
      source,
      created_by
    )
    values (
      p_profile_id,
      'card.granted',
      'pilgrim',
      '10',
      1,
      jsonb_build_object('reason', 'pilgrim_completed', 'spots', to_jsonb(v_spots)),
      'admin',
      p_admin_id
    )
    returning id into v_reward_event_id;

    update public.pilgrim_assignments
    set completed_at = coalesce(completed_at, now()),
        reward_event_id = v_reward_event_id
    where profile_id = p_profile_id;

    perform public.bu_refresh_profile_summary(p_profile_id);
  end if;

  return v_reward_event_id;
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
  v_spots smallint[];
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

    if v_existing.id is not null and v_existing.approval_status = 'approved' then
      return jsonb_build_object('ok', false, 'error', 'approved_locked') || public.bu_photo_payload(v_profile.id);
    end if;

    if v_existing.id is null then
      insert into public.mission_photo_submissions (
        profile_id,
        mission_key,
        spot_index,
        storage_path,
        approval_status
      )
      values (
        v_profile.id,
        'pilgrim',
        v_spot_index,
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
          reward_event_id = null,
          updated_at = now()
      where id = v_existing.id;
    end if;

    return jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'pendingApproval', true,
      'rewarded', false
    ) || public.bu_photo_payload(v_profile.id);
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

create or replace function public.verify_pilgrim_qr(
  p_login_id text,
  p_spot_index integer,
  p_qr_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  return jsonb_build_object(
    'ok', false,
    'error', 'photo_required',
    'source', 'supabase'
  ) || public.bu_photo_payload(v_profile.id);
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
    return jsonb_build_object('ok', false, 'error', 'photo_not_found');
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
        approved_at = now(),
        approved_by = v_admin.id,
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
    'rewardEventId', v_event_id
  ) || public.bu_photo_payload(v_profile.id);
end;
$$;

revoke all on function public.bu_issue_pilgrim_completion_reward(uuid, uuid) from public, anon, authenticated;
revoke all on function public.submit_mission_photo(text, text, text, integer) from public, anon, authenticated;
revoke all on function public.verify_pilgrim_qr(text, integer, text) from public, anon, authenticated;
revoke all on function public.admin_review_mission_photo(text, text, text) from public, anon, authenticated;

grant execute on function public.submit_mission_photo(text, text, text, integer) to authenticated;
grant execute on function public.verify_pilgrim_qr(text, integer, text) to authenticated;
grant execute on function public.admin_review_mission_photo(text, text, text) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
