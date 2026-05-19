-- 관리자 운영 화면에서 H&P, BBB, 천로역정 상태를 조회하는 RPC를 추가한다.
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
    order by h.profile_id, h.updated_at desc, h.id desc
  ),
  picked_cards as (
    select
      u.id as viewer_id,
      c.card_index,
      c.entry_id,
      c.owner_id,
      c.owner_login_id,
      c.owner_name,
      c.content,
      c.anonymous,
      g.guessed_name,
      coalesce(g.correct, false) as correct,
      g.answered_at
    from active_users u
    left join lateral (
      select
        row_number() over (order by hp_sort_key, created_at, id) - 1 as card_index,
        id as entry_id,
        profile_id as owner_id,
        owner.login_id::text as owner_login_id,
        coalesce(owner.name, owner.display_name, owner.login_id::text, '') as owner_name,
        content,
        anonymous
      from (
        select
          hp.*,
          md5(u.id::text || ':' || v_week_key || ':' || hp.id::text) as hp_sort_key
        from public.hold_pray_entries hp
        where hp.visible = true
          and coalesce(hp.week_key, v_week_key) = v_week_key
          and (hp.profile_id is null or hp.profile_id <> u.id)
        order by hp_sort_key, hp.created_at, hp.id
        limit 3
      ) hp
      left join public.profiles owner on owner.id = hp.profile_id
    ) c on true
    left join public.hold_pray_guesses g
      on g.profile_id = u.id
     and g.week_key = v_week_key
     and g.card_index = c.card_index
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

create or replace function public.admin_bbb_pilgrim_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_rows jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  with active_users as (
    select p.*
    from public.profiles p
    where p.account_status = 'active'
  ),
  latest_photos as (
    select distinct on (s.profile_id, s.mission_key, s.spot_index)
      s.profile_id,
      s.mission_key,
      s.spot_index,
      s.storage_path,
      s.approval_status,
      s.reward_event_id,
      s.created_at,
      s.updated_at
    from public.mission_photo_submissions s
    where s.mission_key in ('bbb_m1', 'bbb_m2', 'pilgrim')
    order by s.profile_id, s.mission_key, s.spot_index, s.updated_at desc, s.id desc
  ),
  bbb_photo_summary as (
    select
      profile_id,
      coalesce((jsonb_agg(jsonb_build_object(
        'status', approval_status,
        'storagePath', storage_path,
        'rewarded', reward_event_id is not null,
        'uploadedAt', created_at,
        'updatedAt', updated_at
      ) order by updated_at desc) filter (where mission_key = 'bbb_m1'))->0, '{}'::jsonb) as m1,
      coalesce((jsonb_agg(jsonb_build_object(
        'status', approval_status,
        'storagePath', storage_path,
        'rewarded', reward_event_id is not null,
        'uploadedAt', created_at,
        'updatedAt', updated_at
      ) order by updated_at desc) filter (where mission_key = 'bbb_m2'))->0, '{}'::jsonb) as m2
    from latest_photos
    where mission_key in ('bbb_m1', 'bbb_m2')
    group by profile_id
  ),
  pilgrim_photo_summary as (
    select
      profile_id,
      coalesce(jsonb_agg(jsonb_build_object(
        'spotIndex', spot_index,
        'status', approval_status,
        'storagePath', storage_path,
        'uploadedAt', created_at,
        'updatedAt', updated_at
      ) order by spot_index) filter (where mission_key = 'pilgrim'), '[]'::jsonb) as spot_photos,
      coalesce(jsonb_agg(spot_index order by spot_index) filter (where mission_key = 'pilgrim' and approval_status = 'approved'), '[]'::jsonb) as completed_spots
    from latest_photos
    where mission_key = 'pilgrim'
    group by profile_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'userId', u.login_id,
    'name', coalesce(u.name, ''),
    'displayName', coalesce(u.display_name, ''),
    'parish', coalesce(u.parish, ''),
    'careBuddy', jsonb_build_object(
      'userId', care.login_id,
      'name', coalesce(care.name, care.display_name, care.login_id::text, '')
    ),
    'secretBuddy', jsonb_build_object(
      'userId', secret.login_id,
      'name', coalesce(secret.name, secret.display_name, secret.login_id::text, '')
    ),
    'secretRevealed', coalesce(ba.secret_revealed, false),
    'tier', coalesce(ba.tier, ''),
    'groupNo', g.group_no,
    'groupName', coalesce(g.name, ''),
    'm1', coalesce(bps.m1, '{}'::jsonb),
    'm2', coalesce(bps.m2, '{}'::jsonb),
    'pilgrimAssignedSpots', coalesce(to_jsonb(pa.spot_indices), '[]'::jsonb),
    'pilgrimCompletedSpots', coalesce(pps.completed_spots, '[]'::jsonb),
    'pilgrimSpotPhotos', coalesce(pps.spot_photos, '[]'::jsonb),
    'pilgrimCompleted', pa.completed_at is not null,
    'pilgrimCompletedAt', pa.completed_at,
    'pilgrimRewarded', pa.reward_event_id is not null
  ) order by
    coalesce(array_position(array['1청','2청','3청','4청','VIP','교회학교','목양교구'], u.parish), 99),
    u.name nulls last,
    u.login_id), '[]'::jsonb)
  into v_rows
  from active_users u
  left join public.bbb_assignments ba on ba.profile_id = u.id
  left join public.profiles care on care.id = ba.care_buddy_id
  left join public.profiles secret on secret.id = ba.secret_buddy_id
  left join public.groups g on g.id = ba.group_id
  left join public.pilgrim_assignments pa on pa.profile_id = u.id
  left join bbb_photo_summary bps on bps.profile_id = u.id
  left join pilgrim_photo_summary pps on pps.profile_id = u.id;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_hold_pray_status(text) from public, anon, authenticated;
revoke all on function public.admin_bbb_pilgrim_status() from public, anon, authenticated;

grant execute on function public.admin_hold_pray_status(text) to authenticated;
grant execute on function public.admin_bbb_pilgrim_status() to authenticated;

commit;
