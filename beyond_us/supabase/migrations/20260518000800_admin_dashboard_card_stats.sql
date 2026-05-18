-- 관리자 대시보드와 실물 카드 수령 현황을 Supabase 기준으로 조회하는 RPC
begin;

create or replace function public.admin_dashboard_summary(p_force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_current_week integer;
  v_week_key text;
  v_weekly_summaries jsonb := '[]'::jsonb;
  v_weekly_parish_summaries jsonb := '[]'::jsonb;
  v_current_summary jsonb := '{}'::jsonb;
  v_current_parish_summaries jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();
  v_current_week := public.bu_current_week();

  select week_key
  into v_week_key
  from public.mission_weeks
  where week_order = v_current_week
  order by enabled desc, week_key
  limit 1;
  v_week_key := coalesce(v_week_key, 'w' || v_current_week::text);

  with weeks as (
    select week_key, week_order, title, draw_threshold
    from public.mission_weeks
    where enabled = true
    order by week_order
  ),
  week_payloads as (
    select
      w.week_order,
      w.week_key,
      jsonb_build_object(
        'week', w.week_order,
        'weekKey', w.week_key,
        'weekTitle', w.title,
        'items', coalesce((
          select jsonb_agg(mi.item_text order by mi.item_no)
          from public.mission_items mi
          where mi.week_key = w.week_key and mi.enabled = true
        ), '[]'::jsonb),
        'scores', coalesce((
          select jsonb_object_agg(mi.item_text, mi.score_weight order by mi.item_no)
          from public.mission_items mi
          where mi.week_key = w.week_key and mi.enabled = true
        ), '{}'::jsonb),
        'cats', coalesce((
          select jsonb_object_agg(mi.item_text, coalesce(mi.category, 'L') order by mi.item_no)
          from public.mission_items mi
          where mi.week_key = w.week_key and mi.enabled = true
        ), '{}'::jsonb),
        'drawThreshold', w.draw_threshold,
        'counts', coalesce((
          select jsonb_object_agg(mi.item_text, coalesce(ic.count_value, 0) order by mi.item_no)
          from public.mission_items mi
          left join lateral (
            select coalesce(sum(coalesce((mp.slot_counts ->> ((mi.item_no - 1)::text))::integer, 0)), 0)::integer as count_value
            from public.mission_progress mp
            join public.profiles p on p.id = mp.profile_id and p.account_status = 'active'
            where mp.week_key = w.week_key
          ) ic on true
          where mi.week_key = w.week_key and mi.enabled = true
        ), '{}'::jsonb),
        'totalCount', coalesce((
          select sum(coalesce(slot.value::integer, 0))::integer
          from public.mission_progress mp
          join public.profiles p on p.id = mp.profile_id and p.account_status = 'active'
          cross join lateral jsonb_each_text(coalesce(mp.slot_counts, '{}'::jsonb)) as slot(key, value)
          where mp.week_key = w.week_key
        ), 0),
        'submissionCount', coalesce((
          select count(distinct mp.profile_id)::integer
          from public.mission_progress mp
          join public.profiles p on p.id = mp.profile_id and p.account_status = 'active'
          where mp.week_key = w.week_key and mp.total_score > 0
        ), 0),
        'submissionEventCount', coalesce((
          select sum(mp.submission_event_count)::integer
          from public.mission_progress mp
          join public.profiles p on p.id = mp.profile_id and p.account_status = 'active'
          where mp.week_key = w.week_key
        ), 0)
      ) as summary
    from weeks w
  )
  select coalesce(jsonb_agg(summary order by week_order), '[]'::jsonb)
  into v_weekly_summaries
  from week_payloads;

  with participant_rows as (
    select
      w.week_order,
      w.week_key,
      w.title as week_title,
      case
        when p.parish = '1청' then 'p1'
        when p.parish = '2청' then 'p2'
        when p.parish = '3청' then 'p3'
        when p.parish = '4청' then 'p4'
        when upper(p.parish) = 'VIP' then 'vip'
        when p.parish in ('교회학교', '목양교구') then 'churchSchool'
        else 'etc'
      end as parish_key,
      case
        when p.parish in ('교회학교', '목양교구') then '교회학교/목양교구'
        when coalesce(p.parish, '') = '' then '기타'
        else p.parish
      end as parish_label,
      p.login_id,
      p.name,
      p.parish,
      case
        when jsonb_typeof(coalesce(mp.date_keys, '[]'::jsonb)) = 'array' then jsonb_array_length(mp.date_keys)
        else 0
      end as active_days,
      mp.total_score
    from public.mission_weeks w
    join public.mission_progress mp on mp.week_key = w.week_key
    join public.profiles p on p.id = mp.profile_id and p.account_status = 'active'
    where w.enabled = true
      and mp.total_score > 0
  ),
  parish_rows as (
    select
      week_order,
      week_key,
      week_title,
      parish_key,
      parish_label,
      count(*)::integer as participant_count,
      coalesce(sum(active_days), 0)::integer as active_days,
      coalesce(sum(total_score), 0)::integer as total_score,
      coalesce(jsonb_agg(jsonb_build_object(
        'nickname', login_id,
        'name', name,
        'parish', parish,
        'activeDays', active_days,
        'score', total_score
      ) order by total_score desc, active_days desc, login_id), '[]'::jsonb) as users
    from participant_rows
    group by week_order, week_key, week_title, parish_key, parish_label
  ),
  week_parish_payloads as (
    select
      w.week_order,
      w.week_key,
      jsonb_build_object(
        'week', w.week_order,
        'weekKey', w.week_key,
        'weekTitle', w.title,
        'parishSummaries', coalesce((
          select jsonb_agg(jsonb_build_object(
            'key', pr.parish_key,
            'label', pr.parish_label,
            'participantCount', pr.participant_count,
            'activeDays', pr.active_days,
            'totalScore', pr.total_score,
            'users', pr.users
          ) order by pr.total_score desc, pr.active_days desc, pr.parish_label)
          from parish_rows pr
          where pr.week_key = w.week_key
        ), '[]'::jsonb)
      ) as summary
    from public.mission_weeks w
    where w.enabled = true
  )
  select coalesce(jsonb_agg(summary order by week_order), '[]'::jsonb)
  into v_weekly_parish_summaries
  from week_parish_payloads;

  select coalesce(summary, '{}'::jsonb)
  into v_current_summary
  from jsonb_array_elements(v_weekly_summaries) as elem(summary)
  where summary ->> 'weekKey' = v_week_key
  limit 1;

  select coalesce(summary -> 'parishSummaries', '[]'::jsonb)
  into v_current_parish_summaries
  from jsonb_array_elements(v_weekly_parish_summaries) as elem(summary)
  where summary ->> 'weekKey' = v_week_key
  limit 1;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'currentWeek', v_current_week,
    'weekTitle', coalesce(v_current_summary ->> 'weekTitle', v_current_week::text || '주차'),
    'items', coalesce(v_current_summary -> 'items', '[]'::jsonb),
    'scores', coalesce(v_current_summary -> 'scores', '{}'::jsonb),
    'cats', coalesce(v_current_summary -> 'cats', '{}'::jsonb),
    'drawThreshold', coalesce((v_current_summary ->> 'drawThreshold')::integer, 6),
    'counts', coalesce(v_current_summary -> 'counts', '{}'::jsonb),
    'totalCount', coalesce((v_current_summary ->> 'totalCount')::integer, 0),
    'submissionCount', coalesce((v_current_summary ->> 'submissionCount')::integer, 0),
    'submissionEventCount', coalesce((v_current_summary ->> 'submissionEventCount')::integer, 0),
    'weeklySummaries', coalesce(v_weekly_summaries, '[]'::jsonb),
    'parishSummaries', coalesce(v_current_parish_summaries, '[]'::jsonb),
    'weeklyParishSummaries', coalesce(v_weekly_parish_summaries, '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_card_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_total_draws integer := 0;
  v_card_counts jsonb := '{}'::jsonb;
  v_received_counts jsonb := '{}'::jsonb;
  v_user_stats jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  select coalesce(sum(quantity), 0)::integer
  into v_total_draws
  from public.user_cards uc
  join public.profiles p on p.id = uc.profile_id and p.account_status = 'active'
  where uc.card_id between 1 and 9;

  select coalesce(jsonb_object_agg(c.id::text, coalesce(ct.qty, 0) order by c.id), '{}'::jsonb)
  into v_card_counts
  from public.cards c
  left join (
    select uc.card_id, sum(uc.quantity)::integer as qty
    from public.user_cards uc
    join public.profiles p on p.id = uc.profile_id and p.account_status = 'active'
    group by uc.card_id
  ) ct on ct.card_id = c.id
  where c.id between 1 and 9 and c.enabled = true;

  select coalesce(jsonb_object_agg(c.id::text, coalesce(rt.received, 0) order by c.id), '{}'::jsonb)
  into v_received_counts
  from public.cards c
  left join (
    select r.card_id, sum(r.received_qty)::integer as received
    from public.physical_card_receipts r
    join public.profiles p on p.id = r.profile_id and p.account_status = 'active'
    group by r.card_id
  ) rt on rt.card_id = c.id
  where c.id between 1 and 9 and c.enabled = true;

  with active_profiles as (
    select p.id, p.login_id, p.name
    from public.profiles p
    where p.account_status = 'active'
      and (
        exists (select 1 from public.user_cards uc where uc.profile_id = p.id and uc.quantity > 0)
        or exists (select 1 from public.physical_card_receipts r where r.profile_id = p.id and r.received_qty > 0)
      )
  ),
  normal_cards as (
    select id, name, sort_order
    from public.cards
    where id between 1 and 9 and enabled = true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'nickname', ap.login_id,
    'name', ap.name,
    'cards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'cardId', c.id,
        'cardName', c.name,
        'drew', coalesce(uc.quantity, 0),
        'received', coalesce(r.received_qty, 0),
        'needed', greatest(0, coalesce(uc.quantity, 0) - coalesce(r.received_qty, 0)),
        'tfTarget', coalesce(uc.quantity, 0),
        'tradeOut', 0,
        'tradeOutTo', '[]'::jsonb,
        'tradeInFrom', '[]'::jsonb,
        'tradeInFromDetails', '[]'::jsonb
      ) order by c.sort_order, c.id)
      from normal_cards c
      left join public.user_cards uc on uc.profile_id = ap.id and uc.card_id = c.id
      left join public.physical_card_receipts r on r.profile_id = ap.id and r.card_id = c.id
    ), '[]'::jsonb)
  ) order by ap.login_id), '[]'::jsonb)
  into v_user_stats
  from active_profiles ap;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'totalDraws', v_total_draws,
    'cardCounts', v_card_counts,
    'receivedCounts', v_received_counts,
    'userStats', v_user_stats
  );
end;
$$;

revoke all on function public.admin_dashboard_summary(boolean) from public, anon, authenticated;
grant execute on function public.admin_dashboard_summary(boolean) to authenticated;

revoke all on function public.admin_card_stats() from public, anon, authenticated;
grant execute on function public.admin_card_stats() to authenticated;

commit;
