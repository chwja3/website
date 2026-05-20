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
