-- 관리자 앱 가입자 탭에서 유저별 추첨권 현황 조회와 단일 회수를 처리한다.
begin;

create or replace function public.admin_get_profile_raffle_tickets(
  p_login_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_tickets jsonb := '[]'::jsonb;
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

  select coalesce(jsonb_agg(jsonb_build_object(
    'ticketNo', lpad(rt.ticket_no::text, 4, '0'),
    'conditionKey', rt.condition_key,
    'conditionLabel', coalesce(rc.label, rt.condition_key, '추첨권'),
    'issuedAt', rt.issued_at,
    'eventId', rt.event_id
  ) order by rt.ticket_no), '[]'::jsonb)
  into v_tickets
  from public.raffle_tickets rt
  left join public.raffle_conditions rc on rc.condition_key = rt.condition_key
  where rt.profile_id = v_profile.id
    and rt.active = true;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'admin', v_admin.login_id,
    'user', jsonb_build_object(
      'nickname', v_profile.login_id,
      'name', v_profile.name,
      'parish', v_profile.parish,
      'raffleExcluded', v_profile.raffle_excluded
    ),
    'activeCount', jsonb_array_length(v_tickets),
    'tickets', v_tickets
  );
end;
$$;

create or replace function public.admin_revoke_raffle_ticket(
  p_login_id text,
  p_ticket_no text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_ticket_no integer;
  v_ticket record;
  v_reason text := coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'admin_manual_revoke');
  v_event_id uuid;
  v_active_count integer := 0;
begin
  v_admin := public.bu_admin_profile();

  begin
    v_ticket_no := nullif(regexp_replace(coalesce(p_ticket_no, ''), '\D', '', 'g'), '')::integer;
  exception when invalid_text_representation then
    v_ticket_no := null;
  end;

  if v_ticket_no is null then
    return jsonb_build_object('ok', false, 'error', 'missing_ticket_no');
  end if;

  select *
  into v_profile
  from public.profiles
  where login_id = p_login_id
    and account_status = 'active'
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'error', 'user_not_found');
  end if;

  perform pg_advisory_xact_lock(hashtext('raffle_ticket_issue'), 0);
  perform pg_advisory_xact_lock(hashtext('raffle_ticket_profile'), hashtext(v_profile.id::text));

  select rt.ticket_no, rt.condition_key
  into v_ticket
  from public.raffle_tickets rt
  where rt.ticket_no = v_ticket_no
    and rt.profile_id = v_profile.id
    and rt.active = true
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'ticket_not_found');
  end if;

  update public.raffle_tickets
  set active = false,
      profile_id = null,
      condition_key = null,
      event_id = null,
      revoked_at = now(),
      revoked_reason = v_reason,
      updated_at = now()
  where ticket_no = v_ticket.ticket_no;

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
    v_profile.id,
    'raffle.revoked',
    'raffle_ticket',
    v_ticket.ticket_no::text,
    -1,
    jsonb_build_object(
      'conditionKey', v_ticket.condition_key,
      'ticketNo', lpad(v_ticket.ticket_no::text, 4, '0'),
      'reason', v_reason,
      'adminManual', true
    ),
    'admin',
    v_admin.id
  )
  returning id into v_event_id;

  v_active_count := public.bu_update_raffle_summary(v_profile.id);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'user', v_profile.login_id,
    'ticketNo', lpad(v_ticket.ticket_no::text, 4, '0'),
    'conditionKey', v_ticket.condition_key,
    'eventId', v_event_id,
    'activeCount', v_active_count
  );
end;
$$;

revoke all on function public.admin_get_profile_raffle_tickets(text) from public, anon, authenticated;
revoke all on function public.admin_revoke_raffle_ticket(text, text, text) from public, anon, authenticated;

grant execute on function public.admin_get_profile_raffle_tickets(text) to authenticated;
grant execute on function public.admin_revoke_raffle_ticket(text, text, text) to authenticated;

notify pgrst, 'reload schema';

commit;
