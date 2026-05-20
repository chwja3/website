-- H&P 기도제목 매칭에서 동명이인 후보를 닉네임으로 선택할 수 있게 한다.
begin;

create or replace function public.bu_hp_answer_key(p_text text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(btrim(coalesce(p_text, '')), '[[:space:]]+', '', 'g'));
$$;

create or replace function public.admin_hold_pray_entry_matching(p_week_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_unmatched jsonb := '[]'::jsonb;
  v_unresolved jsonb := '[]'::jsonb;
  v_matched jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  with base as (
    select
      h.id,
      coalesce(h.week_key, '') as week_key,
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
  ),
  candidate_rows as (
    select
      b.id,
      count(mp.id)::integer as candidate_count,
      coalesce(jsonb_agg(jsonb_build_object(
        'userId', mp.login_id::text,
        'name', coalesce(mp.name, ''),
        'parish', coalesce(mp.parish, '')
      ) order by
        coalesce(array_position(array['1청','2청','3청','4청','VIP','교회학교','목양교구'], mp.parish), 99),
        mp.name,
        mp.login_id::text
      ) filter (where mp.id is not null), '[]'::jsonb) as candidates
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
      coalesce(cr.candidate_count, 0) as candidate_count,
      coalesce(cr.candidates, '[]'::jsonb) as candidates,
      case
        when b.profile_id is not null then 'matched'
        when b.owner_name_input is null then 'unmatched'
        when coalesce(cr.candidate_count, 0) > 1 then 'multiple'
        when coalesce(cr.candidate_count, 0) = 1 then 'needs_save'
        else 'not_found'
      end as match_state
    from base b
    left join candidate_rows cr on cr.id = b.id
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
        'candidates', candidates,
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
    'scope', 'all',
    'unmatched', coalesce(v_unmatched, '[]'::jsonb),
    'unresolved', coalesce(v_unresolved, '[]'::jsonb),
    'matched', coalesce(v_matched, '[]'::jsonb)
  );
end;
$$;

drop function if exists public.admin_match_hold_pray_entry(uuid, text);

create or replace function public.admin_match_hold_pray_entry(
  p_entry_id uuid,
  p_owner_name text,
  p_owner_login_id text default null
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
  v_owner_login_id text := nullif(btrim(coalesce(p_owner_login_id, '')), '');
  v_profile public.profiles%rowtype;
  v_match_count integer := 0;
  v_candidates jsonb := '[]'::jsonb;
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

  if v_owner_name is null and v_owner_login_id is null then
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

  if v_owner_login_id is not null then
    select *
    into v_profile
    from public.profiles
    where account_status = 'active'
      and login_id::text = v_owner_login_id
    limit 1;

    if v_profile.id is not null then
      v_match_count := 1;
      v_match_state := 'matched';
      update public.hold_pray_entries
      set profile_id = v_profile.id,
          owner_name_input = v_profile.name
      where id = p_entry_id;
    else
      v_match_state := 'not_found';
      update public.hold_pray_entries
      set profile_id = null,
          owner_name_input = coalesce(v_owner_name, v_owner_login_id)
      where id = p_entry_id;
    end if;
  else
    select
      count(*)::integer,
      coalesce(jsonb_agg(jsonb_build_object(
        'userId', p.login_id::text,
        'name', coalesce(p.name, ''),
        'parish', coalesce(p.parish, '')
      ) order by
        coalesce(array_position(array['1청','2청','3청','4청','VIP','교회학교','목양교구'], p.parish), 99),
        p.name,
        p.login_id::text
      ), '[]'::jsonb)
    into v_match_count, v_candidates
    from public.profiles p
    where p.account_status = 'active'
      and public.bu_hp_answer_key(p.name) = public.bu_hp_answer_key(v_owner_name);

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
      'ownerLoginId', v_owner_login_id,
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
    'candidates', v_candidates,
    'matchedUserId', case when v_match_state = 'matched' then v_profile.login_id else '' end,
    'matchedName', case when v_match_state = 'matched' then v_profile.name else '' end,
    'matchedParish', case when v_match_state = 'matched' then v_profile.parish else '' end,
    'recalculated', v_recalculated
  );
end;
$$;

grant execute on function public.admin_hold_pray_entry_matching(text) to authenticated;
grant execute on function public.admin_match_hold_pray_entry(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';

commit;
