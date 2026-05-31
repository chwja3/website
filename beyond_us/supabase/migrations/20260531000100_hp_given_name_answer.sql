-- H&P 정답 비교에서 성을 제외한 이름 입력을 허용하고 기존 응답을 재계산한다.
begin;

alter table public.hold_pray_entries
  add column if not exists owner_name_input text;

create or replace function public.bu_hp_answer_key(p_text text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(btrim(coalesce(p_text, '')), '[[:space:]]+', '', 'g'));
$$;

create or replace function public.bu_hp_answer_matches(
  p_guess text,
  p_answer text
)
returns boolean
language sql
immutable
as $$
  with normalized as (
    select
      public.bu_hp_answer_key(p_guess) as guess_key,
      public.bu_hp_answer_key(p_answer) as answer_key
  )
  select
    guess_key <> ''
    and answer_key <> ''
    and (
      guess_key = answer_key
      or (
        answer_key ~ '^[가-힣]{3,}$'
        and guess_key = substring(answer_key from 2)
      )
    )
  from normalized;
$$;

create or replace function public.bu_hold_pray_answer_name(p_entry_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(btrim(p.name), ''),
    nullif(btrim(h.owner_name_input), '')
  )
  from public.hold_pray_entries h
  left join public.profiles p on p.id = h.profile_id
  where h.id = p_entry_id
  limit 1;
$$;

create or replace function public.bu_hold_pray_answer_matches(
  p_entry_id uuid,
  p_guess text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.hold_pray_entries h
    left join public.profiles p on p.id = h.profile_id
    cross join lateral (
      values
        (p.name),
        (h.owner_name_input)
    ) as candidate(answer_text)
    where h.id = p_entry_id
      and public.bu_hp_answer_matches(p_guess, candidate.answer_text)
  );
$$;

create or replace function public.bu_award_hold_pray_ticket_if_eligible(
  p_profile_id uuid,
  p_week_key text,
  p_card_index integer default null,
  p_source public.event_source default 'web'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_key text := nullif(trim(coalesce(p_week_key, '')), '');
begin
  if p_profile_id is null or v_week_key is null then
    return false;
  end if;

  if v_week_key not in ('w3', 'w6') then
    return false;
  end if;

  perform pg_advisory_xact_lock(hashtext('hold_pray_ticket:' || p_profile_id::text || ':' || v_week_key));

  if exists(
    select 1
    from public.events
    where profile_id = p_profile_id
      and event_type = 'ticket.granted'
      and ref_type = 'hold_pray'
      and week_key = v_week_key
  ) then
    return false;
  end if;

  if not exists(
    select 1
    from public.hold_pray_guesses
    where profile_id = p_profile_id
      and week_key = v_week_key
      and correct = true
  ) then
    return false;
  end if;

  insert into public.user_inventory (
    profile_id,
    normal_pack_earned,
    normal_pack_remaining
  )
  values (
    p_profile_id,
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
    ref_id,
    amount,
    week_key,
    payload,
    source
  )
  values (
    p_profile_id,
    'ticket.granted',
    'hold_pray',
    case when p_card_index is null then null else p_card_index::text end,
    1,
    v_week_key,
    jsonb_build_object('reason', 'hold_pray_guess', 'cardIndex', p_card_index, 'backfill', p_source = 'migration'),
    p_source
  );

  perform public.bu_refresh_profile_summary(p_profile_id);

  return true;
end;
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
  where g.profile_id = v_profile.id
    and g.week_key = v_week_key
    and hpc.anonymous = false
    and public.bu_hold_pray_answer_matches(hpc.entry_id, g.guessed_name);

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

  if v_entry.anonymous = true then
    return jsonb_build_object('ok', false, 'error', 'anonymous');
  end if;

  v_correct := public.bu_hold_pray_answer_matches(v_entry.entry_id, v_guess);

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

  v_ticket_awarded := public.bu_award_hold_pray_ticket_if_eligible(v_profile.id, v_week_key, p_card_index, 'web');

  perform public.bu_refresh_profile_summary(v_profile.id);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'correct', v_correct,
    'ticketAwarded', v_ticket_awarded
  );
end;
$$;

create or replace function public.bu_recalculate_hold_pray_guesses(p_week_key text default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_key text := nullif(trim(coalesce(p_week_key, '')), '');
  v_updated integer := 0;
  v_candidate record;
begin
  with recalculated as (
    select
      g.profile_id,
      g.week_key,
      g.card_index,
      hpc.anonymous = false
        and public.bu_hold_pray_answer_matches(hpc.entry_id, g.guessed_name) as next_correct
    from public.hold_pray_guesses g
    join lateral public.bu_hold_pray_cards_for_profile(g.profile_id, g.week_key) hpc
      on hpc.card_index = g.card_index
    where v_week_key is null or g.week_key = v_week_key
  ),
  updated as (
    update public.hold_pray_guesses g
    set correct = r.next_correct
    from recalculated r
    where g.profile_id = r.profile_id
      and g.week_key = r.week_key
      and g.card_index = r.card_index
      and g.correct is distinct from r.next_correct
    returning 1
  )
  select count(*)::integer into v_updated from updated;

  for v_candidate in
    select distinct on (g.profile_id, g.week_key)
      g.profile_id,
      g.week_key,
      g.card_index
    from public.hold_pray_guesses g
    where g.correct = true
      and g.week_key in ('w3', 'w6')
      and (v_week_key is null or g.week_key = v_week_key)
    order by g.profile_id, g.week_key, g.answered_at, g.card_index
  loop
    perform public.bu_award_hold_pray_ticket_if_eligible(
      v_candidate.profile_id,
      v_candidate.week_key,
      v_candidate.card_index,
      'migration'
    );
  end loop;

  return coalesce(v_updated, 0);
end;
$$;

revoke all on function public.bu_hp_answer_matches(text, text) from public, anon, authenticated;
revoke all on function public.bu_hold_pray_answer_matches(uuid, text) from public, anon, authenticated;
revoke all on function public.bu_award_hold_pray_ticket_if_eligible(uuid, text, integer, public.event_source) from public, anon, authenticated;
revoke all on function public.get_hold_pray(text, text) from public, anon, authenticated;
revoke all on function public.submit_hold_pray_guess(text, text, integer, text) from public, anon, authenticated;
revoke all on function public.bu_recalculate_hold_pray_guesses(text) from public, anon, authenticated;

grant execute on function public.get_hold_pray(text, text) to authenticated;
grant execute on function public.submit_hold_pray_guess(text, text, integer, text) to authenticated;

do $$
begin
  perform public.bu_recalculate_hold_pray_guesses(null);
end $$;

notify pgrst, 'reload schema';

commit;
