-- 숙소와 차량 배정표를 개인 앱과 관리자 페이지에서 조회하는 테이블과 RPC를 추가한다.
begin;

create table if not exists public.retreat_logistics_assignments (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  login_id text,
  name text not null default '',
  parish text not null default '',
  group_name text not null default '',
  lodging_building text not null default '',
  lodging_room text not null default '',
  lodging_group text not null default '',
  lodging_note text not null default '',
  vehicle_group text not null default '',
  vehicle_route text not null default '',
  vehicle_no text not null default '',
  vehicle_departure text not null default '',
  vehicle_seat text not null default '',
  vehicle_note text not null default '',
  raw_note text not null default '',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists retreat_logistics_assignments_profile_idx
on public.retreat_logistics_assignments (profile_id)
where profile_id is not null;

create index if not exists retreat_logistics_assignments_login_idx
on public.retreat_logistics_assignments (lower(login_id))
where login_id is not null and login_id <> '';

create index if not exists retreat_logistics_assignments_sort_idx
on public.retreat_logistics_assignments (sort_order, name);

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'set_retreat_logistics_assignments_updated_at'
      and tgrelid = 'public.retreat_logistics_assignments'::regclass
  ) then
    create trigger set_retreat_logistics_assignments_updated_at
    before update on public.retreat_logistics_assignments
    for each row execute function public.set_updated_at();
  end if;
end;
$$;

alter table public.retreat_logistics_assignments enable row level security;
revoke all on public.retreat_logistics_assignments from public, anon, authenticated;

comment on table public.retreat_logistics_assignments is '수련회 숙소와 차량 배정표. 개인 앱은 본인 행만, 어드민은 전체 행을 RPC로 조회한다.';
comment on column public.retreat_logistics_assignments.raw_note is '엑셀 원본에서 별도 필드로 나누기 어려운 운영 비고.';

create or replace function public.bu_logistics_normalize(p_value text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(coalesce(p_value, ''), '\s+', '', 'g'));
$$;

insert into public.tab_settings (tab_key, label, enabled, status, sort_order)
values ('logistics', '숙소/차량', true, 'open', 87)
on conflict (tab_key) do update
set label = excluded.label,
    sort_order = excluded.sort_order,
    updated_at = now();

create or replace function public.bu_logistics_assignment_json(a public.retreat_logistics_assignments)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', a.id,
    'profileId', a.profile_id,
    'nickname', coalesce(a.login_id, ''),
    'name', coalesce(a.name, ''),
    'parish', coalesce(a.parish, ''),
    'groupName', coalesce(a.group_name, ''),
    'lodging', jsonb_build_object(
      'building', coalesce(a.lodging_building, ''),
      'room', coalesce(a.lodging_room, ''),
      'group', coalesce(a.lodging_group, ''),
      'note', coalesce(a.lodging_note, '')
    ),
    'vehicle', jsonb_build_object(
      'group', coalesce(a.vehicle_group, ''),
      'route', coalesce(a.vehicle_route, ''),
      'no', coalesce(a.vehicle_no, ''),
      'departure', coalesce(a.vehicle_departure, ''),
      'seat', coalesce(a.vehicle_seat, ''),
      'note', coalesce(a.vehicle_note, '')
    ),
    'rawNote', coalesce(a.raw_note, ''),
    'updatedAt', a.updated_at
  );
$$;

create or replace function public.get_my_logistics_assignment(
  p_login_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_assignment public.retreat_logistics_assignments%rowtype;
begin
  if v_auth_uid is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'unauthorized');
  end if;

  select *
  into v_profile
  from public.profiles
  where auth_user_id = v_auth_uid
    and account_status = 'active'
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'user_not_found');
  end if;

  select a.*
  into v_assignment
  from public.retreat_logistics_assignments a
  where a.profile_id = v_profile.id
     or (
       a.profile_id is null
       and a.login_id is not null
       and lower(a.login_id) = lower(v_profile.login_id::text)
     )
     or (
       a.profile_id is null
       and coalesce(a.login_id, '') = ''
       and public.bu_logistics_normalize(a.name) = public.bu_logistics_normalize(v_profile.name)
       and (
         public.bu_logistics_normalize(a.parish) = public.bu_logistics_normalize(v_profile.parish)
         or coalesce(a.parish, '') = ''
       )
     )
  order by
    case
      when a.profile_id = v_profile.id then 0
      when a.login_id is not null and lower(a.login_id) = lower(v_profile.login_id::text) then 1
      else 2
    end,
    a.sort_order,
    a.updated_at desc
  limit 1;

  if v_assignment.id is null then
    return jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'profile', jsonb_build_object(
        'nickname', v_profile.login_id,
        'name', v_profile.name,
        'parish', v_profile.parish
      ),
      'assignment', null
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'profile', jsonb_build_object(
      'nickname', v_profile.login_id,
      'name', v_profile.name,
      'parish', v_profile.parish
    ),
    'assignment', public.bu_logistics_assignment_json(v_assignment)
  );
end;
$$;

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
       or lower(coalesce(name, '')) like '%' || v_query || '%'
       or lower(coalesce(parish, '')) like '%' || v_query || '%'
       or lower(coalesce(group_name, '')) like '%' || v_query || '%'
       or lower(coalesce(lodging_building, '')) like '%' || v_query || '%'
       or lower(coalesce(lodging_room, '')) like '%' || v_query || '%'
       or lower(coalesce(vehicle_group, '')) like '%' || v_query || '%'
       or lower(coalesce(vehicle_route, '')) like '%' || v_query || '%'
       or lower(coalesce(vehicle_no, '')) like '%' || v_query || '%'
       or lower(coalesce(raw_note, '')) like '%' || v_query || '%'
  )
  select count(*),
         count(*) filter (where profile_id is null)
  into v_total, v_missing_profile_count
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
       or lower(coalesce(name, '')) like '%' || v_query || '%'
       or lower(coalesce(parish, '')) like '%' || v_query || '%'
       or lower(coalesce(group_name, '')) like '%' || v_query || '%'
       or lower(coalesce(lodging_building, '')) like '%' || v_query || '%'
       or lower(coalesce(lodging_room, '')) like '%' || v_query || '%'
       or lower(coalesce(vehicle_group, '')) like '%' || v_query || '%'
       or lower(coalesce(vehicle_route, '')) like '%' || v_query || '%'
       or lower(coalesce(vehicle_no, '')) like '%' || v_query || '%'
       or lower(coalesce(raw_note, '')) like '%' || v_query || '%'
  ),
  limited as (
    select *
    from filtered
    order by sort_order, group_name, parish, name, login_id
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
      'updatedAt', updated_at
    )
    order by sort_order, group_name, parish, name, login_id
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
    'rows', v_rows
  );
end;
$$;

revoke all on function public.bu_logistics_normalize(text) from public, anon, authenticated;
revoke all on function public.bu_logistics_assignment_json(public.retreat_logistics_assignments) from public, anon, authenticated;
revoke all on function public.get_my_logistics_assignment(text) from public, anon, authenticated;
revoke all on function public.admin_get_logistics_assignments(text, integer) from public, anon, authenticated;

grant execute on function public.get_my_logistics_assignment(text) to authenticated;
grant execute on function public.admin_get_logistics_assignments(text, integer) to authenticated;

notify pgrst, 'reload schema';

commit;
