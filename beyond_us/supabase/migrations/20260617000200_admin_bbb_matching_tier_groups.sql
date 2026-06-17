-- BBB 매칭을 조별, 참여구분별로 제한하는 admin RPC를 갱신한다.

create or replace function public.bu_bbb_matching_tier(
  p_participation_tier text,
  p_attendance_status public.attendance_status default null
)
returns text
language sql
stable
as $$
  select case
    when regexp_replace(lower(coalesce(p_participation_tier, '')), '\s+', '', 'g') ~ '(전참|전체|전일|금토일|full|all)' then '전참'
    when regexp_replace(lower(coalesce(p_participation_tier, '')), '\s+', '', 'g') ~ '(토참|토요일|토|sat|saturday)' then '토참'
    when regexp_replace(lower(coalesce(p_participation_tier, '')), '\s+', '', 'g') ~ '(일참|일요일|일|sun|sunday)' then '일참'
    else '전참'
  end;
$$;

revoke all on function public.bu_bbb_matching_tier(text, public.attendance_status) from public, anon, authenticated;
grant execute on function public.bu_bbb_matching_tier(text, public.attendance_status) to authenticated;

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
    'participationTier', coalesce(nullif(ra.participation_tier, ''), public.bu_bbb_matching_tier(ra.participation_tier, ra.attendance_status)),
    'matchingTier', public.bu_bbb_matching_tier(ra.participation_tier, ra.attendance_status),
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
    case public.bu_bbb_matching_tier(ra.participation_tier, ra.attendance_status)
      when '전참' then 0
      when '토참' then 1
      when '일참' then 2
      else 9
    end,
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

  select gm.group_id, public.bu_bbb_matching_tier(ra.participation_tier, ra.attendance_status)
  into v_profile_group_id, v_profile_tier
  from public.profiles p
  left join public.group_members gm on gm.profile_id = p.id
  left join public.retreat_attendance ra on ra.profile_id = p.id
  where p.id = p_profile_id;

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

    select gm.group_id, public.bu_bbb_matching_tier(ra.participation_tier, ra.attendance_status)
    into v_care_group_id, v_care_tier
    from public.profiles p
    left join public.group_members gm on gm.profile_id = p.id
    left join public.retreat_attendance ra on ra.profile_id = p.id
    where p.id = p_care_buddy_id;

    if v_profile_group_id is distinct from v_care_group_id then
      return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'different_group_not_allowed');
    end if;

    if coalesce(v_profile_tier, '전참') is distinct from coalesce(v_care_tier, '전참') then
      return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'different_tier_not_allowed');
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
    coalesce(v_profile_tier, '전참'),
    now()
  )
  on conflict (profile_id) do update
  set care_buddy_id = excluded.care_buddy_id,
      group_id = excluded.group_id,
      tier = excluded.tier,
      updated_at = now();

  if p_care_buddy_id is not null then
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
      coalesce(v_care_tier, '전참'),
      now()
    )
    on conflict (profile_id) do update
    set secret_buddy_id = excluded.secret_buddy_id,
        group_id = excluded.group_id,
        tier = excluded.tier,
        updated_at = now();
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'profileId', p_profile_id,
    'careBuddyId', p_care_buddy_id,
    'oldCareBuddyId', v_old_care_buddy_id,
    'matchingTier', coalesce(v_profile_tier, '전참')
  );
end;
$$;

revoke all on function public.admin_set_bbb_care_buddy(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_set_bbb_care_buddy(uuid, uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
