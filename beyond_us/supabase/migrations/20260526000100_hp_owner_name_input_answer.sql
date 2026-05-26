-- H&P 정답 판정에서 프로필이 없는 기도제목의 입력 이름을 정답 이름으로 사용한다.
begin;

alter table public.hold_pray_entries
  add column if not exists owner_name_input text;

comment on column public.hold_pray_entries.owner_name_input is '관리자가 작성자 매칭을 위해 입력한 실명. 프로필을 못 찾았거나 동명이인일 때도 보존한다.';

create or replace function public.bu_hp_answer_key(p_text text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(btrim(coalesce(p_text, '')), '[[:space:]]+', '', 'g'));
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
    and public.bu_hp_answer_key(g.guessed_name) <> ''
    and public.bu_hp_answer_key(public.bu_hold_pray_answer_name(hpc.entry_id)) <> ''
    and public.bu_hp_answer_key(g.guessed_name) = public.bu_hp_answer_key(public.bu_hold_pray_answer_name(hpc.entry_id));

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
  v_answer_name text;
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

  v_answer_name := public.bu_hold_pray_answer_name(v_entry.entry_id);
  v_correct := public.bu_hp_answer_key(v_guess) <> ''
    and public.bu_hp_answer_key(v_answer_name) <> ''
    and public.bu_hp_answer_key(v_guess) = public.bu_hp_answer_key(v_answer_name);

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

create or replace function public.bu_recalculate_hold_pray_guesses(p_week_key text default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_key text := nullif(trim(coalesce(p_week_key, '')), '');
  v_updated integer := 0;
begin
  with recalculated as (
    select
      g.profile_id,
      g.week_key,
      g.card_index,
      hpc.anonymous = false
        and public.bu_hp_answer_key(g.guessed_name) <> ''
        and public.bu_hp_answer_key(public.bu_hold_pray_answer_name(hpc.entry_id)) <> ''
        and public.bu_hp_answer_key(g.guessed_name) = public.bu_hp_answer_key(public.bu_hold_pray_answer_name(hpc.entry_id)) as next_correct
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

  return coalesce(v_updated, 0);
end;
$$;

revoke all on function public.bu_hp_answer_key(text) from public, anon, authenticated;
revoke all on function public.bu_hold_pray_answer_name(uuid) from public, anon, authenticated;
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
