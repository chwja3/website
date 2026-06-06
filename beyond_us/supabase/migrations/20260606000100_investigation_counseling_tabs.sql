-- 광범위수사와 익명 고민상담 탭, 고민상담 사용자 RPC를 추가한다.
begin;

create table if not exists public.anonymous_counseling_entries (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  content text not null,
  public_visible boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(trim(content)) between 1 and 700)
);

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'set_anonymous_counseling_entries_updated_at'
  ) then
    create trigger set_anonymous_counseling_entries_updated_at
    before update on public.anonymous_counseling_entries
    for each row execute function public.set_updated_at();
  end if;
end;
$$;

create index if not exists anonymous_counseling_entries_profile_idx
on public.anonymous_counseling_entries (profile_id, created_at desc);

create index if not exists anonymous_counseling_entries_public_idx
on public.anonymous_counseling_entries (public_visible, created_at desc)
where public_visible = true;

alter table public.anonymous_counseling_entries enable row level security;
revoke all on public.anonymous_counseling_entries from public, anon, authenticated;

comment on table public.anonymous_counseling_entries is '익명 고민상담 탭에서 작성한 고민. 기본은 작성자 본인만 앱 RPC로 조회한다.';
comment on column public.anonymous_counseling_entries.profile_id is '고민 작성자. 앱 공개 목록에는 노출하지 않는다.';
comment on column public.anonymous_counseling_entries.public_visible is 'true이면 작성자 정보 없이 모든 로그인 유저에게 고민 내용만 공개한다.';

insert into public.tab_settings (tab_key, label, enabled, status, sort_order)
values
  ('investigation', '광범위수사', true, 'open', 65),
  ('counseling', '익명 고민상담', true, 'open', 85)
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
    'collection', true,
    'faq', true,
    'inquiry', true,
    'specialPack', false,
    'bbbSections', coalesce(v_bbb_sections, '{}'::jsonb)
  ));
end;
$$;

create or replace function public.get_counseling_entries(p_login_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_mine jsonb := '[]'::jsonb;
  v_public jsonb := '[]'::jsonb;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'content', content,
    'publicVisible', public_visible,
    'createdAt', created_at
  ) order by created_at desc), '[]'::jsonb)
  into v_mine
  from public.anonymous_counseling_entries
  where profile_id = v_profile.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'content', content,
    'createdAt', created_at
  ) order by created_at desc), '[]'::jsonb)
  into v_public
  from public.anonymous_counseling_entries
  where public_visible = true;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'mine', v_mine,
    'publicEntries', v_public
  );
end;
$$;

create or replace function public.create_counseling_entry(
  p_login_id text,
  p_content text,
  p_public_visible boolean default false
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

  if char_length(v_content) > 700 then
    return jsonb_build_object('ok', false, 'error', 'content_too_long');
  end if;

  insert into public.anonymous_counseling_entries (
    profile_id,
    content,
    public_visible
  )
  values (
    v_profile.id,
    v_content,
    coalesce(p_public_visible, false)
  )
  returning id into v_id;

  return jsonb_build_object('ok', true, 'source', 'supabase', 'id', v_id);
end;
$$;

create or replace function public.update_counseling_entry(
  p_login_id text,
  p_id uuid,
  p_content text,
  p_public_visible boolean default false
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

  if char_length(v_content) > 700 then
    return jsonb_build_object('ok', false, 'error', 'content_too_long');
  end if;

  update public.anonymous_counseling_entries
  set content = v_content,
      public_visible = coalesce(p_public_visible, false),
      updated_at = now()
  where id = p_id
    and profile_id = v_profile.id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

create or replace function public.delete_counseling_entry(
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

  delete from public.anonymous_counseling_entries
  where id = p_id
    and profile_id = v_profile.id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

revoke all on function public.get_counseling_entries(text) from public, anon, authenticated;
revoke all on function public.create_counseling_entry(text, text, boolean) from public, anon, authenticated;
revoke all on function public.update_counseling_entry(text, uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.delete_counseling_entry(text, uuid) from public, anon, authenticated;

grant execute on function public.get_counseling_entries(text) to authenticated;
grant execute on function public.create_counseling_entry(text, text, boolean) to authenticated;
grant execute on function public.update_counseling_entry(text, uuid, text, boolean) to authenticated;
grant execute on function public.delete_counseling_entry(text, uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
