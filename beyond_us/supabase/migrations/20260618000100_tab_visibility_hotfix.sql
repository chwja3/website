-- 사용자 앱 탭 표시 누락을 막기 위해 탭 설정 키와 응답 JSON을 보강한다.
begin;

insert into public.tab_settings (tab_key, label, enabled, status, sort_order)
values
  ('counseling', '목사님께 무물', true, 'open', 85),
  ('visible_radio', '별빛 우편함', true, 'open', 86)
on conflict (tab_key) do update
set label = excluded.label,
    sort_order = excluded.sort_order,
    updated_at = now();

create or replace function public.bu_tab_api_key(p_key text)
returns text
language sql
immutable
as $$
  select case p_key
    when 'holdpray' then 'prayer'
    when 'bbb' then 'secret'
    when 'visibleRadio' then 'visible_radio'
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
        when tab_key = 'visible_radio' then 0
        when tab_key = 'visibleRadio' then 1
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
      bool_or(enabled) filter (where api_key = 'investigation') as investigation_enabled,
      bool_or(enabled) filter (where api_key = 'counseling') as counseling_enabled,
      bool_or(enabled) filter (where api_key = 'visible_radio') as visible_radio_enabled,
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
    'investigation', coalesce(investigation_enabled, false),
    'counseling', coalesce(counseling_enabled, false),
    'visibleRadio', coalesce(visible_radio_enabled, false),
    'visible_radio', coalesce(visible_radio_enabled, false),
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
    'investigation', false,
    'counseling', false,
    'visibleRadio', false,
    'visible_radio', false,
    'collection', true,
    'faq', true,
    'inquiry', true,
    'specialPack', false,
    'bbbSections', coalesce(v_bbb_sections, '{}'::jsonb)
  ));
end;
$$;

grant execute on function public.bu_tab_settings_json() to anon, authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
