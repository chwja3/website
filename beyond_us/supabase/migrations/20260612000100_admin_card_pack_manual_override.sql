-- 관리자 누락 보상에서 카드 뽑기권은 조건 미충족이어도 수동 지급할 수 있게 한다.
begin;

create or replace function public.admin_get_user_reward_opportunities(
  p_login_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_rewards jsonb := '[]'::jsonb;
  v_inventory public.user_inventory%rowtype;
  v_raffle_count integer := 0;
  v_card_count integer := 0;
  v_week record;
  v_condition_met boolean;
  v_claimed boolean;
  v_disabled_reason text;
begin
  v_admin := public.bu_admin_profile();

  select *
  into v_profile
  from public.profiles
  where login_id = p_login_id
    and account_status = 'active'
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'error', 'user_not_found');
  end if;

  select *
  into v_inventory
  from public.user_inventory
  where profile_id = v_profile.id;

  select count(*)::integer
  into v_raffle_count
  from public.raffle_tickets
  where profile_id = v_profile.id
    and active = true;

  v_card_count := public.bu_raffle_card_count(v_profile.id);

  for v_week in
    select week_key, title, draw_threshold, week_order
    from public.mission_weeks
    where draw_threshold > 0
    order by week_order
  loop
    select exists(
      select 1
      from public.mission_progress mp
      where mp.profile_id = v_profile.id
        and mp.week_key = v_week.week_key
        and coalesce(mp.total_score, 0) >= v_week.draw_threshold
    )
    into v_condition_met;

    select exists(
      select 1
      from public.events e
      where e.profile_id = v_profile.id
        and e.event_type = 'ticket.granted'
        and e.week_key = v_week.week_key
        and e.payload ->> 'reason' = 'mission_week_threshold'
    )
    into v_claimed;

    v_disabled_reason := case
      when v_claimed then 'already_claimed'
      else null
    end;

    v_rewards := v_rewards || jsonb_build_array(jsonb_build_object(
      'rewardKey', 'mission_' || v_week.week_key,
      'type', 'card_pack',
      'label', coalesce(v_week.title, v_week.week_key) || ' 사전미션 카드 뽑기권',
      'description', '사전미션 주차 점수 ' || v_week.draw_threshold::text || '점 달성 보상',
      'conditionMet', v_condition_met,
      'claimed', v_claimed,
      'available', not v_claimed,
      'manualOverrideAllowed', true,
      'disabledReason', v_disabled_reason
    ));
  end loop;

  for v_week in
    select *
    from (values
      ('w3'::text, '3주차 H&P 카드 뽑기권'::text),
      ('w6'::text, '6주차 H&P 카드 뽑기권'::text)
    ) as hp(week_key, title)
  loop
    select exists(
      select 1
      from public.hold_pray_guesses g
      where g.profile_id = v_profile.id
        and g.week_key = v_week.week_key
        and g.correct = true
    )
    into v_condition_met;

    select exists(
      select 1
      from public.events e
      where e.profile_id = v_profile.id
        and e.event_type = 'ticket.granted'
        and e.ref_type = 'hold_pray'
        and e.week_key = v_week.week_key
    )
    into v_claimed;

    v_disabled_reason := case
      when v_claimed then 'already_claimed'
      else null
    end;

    v_rewards := v_rewards || jsonb_build_array(jsonb_build_object(
      'rewardKey', 'hp_' || v_week.week_key,
      'type', 'card_pack',
      'label', v_week.title,
      'description', 'H&P 정답 1개 이상 보상',
      'conditionMet', v_condition_met,
      'claimed', v_claimed,
      'available', not v_claimed,
      'manualOverrideAllowed', true,
      'disabledReason', v_disabled_reason
    ));
  end loop;

  for v_week in
    select *
    from (values
      ('app_signup'::text, '앱 가입 추첨권'::text, 0::integer),
      ('card_3'::text, '카드 3종 보유 추첨권'::text, 3::integer),
      ('card_5'::text, '카드 5종 보유 추첨권'::text, 5::integer),
      ('card_10'::text, '카드 10종 보유 추첨권'::text, 10::integer)
    ) as rf(condition_key, title, threshold)
  loop
    v_condition_met := coalesce(v_profile.raffle_excluded, false) = false
      and (
        v_week.threshold = 0
        or v_card_count >= v_week.threshold
      );

    select exists(
      select 1
      from public.raffle_tickets rt
      where rt.profile_id = v_profile.id
        and rt.condition_key = v_week.condition_key
        and rt.active = true
    )
    into v_claimed;

    v_disabled_reason := case
      when coalesce(v_profile.raffle_excluded, false) then 'raffle_excluded'
      when v_claimed then 'already_claimed'
      when not v_condition_met then 'condition_not_met'
      else null
    end;

    v_rewards := v_rewards || jsonb_build_array(jsonb_build_object(
      'rewardKey', 'raffle_' || v_week.condition_key,
      'type', 'raffle_ticket',
      'label', v_week.title,
      'description', case
        when v_week.threshold = 0 then '앱 가입 완료 보상'
        else '현재 카드 ' || v_card_count::text || '/' || v_week.threshold::text || '종 보유'
      end,
      'conditionMet', v_condition_met,
      'claimed', v_claimed,
      'available', v_condition_met and not v_claimed,
      'manualOverrideAllowed', false,
      'disabledReason', v_disabled_reason
    ));
  end loop;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'viewer', v_admin.login_id,
    'user', jsonb_build_object(
      'nickname', v_profile.login_id,
      'name', v_profile.name,
      'parish', v_profile.parish,
      'raffleExcluded', v_profile.raffle_excluded
    ),
    'inventory', jsonb_build_object(
      'normalPackRemaining', coalesce(v_inventory.normal_pack_remaining, 0),
      'normalPackEarned', coalesce(v_inventory.normal_pack_earned, 0),
      'specialPackRemaining', coalesce(v_inventory.special_pack_remaining, 0)
    ),
    'raffleTickets', v_raffle_count,
    'uniqueCards', v_card_count,
    'rewards', v_rewards
  );
end;
$$;

create or replace function public.admin_issue_user_missed_reward(
  p_login_id text,
  p_reward_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_reward_key text := nullif(trim(coalesce(p_reward_key, '')), '');
  v_week_key text;
  v_condition_key text;
  v_week public.mission_weeks%rowtype;
  v_condition_met boolean := false;
  v_claimed boolean := false;
  v_card_index integer := null;
  v_issue_result jsonb := '{}'::jsonb;
  v_card_count integer := 0;
begin
  v_admin := public.bu_admin_profile();

  select *
  into v_profile
  from public.profiles
  where login_id = p_login_id
    and account_status = 'active'
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'error', 'user_not_found');
  end if;

  if v_reward_key is null then
    return jsonb_build_object('ok', false, 'error', 'missing_reward_key');
  end if;

  perform pg_advisory_xact_lock(hashtext('admin_missed_reward:' || v_profile.id::text || ':' || v_reward_key));

  if v_reward_key like 'mission_w%' then
    v_week_key := replace(v_reward_key, 'mission_', '');

    select *
    into v_week
    from public.mission_weeks
    where week_key = v_week_key
      and draw_threshold > 0
    limit 1;

    if v_week.week_key is null then
      return jsonb_build_object('ok', false, 'error', 'unknown_reward');
    end if;

    select exists(
      select 1
      from public.mission_progress mp
      where mp.profile_id = v_profile.id
        and mp.week_key = v_week_key
        and coalesce(mp.total_score, 0) >= v_week.draw_threshold
    )
    into v_condition_met;

    select exists(
      select 1
      from public.events e
      where e.profile_id = v_profile.id
        and e.event_type = 'ticket.granted'
        and e.week_key = v_week_key
        and e.payload ->> 'reason' = 'mission_week_threshold'
    )
    into v_claimed;

    if v_claimed then
      return jsonb_build_object('ok', false, 'error', 'already_claimed');
    end if;

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
      ref_id,
      amount,
      week_key,
      payload,
      source,
      created_by
    )
    values (
      v_profile.id,
      'ticket.granted',
      'mission',
      'admin_missed_' || v_reward_key,
      1,
      v_week_key,
      jsonb_build_object(
        'reason', 'mission_week_threshold',
        'adminManual', true,
        'adminManualOverride', not v_condition_met,
        'conditionMet', v_condition_met,
        'rewardKey', v_reward_key,
        'weekTitle', v_week.title,
        'threshold', v_week.draw_threshold
      ),
      'admin',
      v_admin.id
    );

    perform public.bu_refresh_profile_summary(v_profile.id);

    return jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'issued', true,
      'type', 'card_pack',
      'rewardKey', v_reward_key,
      'user', v_profile.login_id,
      'conditionMet', v_condition_met,
      'manualOverride', not v_condition_met
    );
  end if;

  if v_reward_key in ('hp_w3', 'hp_w6') then
    v_week_key := replace(v_reward_key, 'hp_', '');

    select g.card_index
    into v_card_index
    from public.hold_pray_guesses g
    where g.profile_id = v_profile.id
      and g.week_key = v_week_key
      and g.correct = true
    order by g.answered_at, g.card_index
    limit 1;

    v_condition_met := v_card_index is not null;

    select exists(
      select 1
      from public.events e
      where e.profile_id = v_profile.id
        and e.event_type = 'ticket.granted'
        and e.ref_type = 'hold_pray'
        and e.week_key = v_week_key
    )
    into v_claimed;

    if v_claimed then
      return jsonb_build_object('ok', false, 'error', 'already_claimed');
    end if;

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
      ref_id,
      amount,
      week_key,
      payload,
      source,
      created_by
    )
    values (
      v_profile.id,
      'ticket.granted',
      'hold_pray',
      'admin_missed_' || v_reward_key,
      1,
      v_week_key,
      jsonb_build_object(
        'reason', 'hold_pray_correct',
        'adminManual', true,
        'adminManualOverride', not v_condition_met,
        'conditionMet', v_condition_met,
        'rewardKey', v_reward_key,
        'cardIndex', v_card_index
      ),
      'admin',
      v_admin.id
    );

    perform public.bu_refresh_profile_summary(v_profile.id);

    return jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'issued', true,
      'type', 'card_pack',
      'rewardKey', v_reward_key,
      'user', v_profile.login_id,
      'conditionMet', v_condition_met,
      'manualOverride', not v_condition_met
    );
  end if;

  if v_reward_key like 'raffle_%' then
    v_condition_key := replace(v_reward_key, 'raffle_', '');
    v_card_count := public.bu_raffle_card_count(v_profile.id);

    if coalesce(v_profile.raffle_excluded, false) then
      return jsonb_build_object('ok', false, 'error', 'raffle_excluded');
    end if;

    v_condition_met := case v_condition_key
      when 'app_signup' then true
      when 'card_3' then v_card_count >= 3
      when 'card_5' then v_card_count >= 5
      when 'card_10' then v_card_count >= 10
      else false
    end;

    if not v_condition_met then
      return jsonb_build_object('ok', false, 'error', 'condition_not_met');
    end if;

    select exists(
      select 1
      from public.raffle_tickets rt
      where rt.profile_id = v_profile.id
        and rt.condition_key = v_condition_key
        and rt.active = true
    )
    into v_claimed;

    if v_claimed then
      return jsonb_build_object('ok', false, 'error', 'already_claimed');
    end if;

    v_issue_result := public.bu_issue_raffle_ticket(v_profile.id, v_condition_key, 'admin', v_admin.id);
    if coalesce((v_issue_result ->> 'issued')::boolean, false) = false then
      return v_issue_result || jsonb_build_object('ok', false);
    end if;

    return jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'issued', true,
      'type', 'raffle_ticket',
      'rewardKey', v_reward_key,
      'user', v_profile.login_id,
      'raffle', v_issue_result
    );
  end if;

  return jsonb_build_object('ok', false, 'error', 'unknown_reward');
end;
$$;

revoke all on function public.admin_get_user_reward_opportunities(text) from public, anon, authenticated;
revoke all on function public.admin_issue_user_missed_reward(text, text) from public, anon, authenticated;

grant execute on function public.admin_get_user_reward_opportunities(text) to authenticated;
grant execute on function public.admin_issue_user_missed_reward(text, text) to authenticated;

notify pgrst, 'reload schema';

commit;
