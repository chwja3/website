-- 관리자 카드 조정과 파생 상태 재계산을 Supabase RPC로 제공한다.
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

create or replace function public.admin_adjust_card(
  p_login_id text,
  p_card_id integer,
  p_amount integer default 1,
  p_mode text default 'grant',
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
  v_card public.cards%rowtype;
  v_mode text := lower(trim(coalesce(p_mode, 'grant')));
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_amount integer := coalesce(p_amount, 1);
  v_before integer := 0;
  v_after integer := 0;
  v_event_type text;
  v_event_amount integer;
  v_event_id uuid;
  v_collection jsonb := '{}'::jsonb;
  v_summary jsonb := '{}'::jsonb;
  v_raffle_sync jsonb := '{}'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  if nullif(trim(coalesce(p_login_id, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'missing_login_id');
  end if;

  select *
  into v_profile
  from public.profiles
  where login_id = trim(p_login_id)
    and account_status = 'active'
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'error', 'user_not_found');
  end if;

  select *
  into v_card
  from public.cards
  where id = p_card_id
  limit 1;

  if v_card.id is null then
    return jsonb_build_object('ok', false, 'error', 'card_not_found');
  end if;

  if v_amount < 1 or v_amount > 20 then
    return jsonb_build_object('ok', false, 'error', 'invalid_amount');
  end if;

  if v_mode in ('grant', 'add', 'card.granted') then
    v_mode := 'grant';
  elsif v_mode in ('remove', 'delete', 'card.removed') then
    v_mode := 'remove';
  else
    return jsonb_build_object('ok', false, 'error', 'invalid_mode');
  end if;

  perform pg_advisory_xact_lock(hashtext(v_profile.id::text), hashtext('admin_adjust_card'));

  select coalesce(quantity, 0)
  into v_before
  from public.user_cards
  where profile_id = v_profile.id
    and card_id = v_card.id
  for update;

  v_before := coalesce(v_before, 0);

  if v_mode = 'grant' then
    insert into public.user_cards (
      profile_id,
      card_id,
      quantity,
      first_obtained_at
    )
    values (
      v_profile.id,
      v_card.id,
      v_amount,
      now()
    )
    on conflict (profile_id, card_id) do update
    set quantity = public.user_cards.quantity + excluded.quantity,
        first_obtained_at = coalesce(public.user_cards.first_obtained_at, now()),
        updated_at = now()
    returning quantity into v_after;

    v_event_type := 'card.granted';
    v_event_amount := v_amount;
  else
    if v_before < v_amount then
      return jsonb_build_object(
        'ok', false,
        'error', 'insufficient_cards',
        'currentQty', v_before
      );
    end if;

    update public.user_cards
    set quantity = quantity - v_amount,
        updated_at = now()
    where profile_id = v_profile.id
      and card_id = v_card.id
    returning quantity into v_after;

    v_event_type := 'card.removed';
    v_event_amount := -v_amount;
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
    v_profile.id,
    v_event_type,
    'card',
    v_card.id::text,
    v_event_amount,
    jsonb_build_object(
      'cardName', v_card.name,
      'reason', coalesce(v_reason, case when v_mode = 'remove' then 'admin_card_remove' else 'admin_card_grant' end),
      'beforeQty', v_before,
      'afterQty', v_after
    ),
    'admin',
    v_admin.id
  )
  returning id into v_event_id;

  v_raffle_sync := public.bu_sync_profile_raffle_tickets(v_profile.id, 'admin', v_admin.id);
  v_summary := public.bu_refresh_profile_summary(v_profile.id);
  v_collection := public.bu_collection_counts(v_profile.id);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'eventId', v_event_id,
    'eventType', v_event_type,
    'cardId', v_card.id,
    'cardName', v_card.name,
    'beforeQty', v_before,
    'afterQty', v_after,
    'collection', v_collection,
    'summary', v_summary,
    'raffleSync', v_raffle_sync
  );
end;
$$;

create or replace function public.admin_rebuild_user_state(p_row_limit integer default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_limit integer := greatest(1, coalesce(p_row_limit, 1000000));
  v_checked integer := 0;
  v_mission_progress_rows integer := 0;
  v_collection_rows integer := 0;
  v_dashboard_rows integer := 0;
  v_raffle_sync jsonb := '{}'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  for v_profile in
    select *
    from public.profiles
    where account_status = 'active'
    order by participant_no nulls last, created_at, login_id
    limit v_limit
  loop
    perform public.bu_refresh_profile_summary(v_profile.id);
    v_raffle_sync := public.bu_sync_profile_raffle_tickets(v_profile.id, 'admin', v_admin.id);
    perform public.bu_refresh_profile_summary(v_profile.id);
    v_checked := v_checked + 1;
  end loop;

  select count(*)::integer
  into v_mission_progress_rows
  from public.mission_progress mp
  join public.profiles p on p.id = mp.profile_id and p.account_status = 'active';

  select count(*)::integer
  into v_collection_rows
  from public.user_cards uc
  join public.profiles p on p.id = uc.profile_id and p.account_status = 'active'
  where uc.quantity > 0;

  select count(*)::integer
  into v_dashboard_rows
  from public.user_summary us
  join public.profiles p on p.id = us.profile_id and p.account_status = 'active';

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'collectionRebuilt', v_checked,
    'missionProgressRebuilt', v_mission_progress_rows,
    'dashboardRows', v_dashboard_rows,
    'collectionRows', v_collection_rows,
    'lastRaffleSync', v_raffle_sync
  );
end;
$$;

revoke all on function public.bu_refresh_profile_summary(uuid) from public, anon, authenticated;
revoke all on function public.admin_adjust_card(text, integer, integer, text, text) from public, anon, authenticated;
revoke all on function public.admin_rebuild_user_state(integer) from public, anon, authenticated;

grant execute on function public.admin_adjust_card(text, integer, integer, text, text) to authenticated;
grant execute on function public.admin_rebuild_user_state(integer) to authenticated;

commit;
