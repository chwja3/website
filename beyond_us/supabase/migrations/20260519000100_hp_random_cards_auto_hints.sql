-- H&P 사용자별 랜덤 3장 노출과 자동 초성 힌트를 적용한다.
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
  v_initials text[] := array['ㄱ','ㄲ','ㄴ','ㄷ','ㄸ','ㄹ','ㅁ','ㅂ','ㅃ','ㅅ','ㅆ','ㅇ','ㅈ','ㅉ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ'];
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
  v_hint_replies jsonb := '{}'::jsonb;
  v_revision text := '';
  v_ticket_awarded boolean := false;
  v_ticket_idx integer := -1;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  v_week_key := coalesce(v_week_key, 'w' || public.bu_current_week()::text);

  with eligible_cards as (
    select
      hp.*,
      md5(v_profile.id::text || ':' || v_week_key || ':' || hp.id::text) as hp_sort_key
    from public.hold_pray_entries hp
    where hp.visible = true
      and coalesce(hp.week_key, v_week_key) = v_week_key
      and (hp.profile_id is null or hp.profile_id <> v_profile.id)
  ),
  picked_cards as (
    select *
    from eligible_cards
    order by hp_sort_key, created_at, id
    limit 3
  ),
  ordered_cards as (
    select
      row_number() over (order by hp_sort_key, created_at, id) - 1 as card_index,
      id,
      profile_id,
      content,
      anonymous,
      updated_at
    from picked_cards
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'content', content,
      'anon', anonymous
    ) order by card_index), '[]'::jsonb),
    coalesce(max(updated_at)::text, '')
  into v_cards, v_revision
  from ordered_cards;

  with eligible_cards as (
    select
      hp.*,
      md5(v_profile.id::text || ':' || v_week_key || ':' || hp.id::text) as hp_sort_key
    from public.hold_pray_entries hp
    where hp.visible = true
      and coalesce(hp.week_key, v_week_key) = v_week_key
      and (hp.profile_id is null or hp.profile_id <> v_profile.id)
  ),
  picked_cards as (
    select *
    from eligible_cards
    order by hp_sort_key, created_at, id
    limit 3
  ),
  ordered_cards as (
    select
      row_number() over (order by hp_sort_key, created_at, id) - 1 as card_index,
      profile_id,
      anonymous
    from picked_cards
  )
  select coalesce(jsonb_object_agg(g.card_index::text, g.guessed_name), '{}'::jsonb)
  into v_correct_map
  from public.hold_pray_guesses g
  join ordered_cards oc on oc.card_index = g.card_index
  left join public.profiles owner on owner.id = oc.profile_id
  where g.profile_id = v_profile.id
    and g.week_key = v_week_key
    and g.correct = true
    and oc.anonymous = false
    and lower(g.guessed_name) in (
      lower(coalesce(owner.login_id, '')),
      lower(coalesce(owner.name, '')),
      lower(coalesce(owner.display_name, ''))
    );

  with eligible_cards as (
    select
      hp.*,
      md5(v_profile.id::text || ':' || v_week_key || ':' || hp.id::text) as hp_sort_key
    from public.hold_pray_entries hp
    where hp.visible = true
      and coalesce(hp.week_key, v_week_key) = v_week_key
      and (hp.profile_id is null or hp.profile_id <> v_profile.id)
  ),
  picked_cards as (
    select *
    from eligible_cards
    order by hp_sort_key, created_at, id
    limit 3
  ),
  ordered_cards as (
    select
      row_number() over (order by hp_sort_key, created_at, id) - 1 as card_index,
      id
    from picked_cards
  ),
  latest_hints as (
    select distinct on (h.card_index)
      h.card_index,
      h.hint_text
    from public.hold_pray_hints h
    join ordered_cards oc on oc.card_index = h.card_index and oc.id = h.hold_pray_entry_id
    where h.profile_id = v_profile.id
      and h.week_key = v_week_key
      and h.hint_text <> 'requested'
    order by h.card_index, h.created_at desc
  )
  select coalesce(jsonb_object_agg(card_index::text, hint_text), '{}'::jsonb)
  into v_hint_replies
  from latest_hints;

  select exists(
    select 1
    from public.events
    where profile_id = v_profile.id
      and event_type = 'ticket.granted'
      and ref_type = 'hold_pray'
      and week_key = v_week_key
  )
  into v_ticket_awarded;

  select coalesce((payload ->> 'cardIndex')::integer, -1)
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
    'hintReplies', coalesce(v_hint_replies, '{}'::jsonb)
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
  from (
    with eligible_cards as (
      select
        hp.*,
        md5(v_profile.id::text || ':' || v_week_key || ':' || hp.id::text) as hp_sort_key
      from public.hold_pray_entries hp
      where hp.visible = true
        and coalesce(hp.week_key, v_week_key) = v_week_key
        and (hp.profile_id is null or hp.profile_id <> v_profile.id)
    ),
    picked_cards as (
      select *
      from eligible_cards
      order by hp_sort_key, created_at, id
      limit 3
    )
    select
      row_number() over (order by hp_sort_key, created_at, id) - 1 as card_index,
      picked_cards.*
    from picked_cards
  ) ordered_cards
  where card_index = p_card_index;

  if v_entry.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_entry.profile_id is not null and v_entry.anonymous = false then
    select *
    into v_owner
    from public.profiles
    where id = v_entry.profile_id;

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
  from (
    with eligible_cards as (
      select
        hp.*,
        md5(v_profile.id::text || ':' || v_week_key || ':' || hp.id::text) as hp_sort_key
      from public.hold_pray_entries hp
      where hp.visible = true
        and coalesce(hp.week_key, v_week_key) = v_week_key
        and (hp.profile_id is null or hp.profile_id <> v_profile.id)
    ),
    picked_cards as (
      select *
      from eligible_cards
      order by hp_sort_key, created_at, id
      limit 3
    )
    select
      row_number() over (order by hp_sort_key, created_at, id) - 1 as card_index,
      picked_cards.*
    from picked_cards
  ) ordered_cards
  where card_index = p_card_index;

  if v_entry.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_entry.anonymous = true then
    return jsonb_build_object('ok', false, 'error', 'anonymous');
  end if;

  if v_entry.profile_id is not null then
    select *
    into v_owner
    from public.profiles
    where id = v_entry.profile_id;
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
    v_entry.id,
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

grant execute on function public.bu_korean_initials(text) to authenticated;
grant execute on function public.get_hold_pray(text, text) to authenticated;
grant execute on function public.submit_hold_pray_guess(text, text, integer, text) to authenticated;
grant execute on function public.post_hold_pray_hint(text, text, integer) to authenticated;

commit;
