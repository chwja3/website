-- 관리자 H&P 현황 RPC가 앱과 같은 H&P 카드 선택 helper를 사용하게 한다.
begin;

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

revoke all on function public.admin_hold_pray_status(text) from public, anon, authenticated;
grant execute on function public.admin_hold_pray_status(text) to authenticated;

commit;
