-- 관리자 앱 가입자 목록을 교구와 이름 기준으로 정렬해 조회하는 RPC를 제공한다.
begin;

create or replace function public.admin_get_raffle_attendance(
  p_query text default '',
  p_limit integer default 80,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_query text := lower(trim(coalesce(p_query, '')));
  v_limit integer := greatest(1, least(500, coalesce(p_limit, 80)));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
  v_result jsonb;
begin
  v_admin := public.bu_admin_profile();

  with filtered as (
    select
      p.*,
      coalesce(ra.attended, false) as attended,
      (select count(*)::integer from public.raffle_tickets rt where rt.profile_id = p.id and rt.active = true) as raffle_tickets,
      case
        when p.parish = '1청' then 10
        when p.parish = '2청' then 20
        when p.parish = '3청' then 30
        when p.parish = '4청' then 40
        when p.parish = 'VIP' then 50
        when p.parish in ('교회학교/목양교구', '교회학교', '목양교구') then 60
        else 90
      end as parish_order
    from public.profiles p
    left join public.retreat_attendance ra on ra.profile_id = p.id
    where p.account_status = 'active'
      and (
        v_query = ''
        or lower(p.login_id::text) like '%' || v_query || '%'
        or lower(p.name) like '%' || v_query || '%'
        or lower(p.parish) like '%' || v_query || '%'
      )
  ),
  page_users as (
    select *
    from filtered
    order by parish_order, name, login_id::text
    offset v_offset
    limit v_limit
  ),
  deleted_users as (
    select *
    from public.profiles p
    where p.account_status <> 'active'
    order by p.deleted_at desc nulls last, p.updated_at desc
    limit 80
  )
  select jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'viewer', v_admin.login_id,
    'totalUsers', (select count(*) from public.profiles where account_status = 'active'),
    'attendedCount', (select count(*) from public.retreat_attendance ra join public.profiles p on p.id = ra.profile_id where p.account_status = 'active' and ra.attended = true),
    'raffleExcludedCount', (select count(*) from public.profiles where account_status = 'active' and raffle_excluded = true),
    'deletedCount', (select count(*) from public.profiles where account_status <> 'active'),
    'returnedUsers', (select count(*) from page_users),
    'filteredUsers', (select count(*) from filtered),
    'usersHasMore', (select count(*) from filtered) > v_offset + (select count(*) from page_users),
    'users', coalesce((select jsonb_agg(jsonb_build_object(
      'nickname', login_id,
      'name', name,
      'parish', parish,
      'attended', attended,
      'raffleExcluded', raffle_excluded,
      'raffleTickets', raffle_tickets
    ) order by parish_order, name, login_id::text) from page_users), '[]'::jsonb),
    'deletedUsers', coalesce((select jsonb_agg(jsonb_build_object(
      'nickname', login_id,
      'name', name,
      'parish', parish,
      'inactiveAt', coalesce(deleted_at, updated_at)
    ) order by coalesce(deleted_at, updated_at) desc) from deleted_users), '[]'::jsonb)
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.admin_get_raffle_attendance(text, integer, integer) from public, anon, authenticated;
grant execute on function public.admin_get_raffle_attendance(text, integer, integer) to authenticated;

commit;
