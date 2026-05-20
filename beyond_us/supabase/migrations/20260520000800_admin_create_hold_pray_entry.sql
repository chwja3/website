-- 관리자가 새 H&P 기도제목을 작성자 매칭과 함께 추가하는 RPC를 만든다.
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

create or replace function public.admin_create_hold_pray_entry(
  p_content text,
  p_owner_name text default null,
  p_owner_login_id text default null,
  p_anonymous boolean default false,
  p_visible boolean default true,
  p_week_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_content text := btrim(coalesce(p_content, ''));
  v_owner_name text := nullif(btrim(coalesce(p_owner_name, '')), '');
  v_owner_login_id text := nullif(btrim(coalesce(p_owner_login_id, '')), '');
  v_week_key text := nullif(btrim(coalesce(p_week_key, '')), '');
  v_profile public.profiles%rowtype;
  v_match_count integer := 0;
  v_candidates jsonb := '[]'::jsonb;
  v_match_state text := 'unmatched';
  v_entry_id uuid;
  v_recalculated integer := 0;
begin
  v_admin := public.bu_admin_profile();

  if v_content = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_content');
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
      v_owner_name := v_profile.name;
    else
      v_match_state := 'not_found';
      v_owner_name := coalesce(v_owner_name, v_owner_login_id);
    end if;
  elsif v_owner_name is not null then
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

      v_match_state := 'matched';
    else
      v_match_state := case when v_match_count > 1 then 'multiple' else 'not_found' end;
    end if;
  end if;

  insert into public.hold_pray_entries (
    profile_id,
    week_key,
    content,
    anonymous,
    visible,
    owner_name_input
  )
  values (
    case when v_match_state = 'matched' then v_profile.id else null end,
    v_week_key,
    v_content,
    coalesce(p_anonymous, false),
    coalesce(p_visible, true),
    v_owner_name
  )
  returning id into v_entry_id;

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    ref_id,
    amount,
    week_key,
    payload,
    source,
    created_by
  )
  values (
    case when v_match_state = 'matched' then v_profile.id else null end,
    'hp.prayer_admin_created',
    'hold_pray',
    v_entry_id::text,
    0,
    coalesce(v_week_key, 'all'),
    jsonb_build_object(
      'adminLoginId', v_admin.login_id,
      'ownerNameInput', v_owner_name,
      'ownerLoginId', v_owner_login_id,
      'matchState', v_match_state,
      'candidateCount', v_match_count,
      'visible', coalesce(p_visible, true),
      'anonymous', coalesce(p_anonymous, false)
    ),
    'admin',
    v_admin.id
  );

  if to_regprocedure('public.bu_recalculate_hold_pray_guesses(text)') is not null then
    v_recalculated := public.bu_recalculate_hold_pray_guesses(v_week_key);
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'entryId', v_entry_id,
    'weekKey', coalesce(v_week_key, ''),
    'matchState', v_match_state,
    'candidateCount', v_match_count,
    'candidates', v_candidates,
    'matchedUserId', case when v_match_state = 'matched' then v_profile.login_id else '' end,
    'matchedName', case when v_match_state = 'matched' then v_profile.name else '' end,
    'matchedParish', case when v_match_state = 'matched' then v_profile.parish else '' end,
    'ownerNameInput', coalesce(v_owner_name, ''),
    'recalculated', v_recalculated
  );
end;
$$;

revoke all on function public.admin_create_hold_pray_entry(text, text, text, boolean, boolean, text) from public, anon, authenticated;
grant execute on function public.admin_create_hold_pray_entry(text, text, text, boolean, boolean, text) to authenticated;

notify pgrst, 'reload schema';

commit;
