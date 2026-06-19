-- 숙소와 차량 배정표에서 동명이인 후보를 관리자가 직접 확정할 수 있게 한다.
begin;

alter table public.retreat_logistics_assignments
add column if not exists source_batch text not null default 'manual';

alter table public.retreat_logistics_assignments
add column if not exists match_status text not null default 'manual';

alter table public.retreat_logistics_assignments
add column if not exists match_detail text not null default '';

alter table public.retreat_logistics_assignments
add column if not exists candidate_profiles jsonb not null default '[]'::jsonb;

create or replace function public.admin_get_logistics_assignments(
  p_search text default '',
  p_limit integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_query text := lower(trim(coalesce(p_search, '')));
  v_limit integer := greatest(1, least(coalesce(p_limit, 300), 1000));
  v_total integer := 0;
  v_missing_profile_count integer := 0;
  v_duplicate_count integer := 0;
  v_rows jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  with base as (
    select
      a.*,
      p.login_id as matched_login_id,
      p.name as matched_name,
      p.parish as matched_parish
    from public.retreat_logistics_assignments a
    left join public.profiles p on p.id = a.profile_id
  ),
  filtered as (
    select *
    from base
    where v_query = ''
       or lower(coalesce(login_id, '')) like '%' || v_query || '%'
       or lower(coalesce(matched_login_id::text, '')) like '%' || v_query || '%'
       or lower(coalesce(name, '')) like '%' || v_query || '%'
       or lower(coalesce(matched_name, '')) like '%' || v_query || '%'
       or lower(coalesce(parish, '')) like '%' || v_query || '%'
       or lower(coalesce(matched_parish, '')) like '%' || v_query || '%'
       or lower(coalesce(group_name, '')) like '%' || v_query || '%'
       or lower(coalesce(lodging_building, '')) like '%' || v_query || '%'
       or lower(coalesce(lodging_room, '')) like '%' || v_query || '%'
       or lower(coalesce(vehicle_group, '')) like '%' || v_query || '%'
       or lower(coalesce(vehicle_route, '')) like '%' || v_query || '%'
       or lower(coalesce(vehicle_no, '')) like '%' || v_query || '%'
       or lower(coalesce(raw_note, '')) like '%' || v_query || '%'
       or lower(coalesce(match_status, '')) like '%' || v_query || '%'
       or lower(coalesce(match_detail, '')) like '%' || v_query || '%'
       or lower(coalesce(candidate_profiles::text, '')) like '%' || v_query || '%'
  )
  select count(*),
         count(*) filter (where profile_id is null),
         count(*) filter (where match_status = 'duplicate_needs_check')
  into v_total, v_missing_profile_count, v_duplicate_count
  from filtered;

  with base as (
    select
      a.*,
      p.login_id as matched_login_id,
      p.name as matched_name,
      p.parish as matched_parish
    from public.retreat_logistics_assignments a
    left join public.profiles p on p.id = a.profile_id
  ),
  filtered as (
    select *
    from base
    where v_query = ''
       or lower(coalesce(login_id, '')) like '%' || v_query || '%'
       or lower(coalesce(matched_login_id::text, '')) like '%' || v_query || '%'
       or lower(coalesce(name, '')) like '%' || v_query || '%'
       or lower(coalesce(matched_name, '')) like '%' || v_query || '%'
       or lower(coalesce(parish, '')) like '%' || v_query || '%'
       or lower(coalesce(matched_parish, '')) like '%' || v_query || '%'
       or lower(coalesce(group_name, '')) like '%' || v_query || '%'
       or lower(coalesce(lodging_building, '')) like '%' || v_query || '%'
       or lower(coalesce(lodging_room, '')) like '%' || v_query || '%'
       or lower(coalesce(vehicle_group, '')) like '%' || v_query || '%'
       or lower(coalesce(vehicle_route, '')) like '%' || v_query || '%'
       or lower(coalesce(vehicle_no, '')) like '%' || v_query || '%'
       or lower(coalesce(raw_note, '')) like '%' || v_query || '%'
       or lower(coalesce(match_status, '')) like '%' || v_query || '%'
       or lower(coalesce(match_detail, '')) like '%' || v_query || '%'
       or lower(coalesce(candidate_profiles::text, '')) like '%' || v_query || '%'
  ),
  limited as (
    select *
    from filtered
    order by
      case
        when match_status = 'duplicate_needs_check' then 0
        when profile_id is null then 1
        else 2
      end,
      sort_order,
      group_name,
      parish,
      name,
      login_id
    limit v_limit
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', id,
      'profileId', profile_id,
      'nickname', coalesce(login_id, matched_login_id::text, ''),
      'name', coalesce(nullif(name, ''), matched_name, ''),
      'parish', coalesce(nullif(parish, ''), matched_parish, ''),
      'groupName', coalesce(group_name, ''),
      'lodging', jsonb_build_object(
        'building', coalesce(lodging_building, ''),
        'room', coalesce(lodging_room, ''),
        'group', coalesce(lodging_group, ''),
        'note', coalesce(lodging_note, '')
      ),
      'vehicle', jsonb_build_object(
        'group', coalesce(vehicle_group, ''),
        'route', coalesce(vehicle_route, ''),
        'no', coalesce(vehicle_no, ''),
        'departure', coalesce(vehicle_departure, ''),
        'seat', coalesce(vehicle_seat, ''),
        'note', coalesce(vehicle_note, '')
      ),
      'rawNote', coalesce(raw_note, ''),
      'matched', profile_id is not null,
      'matchStatus', coalesce(match_status, ''),
      'matchDetail', coalesce(match_detail, ''),
      'candidateProfiles', coalesce(candidate_profiles, '[]'::jsonb),
      'sourceBatch', coalesce(source_batch, ''),
      'updatedAt', updated_at
    )
    order by
      case
        when match_status = 'duplicate_needs_check' then 0
        when profile_id is null then 1
        else 2
      end,
      sort_order,
      group_name,
      parish,
      name,
      login_id
  ), '[]'::jsonb)
  into v_rows
  from limited;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'viewer', v_admin.login_id,
    'total', v_total,
    'limit', v_limit,
    'missingProfileCount', v_missing_profile_count,
    'duplicateProfileCount', v_duplicate_count,
    'rows', v_rows
  );
end;
$$;

create or replace function public.admin_set_logistics_assignment_profile(
  p_assignment_id uuid,
  p_profile_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_assignment public.retreat_logistics_assignments%rowtype;
  v_profile public.profiles%rowtype;
begin
  v_admin := public.bu_admin_profile();

  select *
  into v_assignment
  from public.retreat_logistics_assignments
  where id = p_assignment_id
  for update;

  if v_assignment.id is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'assignment_not_found');
  end if;

  if p_profile_id is null then
    update public.retreat_logistics_assignments
    set profile_id = null,
        login_id = '',
        match_status = 'manual_unmatched',
        match_detail = '',
        raw_note = case
          when coalesce(raw_note, '') = ''
            or raw_note = '앱 가입자 매칭 없음'
            or raw_note like '이름 중복 확인 필요:%'
          then '관리자 연결 해제'
          else raw_note
        end,
        updated_at = now()
    where id = p_assignment_id
    returning * into v_assignment;

    return jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'viewer', v_admin.login_id,
      'assignment', public.bu_logistics_assignment_json(v_assignment)
    );
  end if;

  select *
  into v_profile
  from public.profiles
  where id = p_profile_id
    and account_status = 'active';

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'profile_not_found');
  end if;

  update public.retreat_logistics_assignments
  set profile_id = v_profile.id,
      login_id = v_profile.login_id,
      name = coalesce(nullif(name, ''), v_profile.name),
      parish = coalesce(nullif(parish, ''), v_profile.parish),
      match_status = 'matched',
      match_detail = v_profile.login_id,
      raw_note = case
        when raw_note = '앱 가입자 매칭 없음'
          or raw_note like '이름 중복 확인 필요:%'
          or raw_note = '관리자 연결 해제'
        then ''
        else raw_note
      end,
      updated_at = now()
  where id = p_assignment_id
  returning * into v_assignment;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'viewer', v_admin.login_id,
    'profileId', v_profile.id,
    'nickname', v_profile.login_id,
    'assignment', public.bu_logistics_assignment_json(v_assignment)
  );
end;
$$;

revoke all on function public.admin_get_logistics_assignments(text, integer) from public, anon, authenticated;
revoke all on function public.admin_set_logistics_assignment_profile(uuid, uuid) from public, anon, authenticated;

grant execute on function public.admin_get_logistics_assignments(text, integer) to authenticated;
grant execute on function public.admin_set_logistics_assignment_profile(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
