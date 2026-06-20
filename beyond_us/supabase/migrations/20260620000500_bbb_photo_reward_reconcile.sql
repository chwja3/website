-- BBB 사진 승인 보상을 이벤트 원장 기준으로 보정한다.
begin;

create or replace function public.bu_reconcile_special_pack_inventory(
  p_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_earned integer := 0;
  v_consumed integer := 0;
  v_remaining integer := 0;
begin
  if p_profile_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_profile');
  end if;

  select coalesce(sum(case when amount > 0 then amount else 1 end), 0)::integer
  into v_earned
  from public.events
  where profile_id = p_profile_id
    and event_type = 'special_pack.granted';

  select coalesce(sum(case when amount > 0 then amount else 1 end), 0)::integer
  into v_consumed
  from public.events
  where profile_id = p_profile_id
    and event_type = 'special_pack.consumed';

  v_remaining := greatest(0, v_earned - v_consumed);

  insert into public.user_inventory (
    profile_id,
    special_pack_earned,
    special_pack_consumed,
    special_pack_remaining
  )
  values (
    p_profile_id,
    v_earned,
    v_consumed,
    v_remaining
  )
  on conflict (profile_id) do update
  set special_pack_earned = excluded.special_pack_earned,
      special_pack_consumed = excluded.special_pack_consumed,
      special_pack_remaining = excluded.special_pack_remaining,
      updated_at = now();

  perform public.bu_refresh_profile_summary(p_profile_id);

  return jsonb_build_object(
    'ok', true,
    'specialPackEarned', v_earned,
    'specialPackConsumed', v_consumed,
    'specialPackRemaining', v_remaining
  );
end;
$$;

create or replace function public.bu_issue_special_pack_for_photo(
  p_profile_id uuid,
  p_mission_key text,
  p_admin_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
  v_mission_key text := nullif(btrim(coalesce(p_mission_key, '')), '');
begin
  if p_profile_id is null or v_mission_key is null then
    return null;
  end if;

  perform pg_advisory_xact_lock(hashtext('bbb_photo_reward:' || p_profile_id::text || ':' || v_mission_key));

  select e.id
  into v_event_id
  from public.events e
  where e.profile_id = p_profile_id
    and e.event_type = 'special_pack.granted'
    and e.ref_type = v_mission_key
  order by e.occurred_at desc, e.created_at desc
  limit 1;

  if v_event_id is null then
    insert into public.events (
      profile_id,
      event_type,
      ref_type,
      amount,
      payload,
      source,
      created_by
    )
    values (
      p_profile_id,
      'special_pack.granted',
      v_mission_key,
      1,
      jsonb_build_object('reason', 'photo_approved', 'missionKey', v_mission_key),
      'admin',
      p_admin_id
    )
    returning id into v_event_id;
  end if;

  perform public.bu_reconcile_special_pack_inventory(p_profile_id);

  return v_event_id;
end;
$$;

do $$
declare
  v_row record;
  v_event_id uuid;
  v_fixed integer := 0;
begin
  for v_row in
    select s.id, s.profile_id, s.mission_key, s.reward_event_id
    from public.mission_photo_submissions s
    join public.profiles p on p.id = s.profile_id
    where s.mission_key in ('bbb_m1', 'bbb_m2')
      and s.approval_status = 'approved'
      and p.account_status = 'active'
  loop
    v_event_id := public.bu_issue_special_pack_for_photo(v_row.profile_id, v_row.mission_key, null);

    update public.mission_photo_submissions s
    set reward_event_id = v_event_id,
        updated_at = now()
    where s.id = v_row.id
      and (
        s.reward_event_id is null
        or not exists (
          select 1
          from public.events e
          where e.id = s.reward_event_id
        )
      );

    v_fixed := v_fixed + 1;
  end loop;

  raise notice 'BBB approved photo reward reconciled rows: %', v_fixed;
end $$;

revoke all on function public.bu_reconcile_special_pack_inventory(uuid) from public, anon, authenticated;
revoke all on function public.bu_issue_special_pack_for_photo(uuid, text, uuid) from public, anon, authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
