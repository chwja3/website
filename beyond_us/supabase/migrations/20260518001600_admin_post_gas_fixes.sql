-- Admin 화면의 추첨권 번호 페이지네이션과 상태 점검 보조 RPC를 보강한다.

begin;

create or replace function public.admin_get_raffle_tickets(
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
  v_limit integer := greatest(1, least(1000, coalesce(p_limit, 80)));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
  v_total integer := 0;
  v_returned integer := 0;
  v_tickets jsonb := '[]'::jsonb;
  v_available_numbers jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  with filtered as (
    select
      rt.ticket_no,
      rt.active,
      rt.condition_key,
      rt.issued_at,
      p.login_id,
      p.name,
      p.parish,
      rc.label as condition_label
    from public.raffle_tickets rt
    left join public.profiles p on p.id = rt.profile_id
    left join public.raffle_conditions rc on rc.condition_key = rt.condition_key
    where v_query = ''
      or lpad(rt.ticket_no::text, 4, '0') like '%' || v_query || '%'
      or lower(coalesce(p.login_id::text, '')) like '%' || v_query || '%'
      or lower(coalesce(p.name, '')) like '%' || v_query || '%'
      or lower(coalesce(p.parish, '')) like '%' || v_query || '%'
      or lower(coalesce(rc.label, rt.condition_key, '')) like '%' || v_query || '%'
  ),
  paged as (
    select *
    from filtered
    order by ticket_no
    limit v_limit
    offset v_offset
  )
  select
    (select count(*)::integer from filtered),
    (select count(*)::integer from paged),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'ticket_no', lpad(ticket_no::text, 4, '0'),
        'active', active,
        'userId', login_id,
        'name', name,
        'parish', parish,
        'condition', condition_key,
        'condition_label', condition_label,
        'week_key', '',
        'issued_at', issued_at
      ) order by ticket_no)
      from paged
    ), '[]'::jsonb)
  into v_total, v_returned, v_tickets;

  select coalesce(jsonb_agg(lpad(ticket_no::text, 4, '0') order by ticket_no), '[]'::jsonb)
  into v_available_numbers
  from public.raffle_tickets
  where active = false;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'admin', v_admin.login_id,
    'activeCount', (select count(*) from public.raffle_tickets where active = true),
    'availableCount', (select count(*) from public.raffle_tickets where active = false),
    'availableNumbers', v_available_numbers,
    'returned', v_returned,
    'filteredTotal', v_total,
    'hasMore', v_offset + v_returned < v_total,
    'tickets', v_tickets
  );
end;
$$;

revoke all on function public.admin_get_raffle_tickets(text, integer, integer) from public, anon, authenticated;
grant execute on function public.admin_get_raffle_tickets(text, integer, integer) to authenticated;

commit;
