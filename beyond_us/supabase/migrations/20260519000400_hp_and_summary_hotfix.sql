-- H&P 서버 오류와 사용자 요약 과집계를 함께 보정한다.
begin;

alter table public.hold_pray_hints
  add column if not exists hold_pray_entry_id uuid references public.hold_pray_entries(id) on delete cascade;

create index if not exists idx_hold_pray_hints_entry
  on public.hold_pray_hints(hold_pray_entry_id);

create or replace function public.bu_korean_initials(p_text text)
returns text
language plpgsql
immutable
as $$
declare
  v_text text := coalesce(p_text, '');
  v_initials text[] := array[
    chr(12593), chr(12594), chr(12596), chr(12599), chr(12600),
    chr(12601), chr(12609), chr(12610), chr(12611), chr(12613),
    chr(12614), chr(12615), chr(12616), chr(12617), chr(12618),
    chr(12619), chr(12620), chr(12621), chr(12622)
  ];
  v_result text := '';
  v_char text;
  v_code integer;
  i integer;
begin
  if btrim(v_text) = '' then
    return null;
  end if;

  for i in 1..char_length(v_text) loop
    v_char := substr(v_text, i, 1);
    if btrim(v_char) = '' then
      continue;
    end if;

    v_code := ascii(v_char);
    if v_code between 44032 and 55203 then
      v_result := v_result || v_initials[(floor((v_code - 44032)::numeric / 588)::integer) + 1];
    elsif v_char ~ '^[A-Za-z0-9]$' then
      v_result := v_result || upper(v_char);
    else
      v_result := v_result || v_char;
    end if;
  end loop;

  return nullif(v_result, '');
end;
$$;

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
    (row_number() over (order by hp_sort_key, created_at, id) - 1)::integer as card_index,
    id as entry_id,
    profile_id as entry_profile_id,
    content,
    anonymous,
    updated_at
  from picked_cards;
$$;

create or replace function public.get_hold_pray(
  p_login_id text,
  p_week_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_week_key text := nullif(trim(coalesce(p_week_key, '')), '');
  v_cards jsonb := '[]'::jsonb;
  v_correct_map jsonb := '{}'::jsonb;
  v_revision text := '';
  v_ticket_awarded boolean := false;
  v_ticket_idx integer := -1;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  v_week_key := coalesce(v_week_key, 'w' || public.bu_current_week()::text);

  select
    coalesce(jsonb_agg(jsonb_build_object(
      'content', hpc.content,
      'anon', hpc.anonymous
    ) order by hpc.card_index), '[]'::jsonb),
    coalesce(max(hpc.updated_at)::text, '')
  into v_cards, v_revision
  from public.bu_hold_pray_cards_for_profile(v_profile.id, v_week_key) hpc;

  select coalesce(jsonb_object_agg(g.card_index::text, g.guessed_name), '{}'::jsonb)
  into v_correct_map
  from public.hold_pray_guesses g
  join public.bu_hold_pray_cards_for_profile(v_profile.id, v_week_key) hpc
    on hpc.card_index = g.card_index
  left join public.profiles owner on owner.id = hpc.entry_profile_id
  where g.profile_id = v_profile.id
    and g.week_key = v_week_key
    and g.correct = true
    and hpc.anonymous = false
    and lower(g.guessed_name) in (
      lower(coalesce(owner.login_id, '')),
      lower(coalesce(owner.name, '')),
      lower(coalesce(owner.display_name, ''))
    );

  select exists(
    select 1
    from public.events
    where profile_id = v_profile.id
      and event_type = 'ticket.granted'
      and ref_type = 'hold_pray'
      and week_key = v_week_key
  )
  into v_ticket_awarded;

  select case
    when (payload ->> 'cardIndex') ~ '^-?[0-9]+$' then (payload ->> 'cardIndex')::integer
    else -1
  end
  into v_ticket_idx
  from public.events
  where profile_id = v_profile.id
    and event_type = 'ticket.granted'
    and ref_type = 'hold_pray'
    and week_key = v_week_key
  order by occurred_at desc
  limit 1;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'weekKey', v_week_key,
    'hpRevision', v_revision,
    'cards', coalesce(v_cards, '[]'::jsonb),
    'correctMap', coalesce(v_correct_map, '{}'::jsonb),
    'ticketAlreadyAwarded', coalesce(v_ticket_awarded, false),
    'ticketCardIdx', coalesce(v_ticket_idx, -1),
    'hintReplies', '{}'::jsonb
  );
end;
$$;

create or replace function public.submit_hold_pray_guess(
  p_login_id text,
  p_week_key text,
  p_card_index integer,
  p_guess text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_week_key text := coalesce(nullif(trim(coalesce(p_week_key, '')), ''), 'w' || public.bu_current_week()::text);
  v_guess text := trim(coalesce(p_guess, ''));
  v_entry record;
  v_owner public.profiles%rowtype;
  v_correct boolean := false;
  v_ticket_awarded boolean := false;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  if v_guess = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_guess');
  end if;

  select *
  into v_entry
  from public.bu_hold_pray_cards_for_profile(v_profile.id, v_week_key) hpc
  where hpc.card_index = p_card_index
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_entry.entry_profile_id is not null and v_entry.anonymous = false then
    select *
    into v_owner
    from public.profiles
    where id = v_entry.entry_profile_id;

    v_correct := lower(v_guess) in (
      lower(coalesce(v_owner.login_id, '')),
      lower(coalesce(v_owner.name, '')),
      lower(coalesce(v_owner.display_name, ''))
    );
  end if;

  insert into public.hold_pray_guesses (
    profile_id,
    week_key,
    card_index,
    guessed_name,
    correct,
    answered_at
  )
  values (
    v_profile.id,
    v_week_key,
    p_card_index,
    v_guess,
    v_correct,
    now()
  )
  on conflict (profile_id, week_key, card_index) do update
  set guessed_name = excluded.guessed_name,
      correct = excluded.correct,
      answered_at = now();

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    ref_id,
    week_key,
    payload,
    source
  )
  values (
    v_profile.id,
    'hp.guessed',
    'hold_pray',
    p_card_index::text,
    v_week_key,
    jsonb_build_object('guess', v_guess, 'correct', v_correct),
    'web'
  );

  if v_correct and v_week_key in ('w3', 'w6') and not exists(
    select 1
    from public.events
    where profile_id = v_profile.id
      and event_type = 'ticket.granted'
      and ref_type = 'hold_pray'
      and week_key = v_week_key
  ) then
    insert into public.user_inventory (
      profile_id,
      normal_pack_earned,
      normal_pack_remaining
    )
    values (
      v_profile.id,
      1,
      1
    )
    on conflict (profile_id) do update
    set normal_pack_earned = public.user_inventory.normal_pack_earned + 1,
        normal_pack_remaining = public.user_inventory.normal_pack_remaining + 1,
        updated_at = now();

    insert into public.events (
      profile_id,
      event_type,
      ref_type,
      amount,
      week_key,
      payload,
      source
    )
    values (
      v_profile.id,
      'ticket.granted',
      'hold_pray',
      1,
      v_week_key,
      jsonb_build_object('reason', 'hold_pray_guess', 'cardIndex', p_card_index),
      'web'
    );

    v_ticket_awarded := true;
  end if;

  perform public.bu_refresh_profile_summary(v_profile.id);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'correct', v_correct,
    'ticketAwarded', v_ticket_awarded
  );
end;
$$;

create or replace function public.post_hold_pray_hint(
  p_login_id text,
  p_week_key text,
  p_card_index integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_week_key text := coalesce(nullif(trim(coalesce(p_week_key, '')), ''), 'w' || public.bu_current_week()::text);
  v_entry record;
  v_owner public.profiles%rowtype;
  v_answer text := '';
  v_hint_text text := '';
  v_hint_id uuid;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  select *
  into v_entry
  from public.bu_hold_pray_cards_for_profile(v_profile.id, v_week_key) hpc
  where hpc.card_index = p_card_index
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_entry.anonymous = true then
    return jsonb_build_object('ok', false, 'error', 'anonymous');
  end if;

  if v_entry.entry_profile_id is not null then
    select *
    into v_owner
    from public.profiles
    where id = v_entry.entry_profile_id;
    v_answer := coalesce(nullif(v_owner.name, ''), nullif(v_owner.display_name, ''), nullif(v_owner.login_id, ''), '');
  end if;

  v_hint_text := case
    when v_answer <> '' and public.bu_korean_initials(v_answer) is not null
      then '이름 초성: ' || public.bu_korean_initials(v_answer)
    else '초성 정보가 없어요'
  end;

  insert into public.hold_pray_hints (
    profile_id,
    week_key,
    card_index,
    hold_pray_entry_id,
    hint_text
  )
  values (
    v_profile.id,
    v_week_key,
    p_card_index,
    v_entry.entry_id,
    v_hint_text
  )
  returning id into v_hint_id;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'hintId', v_hint_id,
    'hintText', v_hint_text
  );
end;
$$;

drop trigger if exists sync_user_cards_raffle_tickets on public.user_cards;
create constraint trigger sync_user_cards_raffle_tickets
after insert or update or delete on public.user_cards
deferrable initially deferred
for each row execute function public.bu_sync_raffle_from_user_cards_trigger();

drop trigger if exists refresh_summary_from_events on public.events;
create constraint trigger refresh_summary_from_events
after insert on public.events
deferrable initially deferred
for each row execute function public.bu_refresh_summary_from_event_trigger();

drop trigger if exists refresh_summary_from_mission_submissions on public.mission_submissions;
create constraint trigger refresh_summary_from_mission_submissions
after insert or update or delete on public.mission_submissions
deferrable initially deferred
for each row execute function public.bu_refresh_summary_from_mission_submission_trigger();

drop trigger if exists refresh_summary_from_raffle_tickets on public.raffle_tickets;
create constraint trigger refresh_summary_from_raffle_tickets
after insert or update or delete on public.raffle_tickets
deferrable initially deferred
for each row execute function public.bu_refresh_summary_from_raffle_ticket_trigger();

drop trigger if exists refresh_summary_from_trades on public.trades;
create constraint trigger refresh_summary_from_trades
after insert or update or delete on public.trades
deferrable initially deferred
for each row execute function public.bu_refresh_summary_from_trade_trigger();

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

revoke all on function public.bu_hold_pray_cards_for_profile(uuid, text) from public, anon, authenticated;
grant execute on function public.bu_korean_initials(text) to authenticated;
grant execute on function public.get_hold_pray(text, text) to authenticated;
grant execute on function public.submit_hold_pray_guess(text, text, integer, text) to authenticated;
grant execute on function public.post_hold_pray_hint(text, text, integer) to authenticated;

commit;
