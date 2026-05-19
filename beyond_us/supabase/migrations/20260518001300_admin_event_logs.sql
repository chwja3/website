-- 관리자 화면에서 최신 이벤트 로그를 닉네임과 함께 조회하는 RPC를 제공한다.
begin;

create or replace function public.admin_event_logs(
  p_limit integer default 200,
  p_event_type text default null,
  p_query text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 1000);
  v_event_type text := nullif(trim(coalesce(p_event_type, '')), '');
  v_query_raw text := nullif(trim(coalesce(p_query, '')), '');
  v_query_like text := '%' || lower(coalesce(v_query_raw, '')) || '%';
  v_events jsonb := '[]'::jsonb;
  v_event_types jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  with filtered as (
    select
      e.id,
      e.occurred_at,
      e.profile_id,
      p.login_id::text as login_id,
      p.display_name,
      p.name,
      p.parish,
      e.event_type,
      e.ref_type,
      e.ref_id,
      e.amount,
      e.week_key,
      e.payload,
      e.source::text as source,
      e.request_id,
      e.created_by,
      creator.login_id::text as created_by_login_id,
      creator.display_name as created_by_display_name,
      e.created_at
    from public.events e
    left join public.profiles p on p.id = e.profile_id
    left join public.profiles creator on creator.id = e.created_by
    where (v_event_type is null or e.event_type = v_event_type)
      and (
        v_query_raw is null
        or lower(concat_ws(
          ' ',
          e.id::text,
          e.event_type,
          e.ref_type,
          e.ref_id,
          e.week_key,
          e.source::text,
          e.request_id,
          p.login_id::text,
          p.display_name,
          p.name,
          p.parish,
          creator.login_id::text,
          creator.display_name
        )) like v_query_like
      )
    order by e.occurred_at desc, e.created_at desc, e.id desc
    limit v_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'occurredAt', occurred_at,
    'profileId', profile_id,
    'loginId', login_id,
    'displayName', display_name,
    'name', name,
    'parish', parish,
    'eventType', event_type,
    'refType', ref_type,
    'refId', ref_id,
    'amount', amount,
    'weekKey', week_key,
    'payload', payload,
    'source', source,
    'requestId', request_id,
    'createdBy', created_by,
    'createdByLoginId', created_by_login_id,
    'createdByDisplayName', created_by_display_name,
    'createdAt', created_at
  ) order by occurred_at desc, created_at desc, id desc), '[]'::jsonb)
  into v_events
  from filtered;

  select coalesce(jsonb_agg(event_type order by event_type), '[]'::jsonb)
  into v_event_types
  from (
    select distinct e.event_type
    from public.events e
    where e.event_type is not null and e.event_type <> ''
  ) types;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'events', v_events,
    'eventTypes', v_event_types,
    'limit', v_limit,
    'filters', jsonb_build_object(
      'eventType', v_event_type,
      'query', v_query_raw
    ),
    'viewer', v_admin.login_id
  );
end;
$$;

revoke all on function public.admin_event_logs(integer, text, text) from public, anon, authenticated;
grant execute on function public.admin_event_logs(integer, text, text) to authenticated;

commit;
