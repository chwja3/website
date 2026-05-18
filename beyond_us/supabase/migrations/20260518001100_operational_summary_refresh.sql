-- 운영 정본 테이블 변경 후 사용자 요약과 추첨권 상태를 자동 동기화한다.
begin;

create or replace function public.bu_refresh_profile_summary(p_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean := false;
  v_mission_count integer := 0;
  v_total_cards integer := 0;
  v_unique_cards integer := 0;
  v_raffle_ticket_count integer := 0;
  v_active_trade_count integer := 0;
  v_last_activity_at timestamptz;
  v_collection jsonb := '{}'::jsonb;
begin
  select exists(
    select 1 from public.profiles where id = p_profile_id
  )
  into v_exists;

  if not v_exists then
    return jsonb_build_object('ok', false, 'error', 'profile_not_found');
  end if;

  select count(*)::integer
  into v_mission_count
  from public.mission_submissions
  where profile_id = p_profile_id;

  select
    coalesce(sum(quantity), 0)::integer,
    (count(*) filter (where quantity > 0 and card_id between 1 and 10))::integer
  into v_total_cards, v_unique_cards
  from public.user_cards
  where profile_id = p_profile_id;

  select count(*)::integer
  into v_raffle_ticket_count
  from public.raffle_tickets
  where profile_id = p_profile_id
    and active = true;

  select count(*)::integer
  into v_active_trade_count
  from public.trades
  where status = 'requested'
    and (requester_id = p_profile_id or target_id = p_profile_id);

  select max(occurred_at)
  into v_last_activity_at
  from public.events
  where profile_id = p_profile_id;

  v_collection := public.bu_collection_counts(p_profile_id);

  insert into public.user_summary (
    profile_id,
    mission_count,
    total_cards,
    raffle_ticket_count,
    active_trade_count,
    last_activity_at,
    payload,
    updated_at
  )
  values (
    p_profile_id,
    v_mission_count,
    v_total_cards,
    v_raffle_ticket_count,
    v_active_trade_count,
    v_last_activity_at,
    jsonb_build_object(
      'collection', v_collection,
      'uniqueCards', v_unique_cards,
      'lastSummaryRefreshedAt', now()
    ),
    now()
  )
  on conflict (profile_id) do update
  set mission_count = excluded.mission_count,
      total_cards = excluded.total_cards,
      raffle_ticket_count = excluded.raffle_ticket_count,
      active_trade_count = excluded.active_trade_count,
      last_activity_at = excluded.last_activity_at,
      payload = coalesce(public.user_summary.payload, '{}'::jsonb)
        || excluded.payload,
      updated_at = now();

  return jsonb_build_object(
    'ok', true,
    'missionCount', v_mission_count,
    'totalCards', v_total_cards,
    'uniqueCards', v_unique_cards,
    'raffleTicketCount', v_raffle_ticket_count,
    'activeTradeCount', v_active_trade_count,
    'collection', v_collection
  );
end;
$$;

create or replace function public.bu_release_raffle_ticket_condition(
  p_profile_id uuid,
  p_condition_key text,
  p_reason text default 'condition_unmet',
  p_source text default 'server',
  p_created_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_condition_key text := nullif(trim(coalesce(p_condition_key, '')), '');
  v_source public.event_source := public.bu_event_source(p_source);
  v_reason text := coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'condition_unmet');
  v_released integer := 0;
  v_logged integer := 0;
  v_tickets jsonb := '[]'::jsonb;
  v_active_count integer := 0;
begin
  if v_condition_key is null then
    return jsonb_build_object('ok', false, 'released', 0, 'reason', 'missing_condition');
  end if;

  perform pg_advisory_xact_lock(hashtext('raffle_ticket_issue'), 0);
  perform pg_advisory_xact_lock(hashtext('raffle_ticket_profile'), hashtext(p_profile_id::text));

  with to_release as (
    select ticket_no, condition_key
    from public.raffle_tickets
    where profile_id = p_profile_id
      and condition_key = v_condition_key
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
    'conditionKey', v_condition_key,
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
  v_releases jsonb := '[]'::jsonb;
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
    perform public.bu_refresh_profile_summary(p_profile_id);
    return jsonb_build_object('ok', true, 'released', v_release, 'activeCount', 0, 'reason', 'inactive_profile');
  end if;

  if coalesce(v_profile.raffle_excluded, false) then
    v_release := public.bu_release_profile_raffle_tickets(p_profile_id, 'raffle_excluded', p_source, p_created_by);
    perform public.bu_refresh_profile_summary(p_profile_id);
    return jsonb_build_object('ok', true, 'released', v_release, 'activeCount', 0, 'reason', 'raffle_excluded');
  end if;

  v_result := public.bu_issue_raffle_ticket(p_profile_id, 'app_signup', p_source, p_created_by);
  v_results := v_results || jsonb_build_array(v_result);

  v_unique_cards := public.bu_raffle_card_count(p_profile_id);

  if v_unique_cards >= 3 then
    v_result := public.bu_issue_raffle_ticket(p_profile_id, 'card_3', p_source, p_created_by);
  else
    v_result := public.bu_release_raffle_ticket_condition(p_profile_id, 'card_3', 'card_condition_unmet', p_source, p_created_by);
    v_releases := v_releases || jsonb_build_array(v_result);
  end if;
  v_results := v_results || jsonb_build_array(v_result);

  if v_unique_cards >= 5 then
    v_result := public.bu_issue_raffle_ticket(p_profile_id, 'card_5', p_source, p_created_by);
  else
    v_result := public.bu_release_raffle_ticket_condition(p_profile_id, 'card_5', 'card_condition_unmet', p_source, p_created_by);
    v_releases := v_releases || jsonb_build_array(v_result);
  end if;
  v_results := v_results || jsonb_build_array(v_result);

  if v_unique_cards >= 10 then
    v_result := public.bu_issue_raffle_ticket(p_profile_id, 'card_10', p_source, p_created_by);
  else
    v_result := public.bu_release_raffle_ticket_condition(p_profile_id, 'card_10', 'card_condition_unmet', p_source, p_created_by);
    v_releases := v_releases || jsonb_build_array(v_result);
  end if;
  v_results := v_results || jsonb_build_array(v_result);

  v_active_count := public.bu_update_raffle_summary(p_profile_id);
  perform public.bu_refresh_profile_summary(p_profile_id);

  return jsonb_build_object(
    'ok', true,
    'uniqueCards', v_unique_cards,
    'results', v_results,
    'releases', v_releases,
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
  perform public.bu_refresh_profile_summary(new.id);
  return new;
end;
$$;

create or replace function public.bu_sync_raffle_from_user_cards_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_card_id integer;
begin
  if tg_op = 'DELETE' then
    v_profile_id := old.profile_id;
    v_card_id := old.card_id;
  else
    v_profile_id := new.profile_id;
    v_card_id := new.card_id;
  end if;

  if v_profile_id is not null and v_card_id between 1 and 10 then
    perform public.bu_sync_profile_raffle_tickets(v_profile_id, 'server', null);
    perform public.bu_refresh_profile_summary(v_profile_id);
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.bu_refresh_summary_from_event_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.profile_id is not null then
    perform public.bu_refresh_profile_summary(new.profile_id);
  end if;
  return new;
end;
$$;

create or replace function public.bu_refresh_summary_from_mission_submission_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
begin
  v_profile_id := case when tg_op = 'DELETE' then old.profile_id else new.profile_id end;
  if v_profile_id is not null then
    perform public.bu_refresh_profile_summary(v_profile_id);
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.bu_refresh_summary_from_raffle_ticket_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op <> 'DELETE' and new.profile_id is not null then
    perform public.bu_refresh_profile_summary(new.profile_id);
  end if;
  if tg_op <> 'INSERT'
     and old.profile_id is not null
     and (tg_op = 'DELETE' or old.profile_id is distinct from new.profile_id) then
    perform public.bu_refresh_profile_summary(old.profile_id);
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.bu_refresh_summary_from_trade_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requester_id uuid;
  v_target_id uuid;
begin
  if tg_op = 'DELETE' then
    v_requester_id := old.requester_id;
    v_target_id := old.target_id;
  else
    v_requester_id := new.requester_id;
    v_target_id := new.target_id;
  end if;

  if v_requester_id is not null then
    perform public.bu_refresh_profile_summary(v_requester_id);
  end if;
  if v_target_id is not null and v_target_id is distinct from v_requester_id then
    perform public.bu_refresh_profile_summary(v_target_id);
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.admin_audit_user_state(p_limit integer default 500)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_limit integer := greatest(1, least(1000, coalesce(p_limit, 500)));
  v_mismatches jsonb := '[]'::jsonb;
  v_mismatch_count integer := 0;
begin
  v_admin := public.bu_admin_profile();

  with expected as (
    select
      p.id,
      p.login_id,
      p.name,
      coalesce((select count(*)::integer from public.mission_submissions ms where ms.profile_id = p.id), 0) as mission_count,
      coalesce((select sum(uc.quantity)::integer from public.user_cards uc where uc.profile_id = p.id), 0) as total_cards,
      coalesce((select count(*)::integer from public.raffle_tickets rt where rt.profile_id = p.id and rt.active = true), 0) as raffle_ticket_count,
      coalesce((
        select count(*)::integer
        from public.trades t
        where t.status = 'requested'
          and (t.requester_id = p.id or t.target_id = p.id)
      ), 0) as active_trade_count,
      (select max(e.occurred_at) from public.events e where e.profile_id = p.id) as last_activity_at
    from public.profiles p
    where p.account_status = 'active'
    order by p.participant_no nulls last, p.created_at, p.login_id
    limit v_limit
  ),
  compared as (
    select
      e.*,
      coalesce(us.mission_count, 0) as actual_mission_count,
      coalesce(us.total_cards, 0) as actual_total_cards,
      coalesce(us.raffle_ticket_count, 0) as actual_raffle_ticket_count,
      coalesce(us.active_trade_count, 0) as actual_active_trade_count,
      us.last_activity_at as actual_last_activity_at
    from expected e
    left join public.user_summary us on us.profile_id = e.id
  ),
  mismatch_rows as (
    select *
    from compared c
    where c.mission_count is distinct from c.actual_mission_count
       or c.total_cards is distinct from c.actual_total_cards
       or c.raffle_ticket_count is distinct from c.actual_raffle_ticket_count
       or c.active_trade_count is distinct from c.actual_active_trade_count
       or c.last_activity_at is distinct from c.actual_last_activity_at
    order by c.login_id
  )
  select
    count(*)::integer,
    coalesce(jsonb_agg(jsonb_build_object(
      'nickname', login_id,
      'name', name,
      'expected', jsonb_build_object(
        'missionCount', mission_count,
        'totalCards', total_cards,
        'raffleTicketCount', raffle_ticket_count,
        'activeTradeCount', active_trade_count,
        'lastActivityAt', last_activity_at
      ),
      'actual', jsonb_build_object(
        'missionCount', actual_mission_count,
        'totalCards', actual_total_cards,
        'raffleTicketCount', actual_raffle_ticket_count,
        'activeTradeCount', actual_active_trade_count,
        'lastActivityAt', actual_last_activity_at
      )
    ) order by login_id), '[]'::jsonb)
  into v_mismatch_count, v_mismatches
  from mismatch_rows;

  return jsonb_build_object(
    'ok', v_mismatch_count = 0,
    'source', 'supabase',
    'checkedLimit', v_limit,
    'mismatchCount', v_mismatch_count,
    'mismatches', v_mismatches,
    'admin', v_admin.login_id
  );
end;
$$;

drop trigger if exists sync_profiles_raffle_tickets on public.profiles;
create trigger sync_profiles_raffle_tickets
after insert or update of account_status, raffle_excluded on public.profiles
for each row execute function public.bu_sync_raffle_from_profile_trigger();

drop trigger if exists sync_user_cards_raffle_tickets on public.user_cards;
create trigger sync_user_cards_raffle_tickets
after insert or update or delete on public.user_cards
for each row execute function public.bu_sync_raffle_from_user_cards_trigger();

drop trigger if exists refresh_summary_from_events on public.events;
create trigger refresh_summary_from_events
after insert on public.events
for each row execute function public.bu_refresh_summary_from_event_trigger();

drop trigger if exists refresh_summary_from_mission_submissions on public.mission_submissions;
create trigger refresh_summary_from_mission_submissions
after insert or update or delete on public.mission_submissions
for each row execute function public.bu_refresh_summary_from_mission_submission_trigger();

drop trigger if exists refresh_summary_from_raffle_tickets on public.raffle_tickets;
create trigger refresh_summary_from_raffle_tickets
after insert or update or delete on public.raffle_tickets
for each row execute function public.bu_refresh_summary_from_raffle_ticket_trigger();

drop trigger if exists refresh_summary_from_trades on public.trades;
create trigger refresh_summary_from_trades
after insert or update or delete on public.trades
for each row execute function public.bu_refresh_summary_from_trade_trigger();

revoke all on function public.bu_refresh_profile_summary(uuid) from public, anon, authenticated;
revoke all on function public.bu_release_raffle_ticket_condition(uuid, text, text, text, uuid) from public, anon, authenticated;
revoke all on function public.bu_sync_raffle_from_profile_trigger() from public, anon, authenticated;
revoke all on function public.bu_sync_raffle_from_user_cards_trigger() from public, anon, authenticated;
revoke all on function public.bu_refresh_summary_from_event_trigger() from public, anon, authenticated;
revoke all on function public.bu_refresh_summary_from_mission_submission_trigger() from public, anon, authenticated;
revoke all on function public.bu_refresh_summary_from_raffle_ticket_trigger() from public, anon, authenticated;
revoke all on function public.bu_refresh_summary_from_trade_trigger() from public, anon, authenticated;
revoke all on function public.admin_audit_user_state(integer) from public, anon, authenticated;

grant execute on function public.admin_audit_user_state(integer) to authenticated;

commit;
