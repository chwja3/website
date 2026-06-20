-- 하진 프로필을 유하진 조 명단에 매칭하고 H&P 입력 정답 정책을 통일한다.
begin;

alter table public.profiles
  add column if not exists name_initials text;

do $$
declare
  v_hajin_count integer := 0;
  v_yuhajin_count integer := 0;
  v_roster_count integer := 0;
  v_profile public.profiles%rowtype;
begin
  select count(*)::integer
  into v_hajin_count
  from public.profiles p
  where p.account_status = 'active'
    and public.bu_group_roster_normalize_name(p.name) = public.bu_group_roster_normalize_name('하진')
    and public.bu_group_roster_normalize_parish(p.parish) = '4청';

  select count(*)::integer
  into v_yuhajin_count
  from public.profiles p
  where p.account_status = 'active'
    and public.bu_group_roster_normalize_name(p.name) = public.bu_group_roster_normalize_name('유하진')
    and public.bu_group_roster_normalize_parish(p.parish) = '4청';

  if v_hajin_count = 1 then
    update public.profiles p
    set name = '유하진',
        name_initials = public.bu_korean_initials('유하진'),
        updated_at = now()
    where p.account_status = 'active'
      and public.bu_group_roster_normalize_name(p.name) = public.bu_group_roster_normalize_name('하진')
      and public.bu_group_roster_normalize_parish(p.parish) = '4청'
    returning * into v_profile;
  elsif v_hajin_count = 0 and v_yuhajin_count = 1 then
    select *
    into v_profile
    from public.profiles p
    where p.account_status = 'active'
      and public.bu_group_roster_normalize_name(p.name) = public.bu_group_roster_normalize_name('유하진')
      and public.bu_group_roster_normalize_parish(p.parish) = '4청'
    limit 1;
  else
    raise exception 'expected exactly one active 4청 profile named 하진 or 유하진, got 하진 %, 유하진 %', v_hajin_count, v_yuhajin_count;
  end if;

  select count(*)::integer
  into v_roster_count
  from public.retreat_group_roster r
  where r.source_batch = '20260614'
    and r.group_no = 4
    and public.bu_group_roster_normalize_name(r.participant_name) = public.bu_group_roster_normalize_name('유하진');

  if v_roster_count <> 1 then
    raise exception 'expected exactly one 4조 roster row named 유하진, got %', v_roster_count;
  end if;

  update public.retreat_group_roster r
  set matched_profile_id = v_profile.id,
      candidate_profiles = jsonb_build_array(jsonb_build_object(
        'profileId', v_profile.id,
        'loginId', v_profile.login_id,
        'name', v_profile.name,
        'displayName', v_profile.display_name,
        'parish', v_profile.parish,
        'participantCode', v_profile.participant_code,
        'isDev', coalesce(v_profile.is_dev, false),
        'isTest', coalesce(v_profile.is_test, false)
      )),
      match_status = 'matched_manual',
      match_detail = '하진 프로필 이름을 유하진으로 보정해 4조 명단에 수동 매칭',
      updated_at = now()
  where r.source_batch = '20260614'
    and r.group_no = 4
    and public.bu_group_roster_normalize_name(r.participant_name) = public.bu_group_roster_normalize_name('유하진');

  perform public.bu_sync_group_roster_profile_matches('20260614');
end $$;

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
  select public.bu_hp_answer_key(p_guess) <> '';
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
    and g.correct = true;

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

  v_correct := public.bu_hp_answer_key(v_guess) <> '';

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
    jsonb_build_object('guess', v_guess, 'correct', v_correct, 'policy', 'non_empty_input'),
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
        and public.bu_hp_answer_key(g.guessed_name) <> '' as next_correct
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

revoke all on function public.bu_hold_pray_answer_matches(uuid, text) from public, anon, authenticated;
revoke all on function public.get_hold_pray(text, text) from public, anon, authenticated;
revoke all on function public.submit_hold_pray_guess(text, text, integer, text) from public, anon, authenticated;
revoke all on function public.bu_recalculate_hold_pray_guesses(text) from public, anon, authenticated;

grant execute on function public.get_hold_pray(text, text) to authenticated;
grant execute on function public.submit_hold_pray_guess(text, text, integer, text) to authenticated;

do $$
begin
  perform public.bu_recalculate_hold_pray_guesses(null);
end $$;

select pg_notify('pgrst', 'reload schema');

commit;
