-- 사용자 앱의 초기 현황과 사용자 상태를 Supabase에서 읽는 RPC 함수
begin;

create or replace function public.bu_jsonb_int(p_value jsonb, p_fallback integer)
returns integer
language plpgsql
immutable
as $$
declare
  v_text text;
begin
  if p_value is null then
    return p_fallback;
  end if;

  if jsonb_typeof(p_value) = 'number' then
    return (p_value::text)::integer;
  end if;

  if jsonb_typeof(p_value) = 'string' then
    v_text := trim(both '"' from p_value::text);
    if v_text ~ '^-?\d+$' then
      return v_text::integer;
    end if;
  end if;

  return p_fallback;
exception when others then
  return p_fallback;
end;
$$;

create or replace function public.bu_current_week()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week integer;
begin
  select public.bu_jsonb_int(value_json, 1)
  into v_week
  from public.app_settings
  where key = 'current_week';

  v_week := coalesce(v_week, 1);
  if v_week < 1 then return 1; end if;
  if v_week > 6 then return 6; end if;
  return v_week;
end;
$$;

create or replace function public.bu_tab_api_key(p_key text)
returns text
language sql
immutable
as $$
  select case p_key
    when 'holdpray' then 'prayer'
    when 'bbb' then 'secret'
    else p_key
  end;
$$;

create or replace function public.bu_tab_display_key(p_key text)
returns text
language sql
immutable
as $$
  select case p_key
    when 'bbb' then 'secret'
    else p_key
  end;
$$;

create or replace function public.bu_tab_settings_json()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_bbb_sections jsonb;
begin
  select coalesce(value_json, '{}'::jsonb)
  into v_bbb_sections
  from public.app_settings
  where key = 'bbb_settings';

  with normalized as (
    select
      public.bu_tab_display_key(tab_key) as display_key,
      public.bu_tab_api_key(tab_key) as api_key,
      label,
      enabled,
      status::text as status,
      sort_order,
      case
        when tab_key = 'secret' then 0
        when tab_key = 'bbb' then 1
        else 0
      end as priority
    from public.tab_settings
  ),
  dedup as (
    select distinct on (api_key)
      display_key,
      api_key,
      label,
      enabled,
      status,
      sort_order
    from normalized
    order by api_key, priority, sort_order
  ),
  aggregate_tabs as (
    select
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'key', display_key,
            'apiKey', api_key,
            'label', label,
            'enabled', enabled,
            'status', status
          )
          order by sort_order
        ),
        '[]'::jsonb
      ) as items,
      coalesce(jsonb_object_agg(api_key, status), '{}'::jsonb) as statuses,
      bool_or(enabled) filter (where api_key = 'notice') as notice_enabled,
      bool_or(enabled) filter (where api_key = 'mission') as mission_enabled,
      bool_or(enabled) filter (where api_key = 'prayer') as prayer_enabled,
      bool_or(enabled) filter (where api_key = 'secret') as secret_enabled,
      bool_or(enabled) filter (where api_key = 'chat') as chat_enabled,
      bool_or(enabled) filter (where api_key = 'qt') as qt_enabled,
      bool_or(enabled) filter (where api_key = 'pilgrim') as pilgrim_enabled,
      bool_or(enabled) filter (where api_key = 'collection') as collection_enabled,
      bool_or(enabled) filter (where api_key = 'faq') as faq_enabled,
      bool_or(enabled) filter (where api_key = 'inquiry') as inquiry_enabled,
      bool_or(enabled) filter (where api_key = 'specialPack') as special_pack_enabled
    from dedup
  )
  select jsonb_build_object(
    'ok', true,
    'items', items,
    'statuses', statuses,
    'notice', coalesce(notice_enabled, true),
    'mission', coalesce(mission_enabled, true),
    'prayer', coalesce(prayer_enabled, true),
    'secret', coalesce(secret_enabled, false),
    'chat', coalesce(chat_enabled, false),
    'qt', coalesce(qt_enabled, false),
    'pilgrim', coalesce(pilgrim_enabled, false),
    'collection', coalesce(collection_enabled, true),
    'faq', coalesce(faq_enabled, true),
    'inquiry', coalesce(inquiry_enabled, true),
    'specialPack', coalesce(special_pack_enabled, false),
    'bbbSections', coalesce(v_bbb_sections, '{}'::jsonb)
  )
  into v_result
  from aggregate_tabs;

  return coalesce(v_result, jsonb_build_object(
    'ok', true,
    'items', '[]'::jsonb,
    'statuses', '{}'::jsonb,
    'notice', true,
    'mission', true,
    'prayer', true,
    'secret', false,
    'chat', false,
    'qt', false,
    'pilgrim', false,
    'collection', true,
    'faq', true,
    'inquiry', true,
    'specialPack', false,
    'bbbSections', coalesce(v_bbb_sections, '{}'::jsonb)
  ));
end;
$$;

create or replace function public.get_app_bootstrap()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current_week integer;
  v_week_key text;
  v_week_title text;
  v_draw_threshold integer;
  v_items jsonb := '[]'::jsonb;
  v_scores jsonb := '{}'::jsonb;
  v_cats jsonb := '{}'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_total_count integer := 0;
  v_submission_count integer := 0;
  v_submission_event_count integer := 0;
  v_current_summary jsonb;
  v_tab_settings jsonb;
begin
  v_current_week := public.bu_current_week();

  select week_key, title, draw_threshold
  into v_week_key, v_week_title, v_draw_threshold
  from public.mission_weeks
  where week_order = v_current_week
  order by enabled desc, week_key
  limit 1;

  v_week_key := coalesce(v_week_key, 'w' || v_current_week::text);
  v_week_title := coalesce(v_week_title, v_current_week::text || '주차');
  v_draw_threshold := coalesce(v_draw_threshold, 6);

  select
    coalesce(jsonb_agg(item_text order by item_no), '[]'::jsonb),
    coalesce(jsonb_object_agg(item_text, score_weight), '{}'::jsonb),
    coalesce(jsonb_object_agg(item_text, coalesce(category, 'L')), '{}'::jsonb)
  into v_items, v_scores, v_cats
  from public.mission_items
  where week_key = v_week_key
    and enabled = true;

  with enabled_items as (
    select item_no, item_text
    from public.mission_items
    where week_key = v_week_key
      and enabled = true
  ),
  item_counts as (
    select
      ei.item_no,
      ei.item_text,
      coalesce(sum(coalesce((mp.slot_counts ->> ((ei.item_no - 1)::text))::integer, 0)), 0)::integer as count_value
    from enabled_items ei
    left join public.mission_progress mp on mp.week_key = v_week_key
    left join public.profiles p on p.id = mp.profile_id and p.account_status = 'active'
    where p.id is not null or mp.profile_id is null
    group by ei.item_no, ei.item_text
  )
  select
    coalesce(jsonb_object_agg(item_text, count_value order by item_no), '{}'::jsonb),
    coalesce(sum(count_value), 0)::integer
  into v_counts, v_total_count
  from item_counts;

  select
    count(distinct mp.profile_id)::integer,
    coalesce(sum(mp.submission_event_count), 0)::integer
  into v_submission_count, v_submission_event_count
  from public.mission_progress mp
  join public.profiles p on p.id = mp.profile_id and p.account_status = 'active'
  where mp.week_key = v_week_key
    and mp.total_score > 0;

  v_current_summary := jsonb_build_object(
    'week', v_current_week,
    'weekKey', v_week_key,
    'weekTitle', v_week_title,
    'items', v_items,
    'scores', v_scores,
    'cats', v_cats,
    'drawThreshold', v_draw_threshold,
    'counts', v_counts,
    'totalCount', v_total_count,
    'submissionCount', v_submission_count,
    'submissionEventCount', v_submission_event_count,
    'totalScore', 0
  );
  v_tab_settings := public.bu_tab_settings_json();

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'currentWeek', v_current_week,
    'weekTitle', v_week_title,
    'items', v_items,
    'scores', v_scores,
    'cats', v_cats,
    'drawThreshold', v_draw_threshold,
    'counts', v_counts,
    'totalCount', v_total_count,
    'submissionCount', v_submission_count,
    'submissionEventCount', v_submission_event_count,
    'currentWeekSummary', v_current_summary,
    'weeklySummaries', jsonb_build_array(v_current_summary),
    'weeklyParishSummaries', '[]'::jsonb,
    'parishSummaries', '[]'::jsonb,
    'missionProgressReady', true,
    'tabSettings', v_tab_settings
  );
end;
$$;

create or replace function public.get_user_status(
  p_login_id text,
  p_week_key text default null,
  p_lite boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_auth_uid uuid := auth.uid();
  v_current_week integer;
  v_week_key text;
  v_week_title text;
  v_draw_threshold integer;
  v_today text := to_char((now() at time zone 'Asia/Seoul')::date, 'YYYY-MM-DD');
  v_total_score integer := 0;
  v_date_keys jsonb := '[]'::jsonb;
  v_date_slot_indices jsonb := '{}'::jsonb;
  v_today_indices jsonb := '[]'::jsonb;
  v_today_items jsonb := '[]'::jsonb;
  v_collection jsonb := '[]'::jsonb;
  v_week_card jsonb := null;
  v_inventory public.user_inventory%rowtype;
  v_my_ticket_numbers jsonb := '[]'::jsonb;
  v_my_tickets integer := 0;
  v_total_tickets integer := 0;
  v_participant_count integer := 0;
  v_unique_cards integer := 0;
  v_visual_cap integer := 1000;
  v_max_fill integer := 90;
  v_fill_percent integer := 0;
  v_breakdown jsonb := '{}'::jsonb;
  v_signup_ticket integer := 0;
  v_card3_ticket integer := 0;
  v_card5_ticket integer := 0;
  v_card10_ticket integer := 0;
begin
  if nullif(trim(coalesce(p_login_id, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'missing_userId');
  end if;

  select *
  into v_profile
  from public.profiles
  where login_id = p_login_id
    and account_status = 'active'
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'error', 'inactive_user');
  end if;

  if v_auth_uid is null or v_profile.auth_user_id is distinct from v_auth_uid then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;

  v_current_week := public.bu_current_week();
  v_week_key := nullif(trim(coalesce(p_week_key, '')), '');
  if v_week_key is null then
    v_week_key := 'w' || v_current_week::text;
  end if;

  select week_order, title, draw_threshold
  into v_current_week, v_week_title, v_draw_threshold
  from public.mission_weeks
  where week_key = v_week_key
  limit 1;

  v_current_week := coalesce(v_current_week, public.bu_current_week());
  v_week_title := coalesce(v_week_title, v_current_week::text || '주차');
  v_draw_threshold := coalesce(v_draw_threshold, 6);

  select *
  into v_inventory
  from public.user_inventory
  where profile_id = v_profile.id;

  select
    coalesce(mp.total_score, 0),
    coalesce(mp.date_keys, '[]'::jsonb),
    coalesce(mp.date_slot_indices, '{}'::jsonb)
  into v_total_score, v_date_keys, v_date_slot_indices
  from public.mission_progress mp
  where mp.profile_id = v_profile.id
    and mp.week_key = v_week_key;

  v_total_score := coalesce(v_total_score, 0);
  v_date_keys := coalesce(v_date_keys, '[]'::jsonb);
  v_date_slot_indices := coalesce(v_date_slot_indices, '{}'::jsonb);

  if jsonb_typeof(v_date_slot_indices) = 'object'
     and v_date_slot_indices ? v_today
     and jsonb_typeof(v_date_slot_indices -> v_today) = 'array' then
    select coalesce(jsonb_agg(value::integer order by ordinality), '[]'::jsonb)
    into v_today_indices
    from jsonb_array_elements_text(v_date_slot_indices -> v_today) with ordinality;
  end if;
  v_today_indices := coalesce(v_today_indices, '[]'::jsonb);

  select coalesce(jsonb_agg(mi.item_text order by idx.idx), '[]'::jsonb)
  into v_today_items
  from (
    select value::integer as idx
    from jsonb_array_elements_text(v_today_indices)
  ) idx
  join public.mission_items mi
    on mi.week_key = v_week_key
   and mi.item_no = idx.idx + 1
   and mi.enabled = true;

  select coalesce(
    jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.sort_order, c.id, gs.n),
    '[]'::jsonb
  )
  into v_collection
  from public.user_cards uc
  join public.cards c on c.id = uc.card_id
  cross join lateral generate_series(1, uc.quantity) as gs(n)
  where uc.profile_id = v_profile.id
    and uc.quantity > 0
    and c.enabled = true;

  select jsonb_build_object('id', c.id, 'name', c.name)
  into v_week_card
  from public.events e
  join public.cards c
    on c.id = case when e.ref_id ~ '^\d+$' then e.ref_id::smallint else null end
  where e.profile_id = v_profile.id
    and e.event_type = 'card.drawn'
    and e.week_key = v_week_key
  order by e.occurred_at desc
  limit 1;

  select count(*)::integer
  into v_unique_cards
  from public.user_cards
  where profile_id = v_profile.id
    and card_id between 1 and 10
    and quantity > 0;

  select public.bu_jsonb_int(value_json, 1000)
  into v_visual_cap
  from public.app_settings
  where key = 'raffle_visual_cap';
  v_visual_cap := greatest(1, coalesce(v_visual_cap, 1000));

  select public.bu_jsonb_int(value_json, 90)
  into v_max_fill
  from public.app_settings
  where key = 'raffle_visual_max_fill_percent';
  v_max_fill := greatest(1, least(100, coalesce(v_max_fill, 90)));

  select
    count(*)::integer,
    count(distinct profile_id)::integer
  into v_total_tickets, v_participant_count
  from public.raffle_tickets
  where active = true;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'condition',
      case rt.condition_key when 'app_signup' then 'signup' else rt.condition_key end,
      'ticket_no',
      lpad(rt.ticket_no::text, 4, '0')
    )
    order by coalesce(rc.sort_order, 999), rt.ticket_no
  ), '[]'::jsonb)
  into v_my_ticket_numbers
  from public.raffle_tickets rt
  left join public.raffle_conditions rc on rc.condition_key = rt.condition_key
  where rt.active = true
    and rt.profile_id = v_profile.id;

  v_my_tickets := coalesce(jsonb_array_length(v_my_ticket_numbers), 0);

  select
    (count(*) filter (where condition_key = 'app_signup'))::integer,
    (count(*) filter (where condition_key = 'card_3'))::integer,
    (count(*) filter (where condition_key = 'card_5'))::integer,
    (count(*) filter (where condition_key = 'card_10'))::integer
  into v_signup_ticket, v_card3_ticket, v_card5_ticket, v_card10_ticket
  from public.raffle_tickets
  where active = true
    and profile_id = v_profile.id;

  v_breakdown := jsonb_build_object(
    'signupTicket', coalesce(v_signup_ticket, 0),
    'card3Ticket', coalesce(v_card3_ticket, 0),
    'card5Ticket', coalesce(v_card5_ticket, 0),
    'card10Ticket', coalesce(v_card10_ticket, 0),
    'attendanceTicket', 0
  );

  if v_total_tickets <= 0 then
    v_fill_percent := 0;
  else
    v_fill_percent := least(
      v_max_fill,
      greatest(4, round((v_total_tickets::numeric / v_visual_cap::numeric) * v_max_fill)::integer)
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'lite', p_lite,
    'weekScore', v_total_score,
    'drawThreshold', v_draw_threshold,
    'canDraw', coalesce(v_inventory.normal_pack_remaining, 0) > 0,
    'pendingDraws', coalesce(v_inventory.normal_pack_remaining, 0),
    'pendingSpecialPacks', coalesce(v_inventory.special_pack_remaining, 0),
    'earnedTicketThisWeek', v_draw_threshold > 0 and v_total_score >= v_draw_threshold,
    'drawnThisWeek', v_week_card is not null,
    'weekCard', v_week_card,
    'collection', coalesce(v_collection, '[]'::jsonb),
    'raffle', jsonb_build_object(
      'eligible', v_profile.raffle_excluded = false,
      'ineligibleReason', case when v_profile.raffle_excluded then 'raffle_excluded' else '' end,
      'myTickets', case when v_profile.raffle_excluded then 0 else v_my_tickets end,
      'totalTickets', v_total_tickets,
      'participantCount', v_participant_count,
      'uniqueCards', v_unique_cards,
      'visualCap', v_visual_cap,
      'fillPercent', v_fill_percent,
      'breakdown', case when v_profile.raffle_excluded then '{}'::jsonb else v_breakdown end,
      'myTicketNumbers', case when v_profile.raffle_excluded then '[]'::jsonb else v_my_ticket_numbers end
    ),
    'raffleDeferred', false,
    'todayItems', coalesce(v_today_items, '[]'::jsonb),
    'todayIndices', coalesce(v_today_indices, '[]'::jsonb),
    'weekDates', coalesce(v_date_keys, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_app_bootstrap() to anon, authenticated;
grant execute on function public.get_user_status(text, text, boolean) to authenticated;

commit;
