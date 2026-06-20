-- BBB와 천로역정 오픈 상태가 부분 저장으로 깨진 경우를 보정한다.
begin;

insert into public.app_settings (key, value_json, value_type, note)
values (
  'bbb_settings',
  jsonb_build_object(
    'careBuddy', jsonb_build_object('open', true),
    'secretBuddy', jsonb_build_object('open', true),
    'm1', jsonb_build_object('open', true),
    'm2', jsonb_build_object('open', true),
    'm3', jsonb_build_object('open', true),
    'msgOpen', jsonb_build_object('open', true)
  ),
  'json',
  'B.B.B/천로역정 섹션 오픈 상태'
)
on conflict (key) do update
set value_json = coalesce(public.app_settings.value_json, '{}'::jsonb)
  || jsonb_build_object(
    'careBuddy', coalesce(public.app_settings.value_json -> 'careBuddy', '{}'::jsonb) || jsonb_build_object('open', true),
    'secretBuddy', coalesce(public.app_settings.value_json -> 'secretBuddy', '{}'::jsonb) || jsonb_build_object('open', true),
    'm1', coalesce(public.app_settings.value_json -> 'm1', '{}'::jsonb) || jsonb_build_object('open', true),
    'm2', coalesce(public.app_settings.value_json -> 'm2', '{}'::jsonb) || jsonb_build_object('open', true),
    'm3', coalesce(public.app_settings.value_json -> 'm3', '{}'::jsonb) || jsonb_build_object('open', true),
    'msgOpen', coalesce(public.app_settings.value_json -> 'msgOpen', '{}'::jsonb) || jsonb_build_object('open', true)
  ),
  value_type = 'json',
  note = 'B.B.B/천로역정 섹션 오픈 상태',
  updated_at = now();

insert into public.tab_settings (tab_key, label, enabled, status, sort_order)
values
  ('secret', 'B.B.B 미션', true, 'open', 20),
  ('pilgrim', '천로역정', true, 'open', 70)
on conflict (tab_key) do update
set label = excluded.label,
  enabled = true,
  status = 'open',
  sort_order = excluded.sort_order,
  updated_at = now();

select pg_notify('pgrst', 'reload schema');

commit;
