-- H&P 힌트가 사용자 실명 초성을 안정적으로 사용하도록 프로필 초성 필드를 추가한다.
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
    end if;
  end loop;

  return nullif(v_result, '');
end;
$$;

create or replace function public.bu_set_profile_name_initials()
returns trigger
language plpgsql
as $$
begin
  new.name_initials := public.bu_korean_initials(new.name);
  return new;
end;
$$;

drop trigger if exists set_profiles_name_initials on public.profiles;
create trigger set_profiles_name_initials
before insert or update of name on public.profiles
for each row execute function public.bu_set_profile_name_initials();

update public.profiles
set name_initials = public.bu_korean_initials(name)
where name_initials is distinct from public.bu_korean_initials(name);

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
  v_initials text := '';
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

    v_initials := coalesce(
      nullif(v_owner.name_initials, ''),
      public.bu_korean_initials(v_owner.name),
      ''
    );
  end if;

  v_hint_text := case
    when v_initials <> '' then '이름 초성: ' || v_initials
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

create or replace view public.ops_profiles
with (security_invoker = true)
as
select
  p.participant_code,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.birth_date,
  p.gender,
  p.parish,
  p.role,
  p.account_status,
  p.is_dev,
  p.is_test,
  p.raffle_excluded,
  p.password_migration_required,
  p.legacy_sheet_user_id,
  p.admin_note,
  p.last_login_at,
  p.created_at,
  p.updated_at,
  p.deleted_at,
  p.restored_at,
  p.id,
  p.auth_user_id,
  p.name_initials
from public.profiles p
order by p.created_at desc nulls last, p.participant_no desc nulls last;

comment on view public.ops_profiles is '운영용 프로필 목록. Table Editor에서 최신 가입자와 실명 초성을 함께 확인한다.';

revoke all on function public.post_hold_pray_hint(text, text, integer) from public, anon, authenticated;
revoke all on function public.admin_hold_pray_status(text) from public, anon, authenticated;
grant execute on function public.post_hold_pray_hint(text, text, integer) to authenticated;
grant execute on function public.admin_hold_pray_status(text) to authenticated;

commit;
