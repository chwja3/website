-- PROD Supabase에 H&P 매칭과 admin 오류 표시 보강 SQL을 한 번에 적용하는 수동 실행 파일이다.
-- 실행 대상: AGC Retreat PROD Supabase SQL Editor.
-- 생성일: 2026-05-20.
-- 참고: 006/007 helper guard는 앞뒤에 한 번씩 배치해 누락 의존성과 최종 H&P 현황 RPC를 안전하게 보강한다.


-- =====================================================================
-- Source: beyond_us\supabase\migrations\20260520000600_hp_prayer_matching_helper_guard.sql
-- =====================================================================

-- H&P 기도 작성자 매칭 저장에 필요한 내부 helper를 보강한다.
begin;

create or replace function public.bu_hp_answer_key(p_text text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(btrim(coalesce(p_text, '')), '[[:space:]]+', '', 'g'));
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
    (row_number() over (order by pc.hp_sort_key, pc.created_at, pc.id) - 1)::integer as card_index,
    pc.id as entry_id,
    pc.profile_id as entry_profile_id,
    pc.content as content,
    pc.anonymous as anonymous,
    pc.updated_at as updated_at
  from picked_cards pc;
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

revoke all on function public.bu_hp_answer_key(text) from public, anon, authenticated;
revoke all on function public.bu_hold_pray_cards_for_profile(uuid, text) from public, anon, authenticated;
revoke all on function public.bu_recalculate_hold_pray_guesses(text) from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;

-- =====================================================================
-- Source: beyond_us\supabase\migrations\20260520000700_admin_hp_status_helper_guard.sql
-- =====================================================================

-- 관리자 H&P 유저 현황 RPC의 누락 의존성을 보강한다.
begin;

alter table public.profiles
  add column if not exists name_initials text;

comment on column public.profiles.name_initials is 'H&P 힌트와 운영 확인에 사용하는 실명 기준 초성.';

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

update public.profiles
set name_initials = public.bu_korean_initials(name)
where nullif(btrim(coalesce(name_initials, '')), '') is null
  and nullif(btrim(coalesce(name, '')), '') is not null;

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

create or replace function public.admin_hold_pray_status(p_week_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_week_key text := coalesce(nullif(trim(coalesce(p_week_key, '')), ''), 'w' || public.bu_current_week()::text);
  v_rows jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  with active_users as (
    select p.*
    from public.profiles p
    where p.account_status = 'active'
  ),
  own_entries as (
    select distinct on (h.profile_id)
      h.profile_id,
      h.content,
      h.anonymous,
      h.visible,
      h.updated_at
    from public.hold_pray_entries h
    where coalesce(h.week_key, v_week_key) = v_week_key
      and h.profile_id is not null
    order by h.profile_id, h.updated_at desc, h.id desc
  ),
  picked_cards as (
    select
      u.id as viewer_id,
      hpc.card_index,
      hpc.entry_id,
      hpc.entry_profile_id as owner_id,
      owner.login_id::text as owner_login_id,
      coalesce(owner.name, owner.display_name, owner.login_id::text, '') as owner_name,
      coalesce(owner.name_initials, public.bu_korean_initials(owner.name), '') as owner_initials,
      hpc.content,
      hpc.anonymous,
      g.guessed_name,
      coalesce(g.correct, false) as correct,
      g.answered_at
    from active_users u
    left join lateral public.bu_hold_pray_cards_for_profile(u.id, v_week_key) hpc on true
    left join public.profiles owner on owner.id = hpc.entry_profile_id
    left join public.hold_pray_guesses g
      on g.profile_id = u.id
     and g.week_key = v_week_key
     and g.card_index = hpc.card_index
  ),
  card_groups as (
    select
      viewer_id,
      coalesce(jsonb_agg(jsonb_build_object(
        'cardIndex', card_index,
        'ownerUserId', owner_login_id,
        'ownerName', owner_name,
        'ownerInitials', owner_initials,
        'anonymous', anonymous,
        'content', content,
        'guessedName', coalesce(guessed_name, ''),
        'correct', coalesce(correct, false),
        'answeredAt', answered_at
      ) order by card_index) filter (where card_index is not null), '[]'::jsonb) as cards,
      count(*) filter (where card_index is not null and guessed_name is not null) as answered_count,
      count(*) filter (where card_index is not null and correct = true) as correct_count
    from picked_cards
    group by viewer_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'userId', u.login_id,
    'name', coalesce(u.name, ''),
    'nameInitials', coalesce(u.name_initials, public.bu_korean_initials(u.name), ''),
    'displayName', coalesce(u.display_name, ''),
    'parish', coalesce(u.parish, ''),
    'ownPrayer', coalesce(oe.content, ''),
    'ownPrayerAnonymous', coalesce(oe.anonymous, false),
    'ownPrayerVisible', coalesce(oe.visible, false),
    'ownPrayerUpdatedAt', oe.updated_at,
    'cards', coalesce(cg.cards, '[]'::jsonb),
    'answeredCount', coalesce(cg.answered_count, 0),
    'correctCount', coalesce(cg.correct_count, 0)
  ) order by
    coalesce(array_position(array['1청','2청','3청','4청','VIP','교회학교','목양교구'], u.parish), 99),
    u.name nulls last,
    u.login_id), '[]'::jsonb)
  into v_rows
  from active_users u
  left join own_entries oe on oe.profile_id = u.id
  left join card_groups cg on cg.viewer_id = u.id;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'weekKey', v_week_key,
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.bu_hold_pray_cards_for_profile(uuid, text) from public, anon, authenticated;
revoke all on function public.bu_korean_initials(text) from public, anon, authenticated;
revoke all on function public.admin_hold_pray_status(text) from public, anon, authenticated;

grant execute on function public.admin_hold_pray_status(text) to authenticated;

notify pgrst, 'reload schema';

commit;

-- =====================================================================
-- Source: beyond_us\supabase\migrations\20260520000200_hp_prayer_matching_admin.sql
-- =====================================================================

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

-- =====================================================================
-- Source: beyond_us\supabase\migrations\20260520000300_hp_prayer_matching_schema_reload.sql
-- =====================================================================

-- H&P 기도제목 매칭 RPC가 PostgREST에 즉시 보이도록 스키마 캐시를 새로고침한다.
begin;

alter table public.hold_pray_entries
  add column if not exists owner_name_input text;

do $$
begin
  if to_regprocedure('public.admin_hold_pray_entry_matching(text)') is not null then
    grant execute on function public.admin_hold_pray_entry_matching(text) to authenticated;
  end if;

  if to_regprocedure('public.admin_match_hold_pray_entry(uuid,text)') is not null then
    grant execute on function public.admin_match_hold_pray_entry(uuid, text) to authenticated;
  end if;
end;
$$;

notify pgrst, 'reload schema';

commit;

-- =====================================================================
-- Source: beyond_us\supabase\migrations\20260520000400_hp_prayer_matching_all_entries.sql
-- =====================================================================

-- H&P 기도제목 작성자 매칭을 주차와 무관한 전체 엔트리 기준으로 변경한다.
begin;

alter table public.hold_pray_entries
  add column if not exists owner_name_input text;

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
    'scope', 'all',
    'unmatched', coalesce(v_unmatched, '[]'::jsonb),
    'unresolved', coalesce(v_unresolved, '[]'::jsonb),
    'matched', coalesce(v_matched, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.admin_hold_pray_entry_matching(text) to authenticated;

notify pgrst, 'reload schema';

commit;

-- =====================================================================
-- Source: beyond_us\supabase\migrations\20260520000500_hp_prayer_matching_duplicate_candidates.sql
-- =====================================================================

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

-- =====================================================================
-- Source: beyond_us\supabase\migrations\20260520000600_hp_prayer_matching_helper_guard.sql
-- =====================================================================

-- H&P 기도 작성자 매칭 저장에 필요한 내부 helper를 보강한다.
begin;

create or replace function public.bu_hp_answer_key(p_text text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(btrim(coalesce(p_text, '')), '[[:space:]]+', '', 'g'));
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
    (row_number() over (order by pc.hp_sort_key, pc.created_at, pc.id) - 1)::integer as card_index,
    pc.id as entry_id,
    pc.profile_id as entry_profile_id,
    pc.content as content,
    pc.anonymous as anonymous,
    pc.updated_at as updated_at
  from picked_cards pc;
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

revoke all on function public.bu_hp_answer_key(text) from public, anon, authenticated;
revoke all on function public.bu_hold_pray_cards_for_profile(uuid, text) from public, anon, authenticated;
revoke all on function public.bu_recalculate_hold_pray_guesses(text) from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;

-- =====================================================================
-- Source: beyond_us\supabase\migrations\20260520000700_admin_hp_status_helper_guard.sql
-- =====================================================================

-- 관리자 H&P 유저 현황 RPC의 누락 의존성을 보강한다.
begin;

alter table public.profiles
  add column if not exists name_initials text;

comment on column public.profiles.name_initials is 'H&P 힌트와 운영 확인에 사용하는 실명 기준 초성.';

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

update public.profiles
set name_initials = public.bu_korean_initials(name)
where nullif(btrim(coalesce(name_initials, '')), '') is null
  and nullif(btrim(coalesce(name, '')), '') is not null;

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

create or replace function public.admin_hold_pray_status(p_week_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_week_key text := coalesce(nullif(trim(coalesce(p_week_key, '')), ''), 'w' || public.bu_current_week()::text);
  v_rows jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  with active_users as (
    select p.*
    from public.profiles p
    where p.account_status = 'active'
  ),
  own_entries as (
    select distinct on (h.profile_id)
      h.profile_id,
      h.content,
      h.anonymous,
      h.visible,
      h.updated_at
    from public.hold_pray_entries h
    where coalesce(h.week_key, v_week_key) = v_week_key
      and h.profile_id is not null
    order by h.profile_id, h.updated_at desc, h.id desc
  ),
  picked_cards as (
    select
      u.id as viewer_id,
      hpc.card_index,
      hpc.entry_id,
      hpc.entry_profile_id as owner_id,
      owner.login_id::text as owner_login_id,
      coalesce(owner.name, owner.display_name, owner.login_id::text, '') as owner_name,
      coalesce(owner.name_initials, public.bu_korean_initials(owner.name), '') as owner_initials,
      hpc.content,
      hpc.anonymous,
      g.guessed_name,
      coalesce(g.correct, false) as correct,
      g.answered_at
    from active_users u
    left join lateral public.bu_hold_pray_cards_for_profile(u.id, v_week_key) hpc on true
    left join public.profiles owner on owner.id = hpc.entry_profile_id
    left join public.hold_pray_guesses g
      on g.profile_id = u.id
     and g.week_key = v_week_key
     and g.card_index = hpc.card_index
  ),
  card_groups as (
    select
      viewer_id,
      coalesce(jsonb_agg(jsonb_build_object(
        'cardIndex', card_index,
        'ownerUserId', owner_login_id,
        'ownerName', owner_name,
        'ownerInitials', owner_initials,
        'anonymous', anonymous,
        'content', content,
        'guessedName', coalesce(guessed_name, ''),
        'correct', coalesce(correct, false),
        'answeredAt', answered_at
      ) order by card_index) filter (where card_index is not null), '[]'::jsonb) as cards,
      count(*) filter (where card_index is not null and guessed_name is not null) as answered_count,
      count(*) filter (where card_index is not null and correct = true) as correct_count
    from picked_cards
    group by viewer_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'userId', u.login_id,
    'name', coalesce(u.name, ''),
    'nameInitials', coalesce(u.name_initials, public.bu_korean_initials(u.name), ''),
    'displayName', coalesce(u.display_name, ''),
    'parish', coalesce(u.parish, ''),
    'ownPrayer', coalesce(oe.content, ''),
    'ownPrayerAnonymous', coalesce(oe.anonymous, false),
    'ownPrayerVisible', coalesce(oe.visible, false),
    'ownPrayerUpdatedAt', oe.updated_at,
    'cards', coalesce(cg.cards, '[]'::jsonb),
    'answeredCount', coalesce(cg.answered_count, 0),
    'correctCount', coalesce(cg.correct_count, 0)
  ) order by
    coalesce(array_position(array['1청','2청','3청','4청','VIP','교회학교','목양교구'], u.parish), 99),
    u.name nulls last,
    u.login_id), '[]'::jsonb)
  into v_rows
  from active_users u
  left join own_entries oe on oe.profile_id = u.id
  left join card_groups cg on cg.viewer_id = u.id;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'weekKey', v_week_key,
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.bu_hold_pray_cards_for_profile(uuid, text) from public, anon, authenticated;
revoke all on function public.bu_korean_initials(text) from public, anon, authenticated;
revoke all on function public.admin_hold_pray_status(text) from public, anon, authenticated;

grant execute on function public.admin_hold_pray_status(text) to authenticated;

notify pgrst, 'reload schema';

commit;
