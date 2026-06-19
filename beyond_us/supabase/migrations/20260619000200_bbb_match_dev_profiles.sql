-- B.B.B. 조 명단 매칭에서 실제 조원인 개발자/테스트 계정을 허용한다.
begin;

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
    group by r.id
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
          when c.same_parish_count > 1 then '이름 중복 확인필요 - 같은 청'
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
  select
    r.group_id,
    r.matched_profile_id,
    r.group_role,
    now()
  from public.retreat_group_roster r
  where r.source_batch = p_source_batch
    and r.group_id is not null
    and r.matched_profile_id is not null
  on conflict (profile_id) do update
  set group_id = excluded.group_id,
      group_role = excluded.group_role,
      assigned_at = now();

  get diagnostics v_group_members = row_count;

  insert into public.bbb_assignments (
    profile_id,
    care_buddy_id,
    group_id,
    tier,
    updated_at
  )
  select
    r.matched_profile_id,
    care.matched_profile_id,
    r.group_id,
    coalesce(r.participation_tier, '전참'),
    now()
  from public.retreat_group_roster r
  join public.retreat_group_roster care
    on care.id = r.care_buddy_roster_id
  where r.source_batch = p_source_batch
    and r.matched_profile_id is not null
    and care.matched_profile_id is not null
  on conflict (profile_id) do update
  set care_buddy_id = excluded.care_buddy_id,
      group_id = excluded.group_id,
      tier = excluded.tier,
      updated_at = now();

  get diagnostics v_assignments = row_count;

  insert into public.bbb_assignments (
    profile_id,
    secret_buddy_id,
    group_id,
    tier,
    updated_at
  )
  select
    secret.matched_profile_id,
    r.matched_profile_id,
    secret.group_id,
    coalesce(secret.participation_tier, '전참'),
    now()
  from public.retreat_group_roster r
  join public.retreat_group_roster secret
    on secret.id = r.care_buddy_roster_id
  where r.source_batch = p_source_batch
    and r.matched_profile_id is not null
    and secret.matched_profile_id is not null
  on conflict (profile_id) do update
  set secret_buddy_id = excluded.secret_buddy_id,
      group_id = excluded.group_id,
      tier = excluded.tier,
      updated_at = now();

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'sourceBatch', p_source_batch,
    'matchedRowsTouched', v_matched,
    'groupMembersTouched', v_group_members,
    'assignmentsTouched', v_assignments,
    'devProfilesAllowed', true
  );
end;
$$;

revoke all on function public.bu_sync_group_roster_profile_matches(text) from public, anon, authenticated;
grant execute on function public.bu_sync_group_roster_profile_matches(text) to authenticated;

create or replace function public.admin_resolve_group_roster_profile(
  p_roster_id uuid,
  p_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_roster public.retreat_group_roster%rowtype;
  v_profile public.profiles%rowtype;
  v_existing_roster_id uuid;
begin
  v_admin := public.bu_admin_profile();

  select *
  into v_roster
  from public.retreat_group_roster
  where id = p_roster_id;

  if v_roster.id is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'roster_not_found');
  end if;

  select *
  into v_profile
  from public.profiles
  where id = p_profile_id
    and account_status = 'active';

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'profile_not_found');
  end if;

  if public.bu_group_roster_normalize_name(v_profile.name) is distinct from v_roster.name_norm then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'name_mismatch');
  end if;

  select r.id
  into v_existing_roster_id
  from public.retreat_group_roster r
  where r.source_batch = v_roster.source_batch
    and r.matched_profile_id = p_profile_id
    and r.id <> p_roster_id
  order by r.roster_order
  limit 1;

  if v_existing_roster_id is not null then
    return jsonb_build_object(
      'ok', false,
      'source', 'supabase',
      'error', 'profile_already_matched',
      'existingRosterId', v_existing_roster_id
    );
  end if;

  update public.retreat_group_roster
  set matched_profile_id = p_profile_id,
      match_status = 'matched_manual',
      match_detail = '관리자 수동 매칭',
      updated_at = now()
  where id = p_roster_id;

  if v_roster.group_id is not null then
    insert into public.group_members (
      group_id,
      profile_id,
      group_role,
      assigned_at
    )
    values (
      v_roster.group_id,
      p_profile_id,
      v_roster.group_role,
      now()
    )
    on conflict (profile_id) do update
    set group_id = excluded.group_id,
        group_role = excluded.group_role,
        assigned_at = now();
  end if;

  perform public.bu_sync_group_roster_profile_matches(v_roster.source_batch);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'rosterId', p_roster_id,
    'profileId', p_profile_id,
    'matchStatus', 'matched_manual'
  );
end;
$$;

revoke all on function public.admin_resolve_group_roster_profile(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_resolve_group_roster_profile(uuid, uuid) to authenticated;

select public.bu_sync_group_roster_profile_matches('20260614');

select pg_notify('pgrst', 'reload schema');

commit;
