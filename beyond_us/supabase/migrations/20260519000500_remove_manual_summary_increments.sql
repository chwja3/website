-- 미션 제출과 카드 뽑기 RPC의 수동 요약 증가를 제거한다.
begin;

create or replace function public.bu_hold_pray_cards_for_profile(
  p_profile_id uuid,
  p_week_key text
)
returns table (
  card_index integer,
  entry_id uuid,
  entry_profile_id uuid,
  content text,
  anonymous boolean,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with eligible_cards as (
    select
      hp.*,
      md5(p_profile_id::text || ':' || p_week_key || ':' || hp.id::text) as hp_sort_key
    from public.hold_pray_entries hp
    where hp.visible = true
      and coalesce(hp.week_key, p_week_key) = p_week_key
      and (hp.profile_id is null or hp.profile_id <> p_profile_id)
  ),
  picked_cards as (
    select *
    from eligible_cards
    order by hp_sort_key, created_at, id
    limit 3
  )
  select
    (row_number() over (order by pc.hp_sort_key, pc.created_at, pc.id) - 1)::integer as card_index,
    pc.id as entry_id,
    pc.profile_id as entry_profile_id,
    pc.content as content,
    pc.anonymous as anonymous,
    pc.updated_at as updated_at
  from picked_cards pc;
$$;

create or replace function public.submit_pre_mission(
  p_login_id text,
  p_week_key text,
  p_date_key text,
  p_items jsonb,
  p_request_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_auth_uid uuid := auth.uid();
  v_week_key text;
  v_week_title text;
  v_draw_threshold integer;
  v_date date;
  v_date_text text;
  v_request_id text := nullif(trim(coalesce(p_request_id, '')), '');
  v_existing_submission public.mission_submissions%rowtype;
  v_existing_ticket boolean := false;
  v_prev_total_score integer := 0;
  v_next_total_score integer := 0;
  v_prev_event_count integer := 0;
  v_next_event_count integer := 0;
  v_date_keys jsonb := '[]'::jsonb;
  v_next_date_keys jsonb := '[]'::jsonb;
  v_slot_counts jsonb := '{}'::jsonb;
  v_date_slot_indices jsonb := '{}'::jsonb;
  v_existing_today_indices integer[] := array[]::integer[];
  v_next_today_indices integer[] := array[]::integer[];
  v_saved_indices integer[] := array[]::integer[];
  v_saved_items text[] := array[]::text[];
  v_new_score integer := 0;
  v_idx integer;
  v_submission_id uuid;
  v_mission_event_id uuid;
  v_ticket_earned boolean := false;
  v_already_ticket_earned boolean := false;
begin
  if nullif(trim(coalesce(p_login_id, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'missing_userId');
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'invalid_items');
  end if;

  begin
    v_date := coalesce(nullif(trim(coalesce(p_date_key, '')), '')::date, (now() at time zone 'Asia/Seoul')::date);
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'invalid_date');
  end;
  v_date_text := to_char(v_date, 'YYYY-MM-DD');

  select *
  into v_profile
  from public.profiles
  where login_id = p_login_id
    and account_status = 'active'
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'error', 'inactive_user');
  end if;

  if v_auth_uid is null or v_profile.auth_user_id is distinct from v_auth_uid then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;

  v_week_key := nullif(trim(coalesce(p_week_key, '')), '');
  if v_week_key is null then
    v_week_key := 'w' || public.bu_current_week()::text;
  end if;

  select week_key, title, draw_threshold
  into v_week_key, v_week_title, v_draw_threshold
  from public.mission_weeks
  where week_key = v_week_key
    and enabled = true
  limit 1;

  if v_week_key is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_week');
  end if;

  v_draw_threshold := coalesce(v_draw_threshold, 6);

  perform pg_advisory_xact_lock(hashtext(v_profile.id::text), hashtext(v_week_key));

  if v_request_id is not null then
    select *
    into v_existing_submission
    from public.mission_submissions
    where profile_id = v_profile.id
      and request_id = v_request_id
    limit 1;

    if v_existing_submission.id is not null then
      select exists(
        select 1
        from public.events
        where profile_id = v_profile.id
          and event_type = 'ticket.granted'
          and request_id = v_request_id
      )
      into v_existing_ticket;

      select coalesce(total_score, 0)
      into v_next_total_score
      from public.mission_progress
      where profile_id = v_profile.id
        and week_key = v_existing_submission.week_key;

      return jsonb_build_object(
        'ok', true,
        'source', 'supabase',
        'idempotent', true,
        'savedItems', coalesce(v_existing_submission.items_json, '[]'::jsonb),
        'savedIndices', coalesce(v_existing_submission.indices_json, '[]'::jsonb),
        'newScore', coalesce(v_existing_submission.score, 0),
        'weekScore', coalesce(v_next_total_score, 0),
        'ticketEarned', coalesce(v_existing_ticket, false),
        'dateKey', to_char(v_existing_submission.date_key, 'YYYY-MM-DD'),
        'weekKey', v_existing_submission.week_key
      );
    end if;
  end if;

  select
    coalesce(total_score, 0),
    coalesce(date_keys, '[]'::jsonb),
    coalesce(slot_counts, '{}'::jsonb),
    coalesce(date_slot_indices, '{}'::jsonb),
    coalesce(submission_event_count, 0)
  into v_prev_total_score, v_date_keys, v_slot_counts, v_date_slot_indices, v_prev_event_count
  from public.mission_progress
  where profile_id = v_profile.id
    and week_key = v_week_key
  for update;

  v_prev_total_score := coalesce(v_prev_total_score, 0);
  v_date_keys := coalesce(v_date_keys, '[]'::jsonb);
  v_slot_counts := coalesce(v_slot_counts, '{}'::jsonb);
  v_date_slot_indices := coalesce(v_date_slot_indices, '{}'::jsonb);
  v_prev_event_count := coalesce(v_prev_event_count, 0);

  if jsonb_typeof(v_date_slot_indices) = 'object'
     and v_date_slot_indices ? v_date_text
     and jsonb_typeof(v_date_slot_indices -> v_date_text) = 'array' then
    select coalesce(array_agg(value::integer order by value::integer), array[]::integer[])
    into v_existing_today_indices
    from jsonb_array_elements_text(v_date_slot_indices -> v_date_text);
  end if;
  v_existing_today_indices := coalesce(v_existing_today_indices, array[]::integer[]);

  with requested as (
    select distinct trim(value) as item_text
    from jsonb_array_elements_text(p_items) as raw(value)
    where nullif(trim(value), '') is not null
  ),
  valid_items as (
    select
      mi.item_no - 1 as item_index,
      mi.item_text,
      mi.score_weight
    from requested r
    join public.mission_items mi
      on mi.week_key = v_week_key
     and mi.enabled = true
     and mi.item_text = r.item_text
  ),
  new_items as (
    select *
    from valid_items
    where not (item_index = any(v_existing_today_indices))
  )
  select
    coalesce(array_agg(item_index order by item_index), array[]::integer[]),
    coalesce(array_agg(item_text order by item_index), array[]::text[]),
    coalesce(sum(score_weight), 0)::integer
  into v_saved_indices, v_saved_items, v_new_score
  from new_items;

  v_saved_indices := coalesce(v_saved_indices, array[]::integer[]);
  v_saved_items := coalesce(v_saved_items, array[]::text[]);
  v_new_score := coalesce(v_new_score, 0);

  if coalesce(array_length(v_saved_indices, 1), 0) = 0 then
    return jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'savedItems', '[]'::jsonb,
      'savedIndices', '[]'::jsonb,
      'newScore', 0,
      'weekScore', v_prev_total_score,
      'ticketEarned', false,
      'dateKey', v_date_text,
      'weekKey', v_week_key
    );
  end if;

  select coalesce(array_agg(value order by value), array[]::integer[])
  into v_next_today_indices
  from (
    select unnest(v_existing_today_indices) as value
    union
    select unnest(v_saved_indices) as value
  ) unioned;
  v_next_today_indices := coalesce(v_next_today_indices, array[]::integer[]);

  foreach v_idx in array v_saved_indices loop
    v_slot_counts := jsonb_set(
      v_slot_counts,
      array[v_idx::text],
      to_jsonb(coalesce((v_slot_counts ->> v_idx::text)::integer, 0) + 1),
      true
    );
  end loop;

  select coalesce(jsonb_agg(value order by value), '[]'::jsonb)
  into v_next_date_keys
  from (
    select jsonb_array_elements_text(v_date_keys) as value
    union
    select v_date_text as value
  ) unioned;

  v_date_slot_indices := jsonb_set(v_date_slot_indices, array[v_date_text], to_jsonb(v_next_today_indices), true);
  v_next_total_score := v_prev_total_score + v_new_score;
  v_next_event_count := v_prev_event_count + 1;

  insert into public.mission_submissions (
    profile_id,
    week_key,
    date_key,
    score,
    items_json,
    indices_json,
    request_id
  )
  values (
    v_profile.id,
    v_week_key,
    v_date,
    v_new_score,
    to_jsonb(v_saved_items),
    to_jsonb(v_saved_indices),
    v_request_id
  )
  returning id into v_submission_id;

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    ref_id,
    amount,
    week_key,
    payload,
    source,
    request_id
  )
  values (
    v_profile.id,
    'mission.submitted',
    'mission',
    v_submission_id::text,
    v_new_score,
    v_week_key,
    jsonb_build_object(
      'weekTitle', v_week_title,
      'dateKey', v_date_text,
      'score', v_new_score,
      'weekCumScore', v_next_total_score,
      'items', to_jsonb(v_saved_items),
      'indices', to_jsonb(v_saved_indices)
    ),
    'web',
    v_request_id
  )
  returning id into v_mission_event_id;

  insert into public.mission_progress (
    profile_id,
    week_key,
    total_score,
    date_keys,
    slot_counts,
    date_slot_indices,
    submission_event_count
  )
  values (
    v_profile.id,
    v_week_key,
    v_next_total_score,
    v_next_date_keys,
    v_slot_counts,
    v_date_slot_indices,
    v_next_event_count
  )
  on conflict (profile_id, week_key) do update
  set total_score = excluded.total_score,
      date_keys = excluded.date_keys,
      slot_counts = excluded.slot_counts,
      date_slot_indices = excluded.date_slot_indices,
      submission_event_count = excluded.submission_event_count,
      updated_at = now();

  select exists(
    select 1
    from public.events
    where profile_id = v_profile.id
      and event_type = 'ticket.granted'
      and week_key = v_week_key
      and payload ->> 'reason' = 'mission_week_threshold'
  )
  into v_already_ticket_earned;

  if v_draw_threshold > 0
     and v_prev_total_score < v_draw_threshold
     and v_next_total_score >= v_draw_threshold
     and not coalesce(v_already_ticket_earned, false) then
    insert into public.events (
      profile_id,
      event_type,
      ref_type,
      ref_id,
      amount,
      week_key,
      payload,
      source,
      request_id
    )
    values (
      v_profile.id,
      'ticket.granted',
      'mission',
      v_mission_event_id::text,
      1,
      v_week_key,
      jsonb_build_object(
        'reason', 'mission_week_threshold',
        'weekTitle', v_week_title,
        'score', v_next_total_score,
        'threshold', v_draw_threshold
      ),
      'web',
      v_request_id
    );

    insert into public.user_inventory (
      profile_id,
      normal_pack_earned,
      normal_pack_remaining
    )
    values (v_profile.id, 1, 1)
    on conflict (profile_id) do update
    set normal_pack_earned = public.user_inventory.normal_pack_earned + 1,
        normal_pack_remaining = public.user_inventory.normal_pack_remaining + 1,
        updated_at = now();

    v_ticket_earned := true;
  end if;

  perform public.bu_refresh_profile_summary(v_profile.id);

  update public.user_summary
  set payload = coalesce(payload, '{}'::jsonb)
        || jsonb_build_object('lastMissionSubmissionId', v_submission_id),
      updated_at = now()
  where profile_id = v_profile.id;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'savedItems', to_jsonb(v_saved_items),
    'savedIndices', to_jsonb(v_saved_indices),
    'newScore', v_new_score,
    'weekScore', v_next_total_score,
    'ticketEarned', v_ticket_earned,
    'dateKey', v_date_text,
    'weekKey', v_week_key
  );
end;
$$;

create or replace function public.draw_card_pack(
  p_login_id text,
  p_week_key text default null,
  p_pack_type text default 'normal',
  p_request_id text default null,
  p_test_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_inventory public.user_inventory%rowtype;
  v_week_key text := nullif(trim(coalesce(p_week_key, '')), '');
  v_pack_type text := case when lower(coalesce(p_pack_type, 'normal')) = 'special' then 'special' else 'normal' end;
  v_request_id text := nullif(trim(coalesce(p_request_id, '')), '');
  v_card public.cards%rowtype;
  v_is_new boolean := true;
  v_collection jsonb := '{}'::jsonb;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  v_week_key := coalesce(v_week_key, 'w' || public.bu_current_week()::text);

  perform pg_advisory_xact_lock(hashtext(v_profile.id::text), hashtext('draw_card_pack'));

  insert into public.user_inventory (profile_id)
  values (v_profile.id)
  on conflict (profile_id) do nothing;

  select *
  into v_inventory
  from public.user_inventory
  where profile_id = v_profile.id
  for update;

  if v_pack_type = 'normal' and p_test_mode = true and v_profile.is_dev = true then
    update public.user_inventory
    set normal_pack_earned = normal_pack_earned + 1,
        normal_pack_remaining = normal_pack_remaining + 1,
        updated_at = now()
    where profile_id = v_profile.id
    returning * into v_inventory;

    insert into public.events (
      profile_id,
      event_type,
      ref_type,
      amount,
      week_key,
      payload,
      source,
      request_id
    )
    values (
      v_profile.id,
      'ticket.granted',
      'dev',
      1,
      v_week_key,
      jsonb_build_object('reason', 'dev_test_draw'),
      'dev',
      v_request_id
    );
  end if;

  if v_pack_type = 'special' then
    if coalesce(v_inventory.special_pack_remaining, 0) <= 0 then
      return jsonb_build_object('ok', false, 'error', 'no_ticket', 'message', '사용 가능한 카드팩이 없어요.');
    end if;

    select c.*
    into v_card
    from public.cards c
    where c.id between 1 and 9
      and c.enabled = true
      and not exists (
        select 1
        from public.user_cards uc
        where uc.profile_id = v_profile.id
          and uc.card_id = c.id
          and uc.quantity > 0
      )
    order by random()
    limit 1;

    if v_card.id is null then
      select c.*
      into v_card
      from public.cards c
      where c.id between 1 and 9
        and c.enabled = true
      order by random()
      limit 1;
    end if;
  else
    if coalesce(v_inventory.normal_pack_remaining, 0) <= 0 then
      return jsonb_build_object('ok', false, 'error', 'no_ticket', 'message', '사용 가능한 카드팩이 없어요.');
    end if;

    select c.*
    into v_card
    from public.cards c
    where c.id between 1 and 9
      and c.enabled = true
    order by random()
    limit 1;
  end if;

  if v_card.id is null then
    return jsonb_build_object('ok', false, 'error', 'no_card_candidates');
  end if;

  select not exists(
    select 1
    from public.user_cards
    where profile_id = v_profile.id
      and card_id = v_card.id
      and quantity > 0
  )
  into v_is_new;

  if v_pack_type = 'special' then
    update public.user_inventory
    set special_pack_consumed = special_pack_consumed + 1,
        special_pack_remaining = greatest(0, special_pack_remaining - 1),
        updated_at = now()
    where profile_id = v_profile.id
    returning * into v_inventory;

    insert into public.events (
      profile_id,
      event_type,
      ref_type,
      amount,
      week_key,
      payload,
      source,
      request_id
    )
    values (
      v_profile.id,
      'special_pack.consumed',
      'special_pack',
      -1,
      v_week_key,
      jsonb_build_object('packType', v_pack_type),
      'web',
      v_request_id
    );
  else
    update public.user_inventory
    set normal_pack_consumed = normal_pack_consumed + 1,
        normal_pack_remaining = greatest(0, normal_pack_remaining - 1),
        updated_at = now()
    where profile_id = v_profile.id
    returning * into v_inventory;

    insert into public.events (
      profile_id,
      event_type,
      ref_type,
      amount,
      week_key,
      payload,
      source,
      request_id
    )
    values (
      v_profile.id,
      'ticket.consumed',
      'ticket',
      -1,
      v_week_key,
      jsonb_build_object('packType', v_pack_type),
      'web',
      v_request_id
    );
  end if;

  insert into public.user_cards (
    profile_id,
    card_id,
    quantity,
    first_obtained_at
  )
  values (
    v_profile.id,
    v_card.id,
    1,
    now()
  )
  on conflict (profile_id, card_id) do update
  set quantity = public.user_cards.quantity + 1,
      first_obtained_at = coalesce(public.user_cards.first_obtained_at, now()),
      updated_at = now();

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    ref_id,
    amount,
    week_key,
    payload,
    source,
    request_id
  )
  values (
    v_profile.id,
    'card.drawn',
    'card',
    v_card.id::text,
    1,
    v_week_key,
    jsonb_build_object('cardName', v_card.name, 'isNew', v_is_new, 'packType', v_pack_type),
    'web',
    v_request_id
  );

  perform public.bu_refresh_profile_summary(v_profile.id);

  update public.user_summary
  set payload = coalesce(payload, '{}'::jsonb)
        || jsonb_build_object('lastDrawnCardId', v_card.id),
      updated_at = now()
  where profile_id = v_profile.id;

  v_collection := public.bu_collection_counts(v_profile.id);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'card', jsonb_build_object('id', v_card.id, 'name', v_card.name),
    'isNew', v_is_new,
    'collection', v_collection,
    'tickets', jsonb_build_object(
      'earned', v_inventory.normal_pack_earned,
      'consumed', v_inventory.normal_pack_consumed,
      'remaining', v_inventory.normal_pack_remaining
    ),
    'specialPacks', jsonb_build_object(
      'earned', v_inventory.special_pack_earned,
      'consumed', v_inventory.special_pack_consumed,
      'remaining', v_inventory.special_pack_remaining
    ),
    'specialPacksRemaining', v_inventory.special_pack_remaining
  );
end;
$$;

do $$
declare
  v_profile_id uuid;
begin
  for v_profile_id in
    select id
    from public.profiles
    where account_status = 'active'
  loop
    perform public.bu_sync_profile_raffle_tickets(v_profile_id, 'server', null);
    perform public.bu_refresh_profile_summary(v_profile_id);
  end loop;
end;
$$;

grant execute on function public.submit_pre_mission(text, text, text, jsonb, text) to authenticated;
grant execute on function public.draw_card_pack(text, text, text, text, boolean) to authenticated;

commit;
