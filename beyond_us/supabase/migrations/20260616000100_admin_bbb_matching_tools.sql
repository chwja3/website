-- BBB 매칭을 admin에서 조회하고 저장하는 RPC를 추가한다.

create or replace function public.admin_get_bbb_matching_matrix()
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

  select coalesce(jsonb_agg(jsonb_build_object(
    'profileId', u.id,
    'loginId', u.login_id,
    'userId', u.login_id,
    'name', coalesce(u.name, ''),
    'displayName', coalesce(u.display_name, ''),
    'participantCode', coalesce(u.participant_code, ''),
    'parish', coalesce(u.parish, ''),
    'groupId', g.id,
    'groupNo', g.group_no,
    'groupName', coalesce(g.name, ''),
    'groupTier', coalesce(g.tier, ''),
    'groupRole', coalesce(gm.group_role::text, ''),
    'participationTier', coalesce(ra.participation_tier, ''),
    'attendanceStatus', coalesce(ra.attendance_status::text, ''),
    'careBuddyId', ba.care_buddy_id,
    'careBuddyLoginId', care.login_id,
    'careBuddyName', coalesce(care.name, ''),
    'careBuddyDisplayName', coalesce(care.display_name, ''),
    'secretBuddyId', ba.secret_buddy_id,
    'secretBuddyLoginId', secret.login_id,
    'secretBuddyName', coalesce(secret.name, ''),
    'secretBuddyDisplayName', coalesce(secret.display_name, ''),
    'updatedAt', ba.updated_at
  ) order by
    case when g.group_no is null then 9999 else g.group_no end,
    case coalesce(gm.group_role::text, '')
      when 'leader' then 0
      when 'assistant' then 1
      else 2
    end,
    u.name,
    u.login_id::text), '[]'::jsonb)
  into v_rows
  from public.profiles u
  left join public.group_members gm on gm.profile_id = u.id
  left join public.groups g on g.id = gm.group_id
  left join public.retreat_attendance ra on ra.profile_id = u.id
  left join public.bbb_assignments ba on ba.profile_id = u.id
  left join public.profiles care on care.id = ba.care_buddy_id
  left join public.profiles secret on secret.id = ba.secret_buddy_id
  where u.account_status = 'active';

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
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

  select gm.group_id, coalesce(g.tier, ra.participation_tier)
  into v_profile_group_id, v_profile_tier
  from public.profiles p
  left join public.group_members gm on gm.profile_id = p.id
  left join public.groups g on g.id = gm.group_id
  left join public.retreat_attendance ra on ra.profile_id = p.id
  where p.id = p_profile_id;

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
    v_profile_tier,
    now()
  )
  on conflict (profile_id) do update
  set care_buddy_id = excluded.care_buddy_id,
      group_id = coalesce(excluded.group_id, public.bbb_assignments.group_id),
      tier = coalesce(excluded.tier, public.bbb_assignments.tier),
      updated_at = now();

  if p_care_buddy_id is not null then
    select gm.group_id, coalesce(g.tier, ra.participation_tier)
    into v_care_group_id, v_care_tier
    from public.profiles p
    left join public.group_members gm on gm.profile_id = p.id
    left join public.groups g on g.id = gm.group_id
    left join public.retreat_attendance ra on ra.profile_id = p.id
    where p.id = p_care_buddy_id;

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
      v_care_tier,
      now()
    )
    on conflict (profile_id) do update
    set secret_buddy_id = excluded.secret_buddy_id,
        group_id = coalesce(excluded.group_id, public.bbb_assignments.group_id),
        tier = coalesce(excluded.tier, public.bbb_assignments.tier),
        updated_at = now();
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'profileId', p_profile_id,
    'careBuddyId', p_care_buddy_id,
    'oldCareBuddyId', v_old_care_buddy_id
  );
end;
$$;

revoke all on function public.admin_set_bbb_care_buddy(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_set_bbb_care_buddy(uuid, uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
