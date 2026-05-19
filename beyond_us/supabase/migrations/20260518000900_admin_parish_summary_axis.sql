-- 관리자 교구 참여 현황의 표시 순서와 빈 교구 노출을 고정하는 RPC 갱신
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

  with parish_axis(parish_key, parish_label, sort_order) as (
    values
      ('p1', '1청', 1),
      ('p2', '2청', 2),
      ('p3', '3청', 3),
      ('p4', '4청', 4),
      ('vip', 'VIP', 5),
      ('churchSchool', '교회학교/목양교구', 6)
  ),
  participant_rows as (
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
            'key', x.parish_key,
            'label', x.parish_label,
            'participantCount', x.participant_count,
            'activeDays', x.active_days,
            'totalScore', x.total_score,
            'users', x.users
          ) order by x.sort_order, x.parish_label)
          from (
            select
              a.parish_key,
              a.parish_label,
              a.sort_order,
              coalesce(pr.participant_count, 0)::integer as participant_count,
              coalesce(pr.active_days, 0)::integer as active_days,
              coalesce(pr.total_score, 0)::integer as total_score,
              coalesce(pr.users, '[]'::jsonb) as users
            from parish_axis a
            left join parish_rows pr
              on pr.week_key = w.week_key
             and pr.parish_key = a.parish_key
            union all
            select
              pr.parish_key,
              pr.parish_label,
              90 as sort_order,
              pr.participant_count,
              pr.active_days,
              pr.total_score,
              pr.users
            from parish_rows pr
            where pr.week_key = w.week_key
              and not exists (
                select 1 from parish_axis a where a.parish_key = pr.parish_key
              )
          ) x
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

revoke all on function public.admin_dashboard_summary(boolean) from public, anon, authenticated;
grant execute on function public.admin_dashboard_summary(boolean) to authenticated;

commit;
