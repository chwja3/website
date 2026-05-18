-- 추첨권 자동 발급 정책을 Supabase 현재 상태 갱신에 연결한다.
begin;

create or replace function public.bu_raffle_card_count(p_profile_id uuid)
returns integer
language sql
security definer
set search_path = public
as $$
  select count(distinct card_id)::integer
  from public.user_cards
  where profile_id = p_profile_id
    and card_id between 1 and 10
    and quantity > 0;
$$;

create or replace function public.bu_update_raffle_summary(p_profile_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_active_count integer := 0;
begin
  select count(*)::integer
  into v_active_count
  from public.raffle_tickets
  where profile_id = p_profile_id
    and active = true;

  insert into public.user_summary (
    profile_id,
    raffle_ticket_count,
    updated_at
  )
  values (
    p_profile_id,
    v_active_count,
    now()
  )
  on conflict (profile_id) do update
  set raffle_ticket_count = excluded.raffle_ticket_count,
      updated_at = now();

  return v_active_count;
end;
$$;

create or replace function public.bu_event_source(p_source text)
returns public.event_source
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source public.event_source := 'server';
begin
  begin
    v_source := coalesce(nullif(trim(coalesce(p_source, '')), ''), 'server')::public.event_source;
  exception when invalid_text_representation then
    v_source := 'server';
  end;

  return v_source;
end;
$$;

create or replace function public.bu_release_profile_raffle_tickets(
  p_profile_id uuid,
  p_reason text default 'policy_release',
  p_source text default 'server',
  p_created_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source public.event_source := public.bu_event_source(p_source);
  v_reason text := coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'policy_release');
  v_released integer := 0;
  v_logged integer := 0;
  v_tickets jsonb := '[]'::jsonb;
  v_active_count integer := 0;
begin
  perform pg_advisory_xact_lock(hashtext('raffle_ticket_issue'), 0);
  perform pg_advisory_xact_lock(hashtext('raffle_ticket_profile'), hashtext(p_profile_id::text));

  with to_release as (
    select ticket_no, condition_key
    from public.raffle_tickets
    where profile_id = p_profile_id
      and active = true
    order by ticket_no
    for update
  ),
  released as (
    update public.raffle_tickets rt
    set active = false,
        profile_id = null,
        condition_key = null,
        event_id = null,
        revoked_at = now(),
        revoked_reason = v_reason,
        updated_at = now()
    from to_release tr
    where rt.ticket_no = tr.ticket_no
    returning rt.ticket_no
  ),
  logged as (
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
    select
      p_profile_id,
      'raffle.revoked',
      'raffle_ticket',
      r.ticket_no::text,
      -1,
      jsonb_build_object(
        'conditionKey', tr.condition_key,
        'ticketNo', lpad(r.ticket_no::text, 4, '0'),
        'reason', v_reason
      ),
      v_source,
      p_created_by
    from released r
    join to_release tr on tr.ticket_no = r.ticket_no
    returning id
  )
  select
    count(*)::integer,
    coalesce(jsonb_agg(jsonb_build_object(
      'ticketNo', lpad(r.ticket_no::text, 4, '0'),
      'conditionKey', tr.condition_key
    ) order by r.ticket_no), '[]'::jsonb),
    (select count(*)::integer from logged)
  into v_released, v_tickets, v_logged
  from released r
  join to_release tr on tr.ticket_no = r.ticket_no;

  v_active_count := public.bu_update_raffle_summary(p_profile_id);

  return jsonb_build_object(
    'ok', true,
    'released', coalesce(v_released, 0),
    'logged', coalesce(v_logged, 0),
    'tickets', coalesce(v_tickets, '[]'::jsonb),
    'activeCount', v_active_count
  );
end;
$$;

create or replace function public.bu_issue_raffle_ticket(
  p_profile_id uuid,
  p_condition_key text,
  p_source text default 'server',
  p_created_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_condition_key text := nullif(trim(coalesce(p_condition_key, '')), '');
  v_condition public.raffle_conditions%rowtype;
  v_source public.event_source := public.bu_event_source(p_source);
  v_existing_ticket_no integer;
  v_ticket_no integer;
  v_event_id uuid;
  v_active_count integer := 0;
begin
  if v_condition_key is null then
    return jsonb_build_object('ok', false, 'skipped', true, 'reason', 'missing_condition');
  end if;

  perform pg_advisory_xact_lock(hashtext('raffle_ticket_issue'), 0);
  perform pg_advisory_xact_lock(hashtext('raffle_ticket_profile'), hashtext(p_profile_id::text));

  select *
  into v_profile
  from public.profiles
  where id = p_profile_id
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'skipped', true, 'reason', 'profile_not_found');
  end if;

  if v_profile.account_status <> 'active' then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'inactive_profile');
  end if;

  if coalesce(v_profile.raffle_excluded, false) then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'raffle_excluded');
  end if;

  select *
  into v_condition
  from public.raffle_conditions
  where condition_key = v_condition_key
  limit 1;

  if v_condition.condition_key is null then
    return jsonb_build_object('ok', false, 'skipped', true, 'reason', 'unknown_condition', 'conditionKey', v_condition_key);
  end if;

  if coalesce(v_condition.enabled, false) = false then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'condition_disabled', 'conditionKey', v_condition_key);
  end if;

  select ticket_no
  into v_existing_ticket_no
  from public.raffle_tickets
  where profile_id = p_profile_id
    and condition_key = v_condition_key
    and active = true
  order by ticket_no
  limit 1;

  if v_existing_ticket_no is not null then
    v_active_count := public.bu_update_raffle_summary(p_profile_id);
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'already_issued',
      'conditionKey', v_condition_key,
      'ticketNo', lpad(v_existing_ticket_no::text, 4, '0'),
      'activeCount', v_active_count
    );
  end if;

  select ticket_no
  into v_ticket_no
  from public.raffle_tickets
  where active = false
  order by ticket_no
  limit 1
  for update;

  if v_ticket_no is null then
    select coalesce(max(ticket_no), 0) + 1
    into v_ticket_no
    from public.raffle_tickets;

    insert into public.raffle_tickets (
      ticket_no,
      active,
      profile_id,
      condition_key,
      issued_at,
      revoked_at,
      revoked_reason,
      updated_at
    )
    values (
      v_ticket_no,
      true,
      p_profile_id,
      v_condition_key,
      now(),
      null,
      null,
      now()
    );
  else
    update public.raffle_tickets
    set active = true,
        profile_id = p_profile_id,
        condition_key = v_condition_key,
        issued_at = now(),
        revoked_at = null,
        revoked_reason = null,
        updated_at = now()
    where ticket_no = v_ticket_no;
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
    'raffle.issued',
    'raffle_ticket',
    v_ticket_no::text,
    1,
    jsonb_build_object(
      'conditionKey', v_condition_key,
      'conditionLabel', v_condition.label,
      'ticketNo', lpad(v_ticket_no::text, 4, '0')
    ),
    v_source,
    p_created_by
  )
  returning id into v_event_id;

  update public.raffle_tickets
  set event_id = v_event_id,
      updated_at = now()
  where ticket_no = v_ticket_no;

  v_active_count := public.bu_update_raffle_summary(p_profile_id);

  return jsonb_build_object(
    'ok', true,
    'issued', true,
    'conditionKey', v_condition_key,
    'ticketNo', lpad(v_ticket_no::text, 4, '0'),
    'eventId', v_event_id,
    'activeCount', v_active_count
  );
end;
$$;

create or replace function public.bu_sync_profile_raffle_tickets(
  p_profile_id uuid,
  p_source text default 'server',
  p_created_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_unique_cards integer := 0;
  v_results jsonb := '[]'::jsonb;
  v_release jsonb := '{}'::jsonb;
  v_result jsonb := '{}'::jsonb;
  v_active_count integer := 0;
begin
  select *
  into v_profile
  from public.profiles
  where id = p_profile_id
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'error', 'profile_not_found');
  end if;

  if v_profile.account_status <> 'active' then
    v_release := public.bu_release_profile_raffle_tickets(p_profile_id, 'inactive_profile', p_source, p_created_by);
    return jsonb_build_object('ok', true, 'released', v_release, 'activeCount', 0, 'reason', 'inactive_profile');
  end if;

  if coalesce(v_profile.raffle_excluded, false) then
    v_release := public.bu_release_profile_raffle_tickets(p_profile_id, 'raffle_excluded', p_source, p_created_by);
    return jsonb_build_object('ok', true, 'released', v_release, 'activeCount', 0, 'reason', 'raffle_excluded');
  end if;

  v_result := public.bu_issue_raffle_ticket(p_profile_id, 'app_signup', p_source, p_created_by);
  v_results := v_results || jsonb_build_array(v_result);

  v_unique_cards := public.bu_raffle_card_count(p_profile_id);

  if v_unique_cards >= 3 then
    v_result := public.bu_issue_raffle_ticket(p_profile_id, 'card_3', p_source, p_created_by);
    v_results := v_results || jsonb_build_array(v_result);
  end if;

  if v_unique_cards >= 5 then
    v_result := public.bu_issue_raffle_ticket(p_profile_id, 'card_5', p_source, p_created_by);
    v_results := v_results || jsonb_build_array(v_result);
  end if;

  if v_unique_cards >= 10 then
    v_result := public.bu_issue_raffle_ticket(p_profile_id, 'card_10', p_source, p_created_by);
    v_results := v_results || jsonb_build_array(v_result);
  end if;

  v_active_count := public.bu_update_raffle_summary(p_profile_id);

  return jsonb_build_object(
    'ok', true,
    'uniqueCards', v_unique_cards,
    'results', v_results,
    'activeCount', v_active_count
  );
end;
$$;

create or replace function public.bu_sync_raffle_from_profile_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.bu_sync_profile_raffle_tickets(new.id, 'server', null);
  return new;
end;
$$;

create or replace function public.bu_sync_raffle_from_user_cards_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' and new.card_id between 1 and 10 and new.quantity > 0 then
    perform public.bu_sync_profile_raffle_tickets(new.profile_id, 'server', null);
  elsif tg_op = 'UPDATE'
        and new.card_id between 1 and 10
        and new.quantity > 0
        and coalesce(old.quantity, 0) is distinct from coalesce(new.quantity, 0) then
    perform public.bu_sync_profile_raffle_tickets(new.profile_id, 'server', null);
  end if;

  return new;
end;
$$;

drop trigger if exists sync_profiles_raffle_tickets on public.profiles;
create trigger sync_profiles_raffle_tickets
after insert or update of account_status, raffle_excluded on public.profiles
for each row execute function public.bu_sync_raffle_from_profile_trigger();

drop trigger if exists sync_user_cards_raffle_tickets on public.user_cards;
create trigger sync_user_cards_raffle_tickets
after insert or update of quantity on public.user_cards
for each row execute function public.bu_sync_raffle_from_user_cards_trigger();

create or replace function public.backfill_raffle_tickets()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_checked integer := 0;
  v_result jsonb;
  v_active_count integer := 0;
  v_excluded_count integer := 0;
begin
  for v_profile_id in
    select id
    from public.profiles
    order by participant_no nulls last, created_at
  loop
    v_result := public.bu_sync_profile_raffle_tickets(v_profile_id, 'migration', null);
    v_checked := v_checked + 1;
  end loop;

  select count(*)::integer
  into v_active_count
  from public.raffle_tickets
  where active = true;

  select count(*)::integer
  into v_excluded_count
  from public.profiles
  where account_status = 'active'
    and raffle_excluded = true;

  return jsonb_build_object(
    'ok', true,
    'checked', v_checked,
    'activeCount', v_active_count,
    'excludedCount', v_excluded_count
  );
end;
$$;

revoke all on function public.bu_raffle_card_count(uuid) from public, anon, authenticated;
revoke all on function public.bu_update_raffle_summary(uuid) from public, anon, authenticated;
revoke all on function public.bu_event_source(text) from public, anon, authenticated;
revoke all on function public.bu_release_profile_raffle_tickets(uuid, text, text, uuid) from public, anon, authenticated;
revoke all on function public.bu_issue_raffle_ticket(uuid, text, text, uuid) from public, anon, authenticated;
revoke all on function public.bu_sync_profile_raffle_tickets(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.bu_sync_raffle_from_profile_trigger() from public, anon, authenticated;
revoke all on function public.bu_sync_raffle_from_user_cards_trigger() from public, anon, authenticated;
revoke all on function public.backfill_raffle_tickets() from public, anon, authenticated;

commit;
