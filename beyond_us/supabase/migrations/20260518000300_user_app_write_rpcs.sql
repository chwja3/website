-- 사용자 앱의 비파일 쓰기 경로를 Supabase RPC로 처리하는 함수 모음
begin;

create or replace function public.bu_collection_counts(p_profile_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(jsonb_object_agg(card_id::text, quantity order by card_id), '{}'::jsonb)
  from public.user_cards
  where profile_id = p_profile_id
    and quantity > 0;
$$;

create or replace function public.bu_auth_profile(p_login_id text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_auth_uid uuid := auth.uid();
begin
  select *
  into v_profile
  from public.profiles
  where login_id = p_login_id
    and account_status = 'active'
  limit 1;

  if v_profile.id is null then
    raise exception 'inactive_user' using errcode = 'P0001';
  end if;

  if v_auth_uid is null or v_profile.auth_user_id is distinct from v_auth_uid then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  return v_profile;
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

  insert into public.user_summary (
    profile_id,
    total_cards,
    last_activity_at,
    payload
  )
  values (
    v_profile.id,
    1,
    now(),
    jsonb_build_object('lastDrawnCardId', v_card.id)
  )
  on conflict (profile_id) do update
  set total_cards = public.user_summary.total_cards + 1,
      last_activity_at = now(),
      payload = coalesce(public.user_summary.payload, '{}'::jsonb)
        || jsonb_build_object('lastDrawnCardId', v_card.id),
      updated_at = now();

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

create or replace function public.get_public_collection(p_login_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  select *
  into v_profile
  from public.profiles
  where login_id = p_login_id
    and account_status = 'active'
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'nickname', v_profile.login_id,
    'collection', public.bu_collection_counts(v_profile.id)
  );
end;
$$;

create or replace function public.get_user_trades(p_login_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_incoming jsonb := '[]'::jsonb;
  v_outgoing jsonb := '[]'::jsonb;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  with trade_rows as (
    select
      t.*,
      rp.login_id as requester_login_id,
      tp.login_id as target_login_id,
      rc.name as requester_card_name,
      tc.name as target_card_name,
      exists(select 1 from public.trade_prayers pr where pr.trade_id = t.id and pr.profile_id = t.requester_id) as requester_prayed,
      exists(select 1 from public.trade_prayers pr where pr.trade_id = t.id and pr.profile_id = t.target_id) as target_prayed
    from public.trades t
    join public.profiles rp on rp.id = t.requester_id
    join public.profiles tp on tp.id = t.target_id
    join public.cards rc on rc.id = t.requester_card_id
    join public.cards tc on tc.id = t.target_card_id
    where t.target_id = v_profile.id
    order by t.created_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'status', case when status::text = 'requested' then 'pending' else status::text end,
    'requester', requester_login_id,
    'target', target_login_id,
    'requesterCardId', requester_card_id,
    'targetCardId', target_card_id,
    'requesterCardName', requester_card_name,
    'targetCardName', target_card_name,
    'requesterPrayed', requester_prayed,
    'targetPrayed', target_prayed,
    'otherPrayer', '',
    'createdAt', created_at,
    'resolvedAt', resolved_at
  ) order by created_at desc), '[]'::jsonb)
  into v_incoming
  from trade_rows;

  with trade_rows as (
    select
      t.*,
      rp.login_id as requester_login_id,
      tp.login_id as target_login_id,
      rc.name as requester_card_name,
      tc.name as target_card_name,
      exists(select 1 from public.trade_prayers pr where pr.trade_id = t.id and pr.profile_id = t.requester_id) as requester_prayed,
      exists(select 1 from public.trade_prayers pr where pr.trade_id = t.id and pr.profile_id = t.target_id) as target_prayed
    from public.trades t
    join public.profiles rp on rp.id = t.requester_id
    join public.profiles tp on tp.id = t.target_id
    join public.cards rc on rc.id = t.requester_card_id
    join public.cards tc on tc.id = t.target_card_id
    where t.requester_id = v_profile.id
    order by t.created_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'status', case when status::text = 'requested' then 'pending' else status::text end,
    'requester', requester_login_id,
    'target', target_login_id,
    'requesterCardId', requester_card_id,
    'targetCardId', target_card_id,
    'requesterCardName', requester_card_name,
    'targetCardName', target_card_name,
    'requesterPrayed', requester_prayed,
    'targetPrayed', target_prayed,
    'otherPrayer', '',
    'createdAt', created_at,
    'resolvedAt', resolved_at
  ) order by created_at desc), '[]'::jsonb)
  into v_outgoing
  from trade_rows;

  return jsonb_build_object('ok', true, 'source', 'supabase', 'incoming', v_incoming, 'outgoing', v_outgoing);
end;
$$;

create or replace function public.request_trade(
  p_login_id text,
  p_target_login_id text,
  p_requester_card_id integer,
  p_target_card_id integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_trade_id uuid;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  select *
  into v_target
  from public.profiles
  where login_id = p_target_login_id
    and account_status = 'active'
  limit 1;

  if v_target.id is null then
    return jsonb_build_object('ok', false, 'error', 'target_not_found');
  end if;

  if v_target.id = v_profile.id then
    return jsonb_build_object('ok', false, 'error', 'self_trade_not_allowed');
  end if;

  if not exists (
    select 1 from public.user_cards
    where profile_id = v_profile.id and card_id = p_requester_card_id and quantity >= 2
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_enough_requester_card');
  end if;

  if not exists (
    select 1 from public.user_cards
    where profile_id = v_target.id and card_id = p_target_card_id and quantity >= 2
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_enough_target_card');
  end if;

  insert into public.trades (
    requester_id,
    requester_card_id,
    target_id,
    target_card_id
  )
  values (
    v_profile.id,
    p_requester_card_id,
    v_target.id,
    p_target_card_id
  )
  returning id into v_trade_id;

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    ref_id,
    payload,
    source
  )
  values (
    v_profile.id,
    'trade.requested',
    'trade',
    v_trade_id::text,
    jsonb_build_object('targetUserId', v_target.login_id, 'requesterCardId', p_requester_card_id, 'targetCardId', p_target_card_id),
    'web'
  );

  return jsonb_build_object('ok', true, 'source', 'supabase', 'id', v_trade_id);
end;
$$;

create or replace function public.accept_trade(p_login_id text, p_trade_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_trade public.trades%rowtype;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  select *
  into v_trade
  from public.trades
  where id = p_trade_id
  for update;

  if v_trade.id is null or v_trade.target_id <> v_profile.id then
    return jsonb_build_object('ok', false, 'error', 'trade_not_found');
  end if;

  if v_trade.status <> 'requested' then
    return jsonb_build_object('ok', false, 'error', 'trade_not_pending');
  end if;

  perform 1
  from public.user_cards
  where profile_id = v_trade.requester_id
    and card_id = v_trade.requester_card_id
    and quantity > 0
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'requester_card_missing');
  end if;

  perform 1
  from public.user_cards
  where profile_id = v_trade.target_id
    and card_id = v_trade.target_card_id
    and quantity > 0
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'target_card_missing');
  end if;

  update public.user_cards
  set quantity = quantity - 1,
      updated_at = now()
  where profile_id = v_trade.requester_id
    and card_id = v_trade.requester_card_id
    and quantity > 0;

  update public.user_cards
  set quantity = quantity - 1,
      updated_at = now()
  where profile_id = v_trade.target_id
    and card_id = v_trade.target_card_id
    and quantity > 0;

  insert into public.user_cards (profile_id, card_id, quantity, first_obtained_at)
  values (v_trade.requester_id, v_trade.target_card_id, 1, now())
  on conflict (profile_id, card_id) do update
  set quantity = public.user_cards.quantity + 1,
      first_obtained_at = coalesce(public.user_cards.first_obtained_at, now()),
      updated_at = now();

  insert into public.user_cards (profile_id, card_id, quantity, first_obtained_at)
  values (v_trade.target_id, v_trade.requester_card_id, 1, now())
  on conflict (profile_id, card_id) do update
  set quantity = public.user_cards.quantity + 1,
      first_obtained_at = coalesce(public.user_cards.first_obtained_at, now()),
      updated_at = now();

  update public.trades
  set status = 'accepted',
      resolved_at = now()
  where id = v_trade.id;

  insert into public.events (profile_id, event_type, ref_type, ref_id, payload, source)
  values (v_profile.id, 'trade.accepted', 'trade', v_trade.id::text, '{}'::jsonb, 'web');

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

create or replace function public.reject_trade(p_login_id text, p_trade_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  update public.trades
  set status = 'rejected',
      resolved_at = now()
  where id = p_trade_id
    and target_id = v_profile.id
    and status = 'requested';

  if not found then
    return jsonb_build_object('ok', false, 'error', 'trade_not_found');
  end if;

  insert into public.events (profile_id, event_type, ref_type, ref_id, payload, source)
  values (v_profile.id, 'trade.rejected', 'trade', p_trade_id::text, '{}'::jsonb, 'web');

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

create or replace function public.cancel_trade(p_login_id text, p_trade_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  update public.trades
  set status = 'cancelled',
      resolved_at = now()
  where id = p_trade_id
    and requester_id = v_profile.id
    and status = 'requested';

  if not found then
    return jsonb_build_object('ok', false, 'error', 'trade_not_found');
  end if;

  insert into public.events (profile_id, event_type, ref_type, ref_id, payload, source)
  values (v_profile.id, 'trade.cancelled', 'trade', p_trade_id::text, '{}'::jsonb, 'web');

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

create or replace function public.pray_for_trade(p_login_id text, p_trade_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if not exists (
    select 1
    from public.trades
    where id = p_trade_id
      and status = 'accepted'
      and (requester_id = v_profile.id or target_id = v_profile.id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'trade_not_found');
  end if;

  insert into public.trade_prayers (trade_id, profile_id)
  values (p_trade_id, v_profile.id)
  on conflict (trade_id, profile_id) do nothing;

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

create or replace function public.get_my_inquiries(p_login_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_items jsonb := '[]'::jsonb;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'nickname', v_profile.login_id,
    'content', content,
    'reply', coalesce(reply, ''),
    'createdAt', created_at,
    'status', status
  ) order by created_at desc), '[]'::jsonb)
  into v_items
  from public.inquiries
  where profile_id = v_profile.id;

  return jsonb_build_object('ok', true, 'source', 'supabase', 'inquiries', v_items);
end;
$$;

create or replace function public.create_inquiry(p_login_id text, p_content text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_id uuid;
  v_content text := trim(coalesce(p_content, ''));
begin
  v_profile := public.bu_auth_profile(p_login_id);
  if v_content = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_content');
  end if;

  insert into public.inquiries (profile_id, content)
  values (v_profile.id, v_content)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'source', 'supabase', 'id', v_id);
end;
$$;

create or replace function public.update_inquiry(p_login_id text, p_id uuid, p_content text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_content text := trim(coalesce(p_content, ''));
begin
  v_profile := public.bu_auth_profile(p_login_id);
  if v_content = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_content');
  end if;

  update public.inquiries
  set content = v_content,
      updated_at = now()
  where id = p_id
    and profile_id = v_profile.id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

create or replace function public.delete_inquiry(p_login_id text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  delete from public.inquiries
  where id = p_id
    and profile_id = v_profile.id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

create or replace function public.get_bbb_messages(p_login_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_messages jsonb := '[]'::jsonb;
  v_sent jsonb := '[]'::jsonb;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'fromUserId', fp.login_id,
    'toUserId', tp.login_id,
    'message', m.message,
    'createdAt', m.created_at
  ) order by m.created_at asc), '[]'::jsonb)
  into v_messages
  from public.bbb_messages m
  join public.profiles fp on fp.id = m.from_profile_id
  join public.profiles tp on tp.id = m.to_profile_id
  where m.to_profile_id = v_profile.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'fromUserId', fp.login_id,
    'toUserId', tp.login_id,
    'message', m.message,
    'createdAt', m.created_at
  ) order by m.created_at asc), '[]'::jsonb)
  into v_sent
  from public.bbb_messages m
  join public.profiles fp on fp.id = m.from_profile_id
  join public.profiles tp on tp.id = m.to_profile_id
  where m.from_profile_id = v_profile.id;

  return jsonb_build_object('ok', true, 'source', 'supabase', 'messages', v_messages, 'sent', v_sent);
end;
$$;

create or replace function public.send_bbb_message(p_login_id text, p_message text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_to_profile_id uuid;
  v_message text := trim(coalesce(p_message, ''));
  v_id uuid;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  if v_message = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_message');
  end if;

  select care_buddy_id
  into v_to_profile_id
  from public.bbb_assignments
  where profile_id = v_profile.id;

  if v_to_profile_id is null then
    return jsonb_build_object('ok', false, 'error', 'no_match');
  end if;

  insert into public.bbb_messages (from_profile_id, to_profile_id, message)
  values (v_profile.id, v_to_profile_id, v_message)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'source', 'supabase', 'id', v_id);
end;
$$;

create or replace function public.guess_bbb_secret(p_login_id text, p_guess text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_assignment public.bbb_assignments%rowtype;
  v_secret public.profiles%rowtype;
  v_guess text := lower(trim(coalesce(p_guess, '')));
  v_correct boolean := false;
  v_rewarded boolean := false;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  if v_guess = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_guess');
  end if;

  select *
  into v_assignment
  from public.bbb_assignments
  where profile_id = v_profile.id
  for update;

  if v_assignment.profile_id is null or v_assignment.secret_buddy_id is null then
    return jsonb_build_object('ok', false, 'error', 'no_match');
  end if;

  select *
  into v_secret
  from public.profiles
  where id = v_assignment.secret_buddy_id;

  v_correct := v_guess in (
    lower(coalesce(v_secret.login_id, '')),
    lower(coalesce(v_secret.name, '')),
    lower(coalesce(v_secret.display_name, ''))
  );

  if not v_correct then
    return jsonb_build_object('ok', true, 'source', 'supabase', 'correct', false);
  end if;

  if v_assignment.secret_revealed = false then
    update public.bbb_assignments
    set secret_revealed = true,
        updated_at = now()
    where profile_id = v_profile.id;

    insert into public.user_inventory (
      profile_id,
      special_pack_earned,
      special_pack_remaining
    )
    values (v_profile.id, 1, 1)
    on conflict (profile_id) do update
    set special_pack_earned = public.user_inventory.special_pack_earned + 1,
        special_pack_remaining = public.user_inventory.special_pack_remaining + 1,
        updated_at = now();

    insert into public.events (
      profile_id,
      event_type,
      ref_type,
      amount,
      payload,
      source
    )
    values (
      v_profile.id,
      'special_pack.granted',
      'bbb_secret',
      1,
      jsonb_build_object('reason', 'bbb_secret_guess', 'secretBuddyId', v_secret.login_id),
      'web'
    );

    v_rewarded := true;
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'correct', true,
    'rewarded', v_rewarded,
    'alreadyRevealed', not v_rewarded,
    'secretName', coalesce(v_secret.display_name, v_secret.name, v_secret.login_id),
    'secretNickname', v_secret.login_id
  );
end;
$$;

grant execute on function public.bu_collection_counts(uuid) to authenticated;
grant execute on function public.bu_auth_profile(text) to authenticated;
grant execute on function public.draw_card_pack(text, text, text, text, boolean) to authenticated;
grant execute on function public.get_public_collection(text) to authenticated;
grant execute on function public.get_user_trades(text) to authenticated;
grant execute on function public.request_trade(text, text, integer, integer) to authenticated;
grant execute on function public.accept_trade(text, uuid) to authenticated;
grant execute on function public.reject_trade(text, uuid) to authenticated;
grant execute on function public.cancel_trade(text, uuid) to authenticated;
grant execute on function public.pray_for_trade(text, uuid) to authenticated;
grant execute on function public.get_my_inquiries(text) to authenticated;
grant execute on function public.create_inquiry(text, text) to authenticated;
grant execute on function public.update_inquiry(text, uuid, text) to authenticated;
grant execute on function public.delete_inquiry(text, uuid) to authenticated;
grant execute on function public.get_bbb_messages(text) to authenticated;
grant execute on function public.send_bbb_message(text, text) to authenticated;
grant execute on function public.guess_bbb_secret(text, text) to authenticated;

commit;
