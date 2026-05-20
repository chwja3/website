-- 관리자 H&P 기도제목 작성자 매칭 도구를 추가한다.
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
      public.bu_hp_answer_key(g.guessed_name) <> ''
        and public.bu_hp_answer_key(g.guessed_name) = public.bu_hp_answer_key(owner.name) as next_correct
    from public.hold_pray_guesses g
    join lateral public.bu_hold_pray_cards_for_profile(g.profile_id, g.week_key) hpc
      on hpc.card_index = g.card_index
    left join public.profiles owner on owner.id = hpc.entry_profile_id
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

create or replace function public.admin_hold_pray_entry_matching(p_week_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_week_key text := coalesce(nullif(trim(coalesce(p_week_key, '')), ''), 'w' || public.bu_current_week()::text);
  v_unmatched jsonb := '[]'::jsonb;
  v_unresolved jsonb := '[]'::jsonb;
  v_matched jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  with base as (
    select
      h.id,
      coalesce(h.week_key, v_week_key) as week_key,
      h.content,
      h.anonymous,
      h.visible,
      h.profile_id,
      nullif(btrim(coalesce(h.owner_name_input, '')), '') as owner_name_input,
      h.created_at,
      h.updated_at,
      p.login_id::text as matched_user_id,
      p.name as matched_name,
      p.parish as matched_parish
    from public.hold_pray_entries h
    left join public.profiles p on p.id = h.profile_id
    where coalesce(h.week_key, v_week_key) = v_week_key
  ),
  candidate_counts as (
    select
      b.id,
      count(mp.id)::integer as candidate_count
    from base b
    left join public.profiles mp
      on b.owner_name_input is not null
     and mp.account_status = 'active'
     and public.bu_hp_answer_key(mp.name) = public.bu_hp_answer_key(b.owner_name_input)
    group by b.id
  ),
  rows as (
    select
      b.*,
      coalesce(cc.candidate_count, 0) as candidate_count,
      case
        when b.profile_id is not null then 'matched'
        when b.owner_name_input is null then 'unmatched'
        when coalesce(cc.candidate_count, 0) > 1 then 'multiple'
        when coalesce(cc.candidate_count, 0) = 1 then 'needs_save'
        else 'not_found'
      end as match_state
    from base b
    left join candidate_counts cc on cc.id = b.id
  ),
  json_rows as (
    select
      match_state,
      updated_at,
      jsonb_build_object(
        'entryId', id,
        'weekKey', week_key,
        'content', content,
        'anonymous', coalesce(anonymous, false),
        'visible', coalesce(visible, false),
        'ownerNameInput', coalesce(owner_name_input, ''),
        'matchedUserId', coalesce(matched_user_id, ''),
        'matchedName', coalesce(matched_name, ''),
        'matchedParish', coalesce(matched_parish, ''),
        'candidateCount', candidate_count,
        'matchState', match_state,
        'createdAt', created_at,
        'updatedAt', updated_at
      ) as row_json
    from rows
  )
  select
    coalesce(jsonb_agg(row_json order by updated_at desc) filter (where match_state = 'unmatched'), '[]'::jsonb),
    coalesce(jsonb_agg(row_json order by updated_at desc) filter (where match_state in ('not_found', 'multiple', 'needs_save')), '[]'::jsonb),
    coalesce(jsonb_agg(row_json order by updated_at desc) filter (where match_state = 'matched'), '[]'::jsonb)
  into v_unmatched, v_unresolved, v_matched
  from json_rows;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'weekKey', v_week_key,
    'unmatched', coalesce(v_unmatched, '[]'::jsonb),
    'unresolved', coalesce(v_unresolved, '[]'::jsonb),
    'matched', coalesce(v_matched, '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_match_hold_pray_entry(
  p_entry_id uuid,
  p_owner_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_entry public.hold_pray_entries%rowtype;
  v_owner_name text := nullif(btrim(coalesce(p_owner_name, '')), '');
  v_profile public.profiles%rowtype;
  v_match_count integer := 0;
  v_week_key text;
  v_recalculated integer := 0;
  v_match_state text := 'unmatched';
begin
  v_admin := public.bu_admin_profile();

  select *
  into v_entry
  from public.hold_pray_entries
  where id = p_entry_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'entry_not_found');
  end if;

  v_week_key := coalesce(v_entry.week_key, 'w' || public.bu_current_week()::text);

  if v_owner_name is null then
    update public.hold_pray_entries
    set profile_id = null,
        owner_name_input = null
    where id = p_entry_id;

    v_recalculated := public.bu_recalculate_hold_pray_guesses(case when v_entry.week_key is null then null else v_week_key end);

    insert into public.events (profile_id, event_type, ref_type, ref_id, week_key, payload, source, created_by)
    values (
      null,
      'hp.prayer_owner_unmatched',
      'hold_pray',
      p_entry_id::text,
      v_week_key,
      jsonb_build_object('adminLoginId', v_admin.login_id, 'previousProfileId', v_entry.profile_id),
      'admin',
      v_admin.id
    );

    return jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'matchState', v_match_state,
      'recalculated', v_recalculated
    );
  end if;

  select count(*)::integer
  into v_match_count
  from public.profiles
  where account_status = 'active'
    and public.bu_hp_answer_key(name) = public.bu_hp_answer_key(v_owner_name);

  if v_match_count = 1 then
    select *
    into v_profile
    from public.profiles
    where account_status = 'active'
      and public.bu_hp_answer_key(name) = public.bu_hp_answer_key(v_owner_name)
    limit 1;

    update public.hold_pray_entries
    set profile_id = v_profile.id,
        owner_name_input = v_profile.name
    where id = p_entry_id;

    v_match_state := 'matched';
  else
    update public.hold_pray_entries
    set profile_id = null,
        owner_name_input = v_owner_name
    where id = p_entry_id;

    v_match_state := case when v_match_count > 1 then 'multiple' else 'not_found' end;
  end if;

  v_recalculated := public.bu_recalculate_hold_pray_guesses(case when v_entry.week_key is null then null else v_week_key end);

  insert into public.events (profile_id, event_type, ref_type, ref_id, week_key, payload, source, created_by)
  values (
    case when v_match_state = 'matched' then v_profile.id else null end,
    'hp.prayer_owner_matched',
    'hold_pray',
    p_entry_id::text,
    v_week_key,
    jsonb_build_object(
      'adminLoginId', v_admin.login_id,
      'ownerNameInput', v_owner_name,
      'matchState', v_match_state,
      'candidateCount', v_match_count
    ),
    'admin',
    v_admin.id
  );

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'matchState', v_match_state,
    'candidateCount', v_match_count,
    'matchedUserId', case when v_match_state = 'matched' then v_profile.login_id else '' end,
    'matchedName', case when v_match_state = 'matched' then v_profile.name else '' end,
    'matchedParish', case when v_match_state = 'matched' then v_profile.parish else '' end,
    'recalculated', v_recalculated
  );
end;
$$;

revoke all on function public.bu_recalculate_hold_pray_guesses(text) from public, anon, authenticated;
revoke all on function public.admin_hold_pray_entry_matching(text) from public, anon, authenticated;
revoke all on function public.admin_match_hold_pray_entry(uuid, text) from public, anon, authenticated;

grant execute on function public.admin_hold_pray_entry_matching(text) to authenticated;
grant execute on function public.admin_match_hold_pray_entry(uuid, text) to authenticated;

commit;
