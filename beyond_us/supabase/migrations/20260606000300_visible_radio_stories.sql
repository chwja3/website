-- 보이는 라디오 사연 탭과 익명 사연 수집 RPC를 추가한다.
begin;

create table if not exists public.visible_radio_stories (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(trim(content)) between 1 and 1000)
);

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'set_visible_radio_stories_updated_at'
  ) then
    create trigger set_visible_radio_stories_updated_at
    before update on public.visible_radio_stories
    for each row execute function public.set_updated_at();
  end if;
end;
$$;

create index if not exists visible_radio_stories_profile_idx
on public.visible_radio_stories (profile_id, created_at desc);

create index if not exists visible_radio_stories_created_idx
on public.visible_radio_stories (created_at desc);

alter table public.visible_radio_stories enable row level security;
revoke all on public.visible_radio_stories from public, anon, authenticated;

comment on table public.visible_radio_stories is '보이는 라디오 탭에서 받은 익명 사연. 작성자는 사용자 RPC 외에는 노출하지 않는다.';
comment on column public.visible_radio_stories.profile_id is '사연 작성자. 관리자 RPC에는 노출하지 않는다.';
comment on column public.visible_radio_stories.content is '보이는 라디오에 제출한 사연 본문.';

insert into public.tab_settings (tab_key, label, enabled, status, sort_order)
values ('visible_radio', '보이는 라디오', true, 'open', 86)
on conflict (tab_key) do update
set label = excluded.label,
    sort_order = excluded.sort_order,
    updated_at = now();

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

create or replace function public.get_visible_radio_stories(p_login_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_stories jsonb := '[]'::jsonb;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'content', content,
    'createdAt', created_at,
    'updatedAt', updated_at
  ) order by created_at desc), '[]'::jsonb)
  into v_stories
  from public.visible_radio_stories
  where profile_id = v_profile.id;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'stories', v_stories
  );
end;
$$;

create or replace function public.create_visible_radio_story(
  p_login_id text,
  p_content text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_content text := trim(coalesce(p_content, ''));
  v_id uuid;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if v_content = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_content');
  end if;

  if char_length(v_content) > 1000 then
    return jsonb_build_object('ok', false, 'error', 'content_too_long');
  end if;

  insert into public.visible_radio_stories (profile_id, content)
  values (v_profile.id, v_content)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'source', 'supabase', 'id', v_id);
end;
$$;

create or replace function public.update_visible_radio_story(
  p_login_id text,
  p_id uuid,
  p_content text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_content text := trim(coalesce(p_content, ''));
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if v_content = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_content');
  end if;

  if char_length(v_content) > 1000 then
    return jsonb_build_object('ok', false, 'error', 'content_too_long');
  end if;

  update public.visible_radio_stories
  set content = v_content,
      updated_at = now()
  where id = p_id
    and profile_id = v_profile.id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

create or replace function public.delete_visible_radio_story(
  p_login_id text,
  p_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  delete from public.visible_radio_stories
  where id = p_id
    and profile_id = v_profile.id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

create or replace function public.admin_get_visible_radio_stories()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_stories jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'content', content,
    'createdAt', created_at,
    'updatedAt', updated_at
  ) order by created_at desc), '[]'::jsonb)
  into v_stories
  from public.visible_radio_stories;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'stories', v_stories
  );
end;
$$;

revoke all on function public.get_visible_radio_stories(text) from public, anon, authenticated;
revoke all on function public.create_visible_radio_story(text, text) from public, anon, authenticated;
revoke all on function public.update_visible_radio_story(text, uuid, text) from public, anon, authenticated;
revoke all on function public.delete_visible_radio_story(text, uuid) from public, anon, authenticated;
revoke all on function public.admin_get_visible_radio_stories() from public, anon, authenticated;

grant execute on function public.get_visible_radio_stories(text) to authenticated;
grant execute on function public.create_visible_radio_story(text, text) to authenticated;
grant execute on function public.update_visible_radio_story(text, uuid, text) to authenticated;
grant execute on function public.delete_visible_radio_story(text, uuid) to authenticated;
grant execute on function public.admin_get_visible_radio_stories() to authenticated;

notify pgrst, 'reload schema';

commit;
