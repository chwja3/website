-- dev에서 main으로 반영할 Supabase migration 통합 실행 파일이다.
-- 생성일: 2026-06-14
-- 실행 순서: 아래 파일명 순서 그대로 Supabase SQL Editor에서 한 번에 실행한다.


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260606000100_investigation_counseling_tabs.sql
-- ============================================================================

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


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260606000200_admin_counseling_replies.sql
-- ============================================================================

-- 익명 고민상담에 관리자 답변 기능을 추가하고 작성자 익명성을 유지한다.
begin;

alter table public.anonymous_counseling_entries
add column if not exists reply text,
add column if not exists replied_by uuid references public.profiles(id) on delete set null,
add column if not exists replied_at timestamptz;

alter table public.anonymous_counseling_entries
drop constraint if exists anonymous_counseling_entries_reply_length;

alter table public.anonymous_counseling_entries
add constraint anonymous_counseling_entries_reply_length
check (reply is null or char_length(trim(reply)) <= 1200);

comment on column public.anonymous_counseling_entries.reply is '관리자가 작성한 익명 고민상담 답변.';
comment on column public.anonymous_counseling_entries.replied_by is '답변을 작성한 관리자 프로필. 사용자와 일반 관리자 화면에는 노출하지 않는다.';
comment on column public.anonymous_counseling_entries.replied_at is '관리자 답변이 마지막으로 저장된 시각.';

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
    'reply', nullif(reply, ''),
    'repliedAt', replied_at,
    'createdAt', created_at
  ) order by created_at desc), '[]'::jsonb)
  into v_mine
  from public.anonymous_counseling_entries
  where profile_id = v_profile.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'content', content,
    'reply', nullif(reply, ''),
    'repliedAt', replied_at,
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
      reply = case when content is distinct from v_content then null else reply end,
      replied_by = case when content is distinct from v_content then null else replied_by end,
      replied_at = case when content is distinct from v_content then null else replied_at end,
      updated_at = now()
  where id = p_id
    and profile_id = v_profile.id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

create or replace function public.admin_get_counseling_entries()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_entries jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'content', content,
    'publicVisible', public_visible,
    'reply', nullif(reply, ''),
    'repliedAt', replied_at,
    'createdAt', created_at
  ) order by created_at desc), '[]'::jsonb)
  into v_entries
  from public.anonymous_counseling_entries;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'entries', v_entries
  );
end;
$$;

create or replace function public.admin_reply_counseling_entry(
  p_id uuid,
  p_reply text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_reply text := trim(coalesce(p_reply, ''));
begin
  v_admin := public.bu_admin_profile();

  if char_length(v_reply) > 1200 then
    return jsonb_build_object('ok', false, 'error', 'reply_too_long');
  end if;

  update public.anonymous_counseling_entries
  set reply = nullif(v_reply, ''),
      replied_by = case when v_reply = '' then null else v_admin.id end,
      replied_at = case when v_reply = '' then null else now() end,
      updated_at = now()
  where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

revoke all on function public.get_counseling_entries(text) from public, anon, authenticated;
revoke all on function public.update_counseling_entry(text, uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.admin_get_counseling_entries() from public, anon, authenticated;
revoke all on function public.admin_reply_counseling_entry(uuid, text) from public, anon, authenticated;

grant execute on function public.get_counseling_entries(text) to authenticated;
grant execute on function public.update_counseling_entry(text, uuid, text, boolean) to authenticated;
grant execute on function public.admin_get_counseling_entries() to authenticated;
grant execute on function public.admin_reply_counseling_entry(uuid, text) to authenticated;

notify pgrst, 'reload schema';

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260606000300_visible_radio_stories.sql
-- ============================================================================

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


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260609000100_visible_radio_categories_trade_prayers.sql
-- ============================================================================

-- 보이는 라디오 카테고리와 교환 기도제목 조회를 보강한다.
begin;

alter table public.visible_radio_stories
  add column if not exists category_key text not null default 'mvp',
  add column if not exists category_label text not null default '우리 조 MVP',
  add column if not exists target_text text,
  add column if not exists status text not null default 'candidate',
  add column if not exists pinned_order integer;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'visible_radio_stories_category_key_check'
  ) then
    alter table public.visible_radio_stories
      add constraint visible_radio_stories_category_key_check
      check (category_key in ('mvp', 'buddy', 'moment', 'sorry', 'cheer', 'funny_praise'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'visible_radio_stories_status_check'
  ) then
    alter table public.visible_radio_stories
      add constraint visible_radio_stories_status_check
      check (status in ('candidate', 'hold', 'excluded'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'visible_radio_stories_target_text_length'
  ) then
    alter table public.visible_radio_stories
      add constraint visible_radio_stories_target_text_length
      check (target_text is null or char_length(trim(target_text)) <= 80);
  end if;
end;
$$;

create index if not exists visible_radio_stories_category_created_idx
on public.visible_radio_stories (category_key, created_at desc);

create index if not exists visible_radio_stories_status_created_idx
on public.visible_radio_stories (status, created_at desc);

create or replace function public.bu_visible_radio_category_label(p_key text)
returns text
language sql
immutable
as $$
  select case coalesce(p_key, 'mvp')
    when 'mvp' then '우리 조 MVP'
    when 'buddy' then '버디에게'
    when 'moment' then '감동의 순간'
    when 'sorry' then '미안했어요'
    when 'cheer' then '응원 한마디'
    when 'funny_praise' then '익명 폭로(?) 칭찬'
    else '우리 조 MVP'
  end;
$$;

update public.visible_radio_stories
set category_key = case
      when category_key in ('mvp', 'buddy', 'moment', 'sorry', 'cheer', 'funny_praise') then category_key
      else 'mvp'
    end,
    category_label = public.bu_visible_radio_category_label(
      case
        when category_key in ('mvp', 'buddy', 'moment', 'sorry', 'cheer', 'funny_praise') then category_key
        else 'mvp'
      end
    ),
    status = case
      when status in ('candidate', 'hold', 'excluded') then status
      else 'candidate'
    end;

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
    'categoryKey', category_key,
    'categoryLabel', category_label,
    'targetText', coalesce(target_text, ''),
    'status', status,
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
  p_category_key text,
  p_target_text text,
  p_content text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_category_key text := lower(trim(coalesce(p_category_key, 'mvp')));
  v_target_text text := nullif(trim(coalesce(p_target_text, '')), '');
  v_content text := trim(coalesce(p_content, ''));
  v_id uuid;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if v_category_key not in ('mvp', 'buddy', 'moment', 'sorry', 'cheer', 'funny_praise') then
    v_category_key := 'mvp';
  end if;

  if v_content = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_content');
  end if;

  if char_length(v_content) > 1000 then
    return jsonb_build_object('ok', false, 'error', 'content_too_long');
  end if;

  if v_target_text is not null and char_length(v_target_text) > 80 then
    return jsonb_build_object('ok', false, 'error', 'target_too_long');
  end if;

  insert into public.visible_radio_stories (
    profile_id,
    category_key,
    category_label,
    target_text,
    content
  )
  values (
    v_profile.id,
    v_category_key,
    public.bu_visible_radio_category_label(v_category_key),
    v_target_text,
    v_content
  )
  returning id into v_id;

  return jsonb_build_object('ok', true, 'source', 'supabase', 'id', v_id);
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
begin
  return public.create_visible_radio_story(p_login_id, 'mvp', null, p_content);
end;
$$;

create or replace function public.update_visible_radio_story(
  p_login_id text,
  p_id uuid,
  p_category_key text,
  p_target_text text,
  p_content text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_category_key text := lower(trim(coalesce(p_category_key, 'mvp')));
  v_target_text text := nullif(trim(coalesce(p_target_text, '')), '');
  v_content text := trim(coalesce(p_content, ''));
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if v_category_key not in ('mvp', 'buddy', 'moment', 'sorry', 'cheer', 'funny_praise') then
    v_category_key := 'mvp';
  end if;

  if v_content = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_content');
  end if;

  if char_length(v_content) > 1000 then
    return jsonb_build_object('ok', false, 'error', 'content_too_long');
  end if;

  if v_target_text is not null and char_length(v_target_text) > 80 then
    return jsonb_build_object('ok', false, 'error', 'target_too_long');
  end if;

  update public.visible_radio_stories
  set category_key = v_category_key,
      category_label = public.bu_visible_radio_category_label(v_category_key),
      target_text = v_target_text,
      content = v_content,
      updated_at = now()
  where id = p_id
    and profile_id = v_profile.id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'source', 'supabase');
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
begin
  return public.update_visible_radio_story(p_login_id, p_id, 'mvp', null, p_content);
end;
$$;

create or replace function public.admin_get_visible_radio_stories(
  p_category_key text,
  p_query text,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_category_key text := nullif(lower(trim(coalesce(p_category_key, ''))), '');
  v_query text := lower(trim(coalesce(p_query, '')));
  v_status text := nullif(lower(trim(coalesce(p_status, ''))), '');
  v_stories jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  if v_category_key is not null and v_category_key not in ('mvp', 'buddy', 'moment', 'sorry', 'cheer', 'funny_praise') then
    v_category_key := null;
  end if;

  if v_status is not null and v_status not in ('candidate', 'hold', 'excluded') then
    v_status := null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'categoryKey', category_key,
    'categoryLabel', category_label,
    'targetText', coalesce(target_text, ''),
    'status', status,
    'content', content,
    'createdAt', created_at,
    'updatedAt', updated_at
  ) order by created_at desc), '[]'::jsonb)
  into v_stories
  from public.visible_radio_stories
  where (v_category_key is null or category_key = v_category_key)
    and (v_status is null or status = v_status)
    and (
      v_query = ''
      or lower(content) like '%' || v_query || '%'
      or lower(coalesce(target_text, '')) like '%' || v_query || '%'
      or lower(category_label) like '%' || v_query || '%'
    );

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'stories', v_stories
  );
end;
$$;

create or replace function public.admin_get_visible_radio_stories()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.admin_get_visible_radio_stories(null, null, null);
end;
$$;

create or replace function public.admin_update_visible_radio_story_status(
  p_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_status text := lower(trim(coalesce(p_status, 'candidate')));
begin
  v_admin := public.bu_admin_profile();

  if v_status not in ('candidate', 'hold', 'excluded') then
    return jsonb_build_object('ok', false, 'error', 'invalid_status');
  end if;

  update public.visible_radio_stories
  set status = v_status,
      updated_at = now()
  where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

create or replace function public.bu_trade_prayer_for_profile(p_profile_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select trim(h.content)
    from public.hold_pray_entries h
    where h.profile_id = p_profile_id
      and h.visible = true
      and trim(coalesce(h.content, '')) <> ''
    order by
      case when h.week_key = 'w' || public.bu_current_week()::text then 0 else 1 end,
      h.created_at desc
    limit 1
  ), '');
$$;

create or replace function public.get_user_trades(p_login_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_incoming jsonb := '[]'::jsonb;
  v_outgoing jsonb := '[]'::jsonb;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  with trade_rows as (
    select
      t.*,
      rp.login_id as requester_login_id,
      tp.login_id as target_login_id,
      rc.name as requester_card_name,
      tc.name as target_card_name,
      exists(select 1 from public.trade_prayers pr where pr.trade_id = t.id and pr.profile_id = t.requester_id) as requester_prayed,
      exists(select 1 from public.trade_prayers pr where pr.trade_id = t.id and pr.profile_id = t.target_id) as target_prayed
    from public.trades t
    join public.profiles rp on rp.id = t.requester_id
    join public.profiles tp on tp.id = t.target_id
    join public.cards rc on rc.id = t.requester_card_id
    join public.cards tc on tc.id = t.target_card_id
    where t.target_id = v_profile.id
    order by t.created_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'status', case when status::text = 'requested' then 'pending' else status::text end,
    'requester', requester_login_id,
    'target', target_login_id,
    'requesterCardId', requester_card_id,
    'targetCardId', target_card_id,
    'requesterCardName', requester_card_name,
    'targetCardName', target_card_name,
    'requesterPrayed', requester_prayed,
    'targetPrayed', target_prayed,
    'otherPrayer', public.bu_trade_prayer_for_profile(requester_id),
    'createdAt', created_at,
    'resolvedAt', resolved_at
  ) order by created_at desc), '[]'::jsonb)
  into v_incoming
  from trade_rows;

  with trade_rows as (
    select
      t.*,
      rp.login_id as requester_login_id,
      tp.login_id as target_login_id,
      rc.name as requester_card_name,
      tc.name as target_card_name,
      exists(select 1 from public.trade_prayers pr where pr.trade_id = t.id and pr.profile_id = t.requester_id) as requester_prayed,
      exists(select 1 from public.trade_prayers pr where pr.trade_id = t.id and pr.profile_id = t.target_id) as target_prayed
    from public.trades t
    join public.profiles rp on rp.id = t.requester_id
    join public.profiles tp on tp.id = t.target_id
    join public.cards rc on rc.id = t.requester_card_id
    join public.cards tc on tc.id = t.target_card_id
    where t.requester_id = v_profile.id
    order by t.created_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'status', case when status::text = 'requested' then 'pending' else status::text end,
    'requester', requester_login_id,
    'target', target_login_id,
    'requesterCardId', requester_card_id,
    'targetCardId', target_card_id,
    'requesterCardName', requester_card_name,
    'targetCardName', target_card_name,
    'requesterPrayed', requester_prayed,
    'targetPrayed', target_prayed,
    'otherPrayer', public.bu_trade_prayer_for_profile(target_id),
    'createdAt', created_at,
    'resolvedAt', resolved_at
  ) order by created_at desc), '[]'::jsonb)
  into v_outgoing
  from trade_rows;

  return jsonb_build_object('ok', true, 'source', 'supabase', 'incoming', v_incoming, 'outgoing', v_outgoing);
end;
$$;

revoke all on function public.bu_visible_radio_category_label(text) from public, anon, authenticated;
revoke all on function public.get_visible_radio_stories(text) from public, anon, authenticated;
revoke all on function public.create_visible_radio_story(text, text, text, text) from public, anon, authenticated;
revoke all on function public.create_visible_radio_story(text, text) from public, anon, authenticated;
revoke all on function public.update_visible_radio_story(text, uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.update_visible_radio_story(text, uuid, text) from public, anon, authenticated;
revoke all on function public.delete_visible_radio_story(text, uuid) from public, anon, authenticated;
revoke all on function public.admin_get_visible_radio_stories(text, text, text) from public, anon, authenticated;
revoke all on function public.admin_get_visible_radio_stories() from public, anon, authenticated;
revoke all on function public.admin_update_visible_radio_story_status(uuid, text) from public, anon, authenticated;
revoke all on function public.bu_trade_prayer_for_profile(uuid) from public, anon, authenticated;
revoke all on function public.get_user_trades(text) from public, anon, authenticated;

grant execute on function public.get_visible_radio_stories(text) to authenticated;
grant execute on function public.create_visible_radio_story(text, text, text, text) to authenticated;
grant execute on function public.create_visible_radio_story(text, text) to authenticated;
grant execute on function public.update_visible_radio_story(text, uuid, text, text, text) to authenticated;
grant execute on function public.update_visible_radio_story(text, uuid, text) to authenticated;
grant execute on function public.delete_visible_radio_story(text, uuid) to authenticated;
grant execute on function public.admin_get_visible_radio_stories(text, text, text) to authenticated;
grant execute on function public.admin_get_visible_radio_stories() to authenticated;
grant execute on function public.admin_update_visible_radio_story_status(uuid, text) to authenticated;
grant execute on function public.get_user_trades(text) to authenticated;

notify pgrst, 'reload schema';

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260612000100_trade_prayer_exclude_anonymous.sql
-- ============================================================================

-- 교환현황(get_user_trades) 상대 기도제목 노출에서 익명 entry를 제외한다.
-- 교환현황 화면은 상대 닉네임이 이미 노출되므로 익명 entry를 보여주면 익명의 의미가 사라진다.
-- H&P 캐러셀 등 다른 화면의 익명 동작에는 영향 없음 (bu_trade_prayer_for_profile만 수정).
begin;

create or replace function public.bu_trade_prayer_for_profile(p_profile_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select trim(h.content)
    from public.hold_pray_entries h
    where h.profile_id = p_profile_id
      and h.visible = true
      and coalesce(h.anonymous, false) = false
      and trim(coalesce(h.content, '')) <> ''
    order by
      case when h.week_key = 'w' || public.bu_current_week()::text then 0 else 1 end,
      h.created_at desc
    limit 1
  ), '');
$$;

notify pgrst, 'reload schema';

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260612000200_visible_radio_nickname_option.sql
-- ============================================================================

-- 별빛 우편함: 사연 제출 시 닉네임 공개 기본, 익명 옵션 추가.
-- 어드민(라디오 사회자) 화면에서 비익명 사연은 {교구} {닉네임} 노출, 익명은 숨김.
begin;

alter table public.visible_radio_stories
  add column if not exists is_anonymous boolean not null default false;

-- 사용자 본인 사연 조회: isAnonymous 포함
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
    'categoryKey', category_key,
    'categoryLabel', category_label,
    'targetText', coalesce(target_text, ''),
    'status', status,
    'content', content,
    'isAnonymous', coalesce(is_anonymous, false),
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

-- 새 사연 작성: is_anonymous 파라미터 받는 overload 추가
create or replace function public.create_visible_radio_story(
  p_login_id text,
  p_category_key text,
  p_target_text text,
  p_content text,
  p_is_anonymous boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_category_key text := lower(trim(coalesce(p_category_key, 'mvp')));
  v_target_text text := nullif(trim(coalesce(p_target_text, '')), '');
  v_content text := trim(coalesce(p_content, ''));
  v_id uuid;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if v_category_key not in ('mvp', 'buddy', 'moment', 'sorry', 'cheer', 'funny_praise') then
    v_category_key := 'mvp';
  end if;

  if v_content = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_content');
  end if;

  if char_length(v_content) > 1000 then
    return jsonb_build_object('ok', false, 'error', 'content_too_long');
  end if;

  if v_target_text is not null and char_length(v_target_text) > 80 then
    return jsonb_build_object('ok', false, 'error', 'target_too_long');
  end if;

  insert into public.visible_radio_stories (
    profile_id,
    category_key,
    category_label,
    target_text,
    content,
    is_anonymous
  )
  values (
    v_profile.id,
    v_category_key,
    public.bu_visible_radio_category_label(v_category_key),
    v_target_text,
    v_content,
    coalesce(p_is_anonymous, false)
  )
  returning id into v_id;

  return jsonb_build_object('ok', true, 'source', 'supabase', 'id', v_id);
end;
$$;

-- 사연 수정: is_anonymous 파라미터 받는 overload 추가
create or replace function public.update_visible_radio_story(
  p_login_id text,
  p_id uuid,
  p_category_key text,
  p_target_text text,
  p_content text,
  p_is_anonymous boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_category_key text := lower(trim(coalesce(p_category_key, 'mvp')));
  v_target_text text := nullif(trim(coalesce(p_target_text, '')), '');
  v_content text := trim(coalesce(p_content, ''));
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if v_category_key not in ('mvp', 'buddy', 'moment', 'sorry', 'cheer', 'funny_praise') then
    v_category_key := 'mvp';
  end if;

  if v_content = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_content');
  end if;

  if char_length(v_content) > 1000 then
    return jsonb_build_object('ok', false, 'error', 'content_too_long');
  end if;

  if v_target_text is not null and char_length(v_target_text) > 80 then
    return jsonb_build_object('ok', false, 'error', 'target_too_long');
  end if;

  update public.visible_radio_stories
  set category_key = v_category_key,
      category_label = public.bu_visible_radio_category_label(v_category_key),
      target_text = v_target_text,
      content = v_content,
      is_anonymous = coalesce(p_is_anonymous, false),
      updated_at = now()
  where id = p_id
    and profile_id = v_profile.id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

-- 어드민 사연 조회: 비익명이면 작성자 닉네임/교구 노출, 익명이면 숨김
create or replace function public.admin_get_visible_radio_stories(
  p_category_key text,
  p_query text,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_category_key text := nullif(lower(trim(coalesce(p_category_key, ''))), '');
  v_query text := lower(trim(coalesce(p_query, '')));
  v_status text := nullif(lower(trim(coalesce(p_status, ''))), '');
  v_stories jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  if v_category_key is not null and v_category_key not in ('mvp', 'buddy', 'moment', 'sorry', 'cheer', 'funny_praise') then
    v_category_key := null;
  end if;

  if v_status is not null and v_status not in ('candidate', 'hold', 'excluded') then
    v_status := null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'categoryKey', s.category_key,
    'categoryLabel', s.category_label,
    'targetText', coalesce(s.target_text, ''),
    'status', s.status,
    'content', s.content,
    'isAnonymous', coalesce(s.is_anonymous, false),
    'authorNickname', case when coalesce(s.is_anonymous, false) then '' else coalesce(p.login_id::text, '') end,
    'authorParish', case when coalesce(s.is_anonymous, false) then '' else coalesce(p.parish, '') end,
    'createdAt', s.created_at,
    'updatedAt', s.updated_at
  ) order by s.created_at desc), '[]'::jsonb)
  into v_stories
  from public.visible_radio_stories s
  left join public.profiles p on p.id = s.profile_id
  where (v_category_key is null or s.category_key = v_category_key)
    and (v_status is null or s.status = v_status)
    and (
      v_query = ''
      or lower(s.content) like '%' || v_query || '%'
      or lower(coalesce(s.target_text, '')) like '%' || v_query || '%'
      or lower(s.category_label) like '%' || v_query || '%'
      or (not coalesce(s.is_anonymous, false) and lower(coalesce(p.login_id::text, '')) like '%' || v_query || '%')
    );

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'stories', v_stories
  );
end;
$$;

revoke all on function public.create_visible_radio_story(text, text, text, text, boolean) from public, anon, authenticated;
revoke all on function public.update_visible_radio_story(text, uuid, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.create_visible_radio_story(text, text, text, text, boolean) to authenticated;
grant execute on function public.update_visible_radio_story(text, uuid, text, text, text, boolean) to authenticated;

notify pgrst, 'reload schema';

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260612000300_admin_direct_card_pack_grant.sql
-- ============================================================================

-- 관리자 앱 가입자 탭에서 카드 뽑기권을 직접 1장 지급하는 RPC를 추가한다.
begin;

create or replace function public.admin_grant_card_pack_ticket(
  p_login_id text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_remaining integer := 0;
  v_event_id uuid;
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

  perform pg_advisory_xact_lock(hashtext('admin_grant_card_pack_ticket:' || v_profile.id::text));

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
      updated_at = now()
  returning normal_pack_remaining into v_remaining;

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    ref_id,
    amount,
    payload,
    source,
    created_by
  )
  values (
    v_profile.id,
    'ticket.granted',
    'admin_manual',
    gen_random_uuid()::text,
    1,
    jsonb_build_object(
      'reason', 'admin_manual_card_pack',
      'reasonText', coalesce(v_reason, '운영 수동 지급'),
      'adminManual', true
    ),
    'admin',
    v_admin.id
  )
  returning id into v_event_id;

  perform public.bu_refresh_profile_summary(v_profile.id);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'user', v_profile.login_id,
    'eventId', v_event_id,
    'normalPackRemaining', coalesce(v_remaining, 0)
  );
end;
$$;

revoke all on function public.admin_grant_card_pack_ticket(text, text) from public, anon, authenticated;
grant execute on function public.admin_grant_card_pack_ticket(text, text) to authenticated;

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260612000400_qt_reflection_structure.sql
-- ============================================================================

-- QT 말씀 묵상 답변과 기도제목을 사용자별 날짜 단위로 저장하는 구조를 추가한다.
begin;

create table if not exists public.qt_submissions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  content_date date not null,
  answer_text text not null default '',
  prayer_text text not null default '',
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (profile_id, content_date),
  check (char_length(answer_text) <= 1200),
  check (char_length(prayer_text) <= 800)
);

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'set_qt_submissions_updated_at'
  ) then
    create trigger set_qt_submissions_updated_at
    before update on public.qt_submissions
    for each row execute function public.set_updated_at();
  end if;
end $$;

create index if not exists qt_submissions_profile_date_idx
on public.qt_submissions (profile_id, content_date desc);

alter table public.qt_submissions enable row level security;
revoke all on public.qt_submissions from public, anon, authenticated;

comment on table public.qt_submissions is '사용자별 Q.T. 말씀 묵상 답변과 기도제목 제출 내역.';
comment on column public.qt_submissions.content_date is 'QT 본문이 표시된 날짜.';
comment on column public.qt_submissions.answer_text is '사용자가 작성한 QT 질문 답변.';
comment on column public.qt_submissions.prayer_text is '사용자가 작성한 기도제목.';

create or replace function public.bu_qt_content_date(p_content_date date default null)
returns date
language sql
stable
set search_path = public
as $$
  select coalesce(p_content_date, (now() at time zone 'Asia/Seoul')::date);
$$;

create or replace function public.get_qt_reflection(
  p_login_id text,
  p_content_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_content_date date := public.bu_qt_content_date(p_content_date);
  v_submission public.qt_submissions%rowtype;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  select *
  into v_submission
  from public.qt_submissions
  where profile_id = v_profile.id
    and content_date = v_content_date
  limit 1;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'contentDate', v_content_date,
    'answerText', coalesce(v_submission.answer_text, ''),
    'prayerText', coalesce(v_submission.prayer_text, ''),
    'submittedAt', v_submission.submitted_at
  );
end;
$$;

create or replace function public.submit_qt_reflection(
  p_login_id text,
  p_content_date date,
  p_answer_text text,
  p_prayer_text text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_content_date date := public.bu_qt_content_date(p_content_date);
  v_answer text := left(trim(coalesce(p_answer_text, '')), 1200);
  v_prayer text := left(trim(coalesce(p_prayer_text, '')), 800);
  v_submission_id uuid;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if v_answer = '' and v_prayer = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_qt_reflection');
  end if;

  insert into public.qt_submissions (
    profile_id,
    content_date,
    answer_text,
    prayer_text,
    submitted_at
  )
  values (
    v_profile.id,
    v_content_date,
    v_answer,
    v_prayer,
    now()
  )
  on conflict (profile_id, content_date) do update
  set answer_text = excluded.answer_text,
      prayer_text = excluded.prayer_text,
      updated_at = now()
  returning id into v_submission_id;

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    ref_id,
    amount,
    payload,
    source
  )
  values (
    v_profile.id,
    'qt.submitted',
    'qt',
    v_content_date::text,
    1,
    jsonb_build_object(
      'contentDate', v_content_date,
      'hasAnswer', v_answer <> '',
      'hasPrayer', v_prayer <> ''
    ),
    'web'
  );

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'id', v_submission_id,
    'contentDate', v_content_date
  );
end;
$$;

revoke all on function public.bu_qt_content_date(date) from public, anon, authenticated;
revoke all on function public.get_qt_reflection(text, date) from public, anon, authenticated;
revoke all on function public.submit_qt_reflection(text, date, text, text) from public, anon, authenticated;

grant execute on function public.bu_qt_content_date(date) to authenticated;
grant execute on function public.get_qt_reflection(text, date) to authenticated;
grant execute on function public.submit_qt_reflection(text, date, text, text) to authenticated;

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260612000500_admin_direct_raffle_ticket_grant.sql
-- ============================================================================

-- 관리자 앱 가입자 탭에서 추첨권을 직접 1장 지급하는 RPC를 추가한다.
begin;

create or replace function public.admin_grant_raffle_ticket(
  p_login_id text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_condition_key text := 'admin_manual_' || replace(gen_random_uuid()::text, '-', '');
  v_condition_label text := coalesce(v_reason, '운영 수동 지급');
  v_issue_result jsonb;
  v_event_id uuid;
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

  if coalesce(v_profile.raffle_excluded, false) then
    return jsonb_build_object('ok', false, 'error', 'raffle_excluded');
  end if;

  insert into public.raffle_conditions (
    condition_key,
    label,
    enabled,
    sort_order
  )
  values (
    v_condition_key,
    v_condition_label,
    true,
    9000
  );

  v_issue_result := public.bu_issue_raffle_ticket(
    v_profile.id,
    v_condition_key,
    'admin',
    v_admin.id
  );

  if coalesce((v_issue_result->>'issued')::boolean, false) = false then
    return jsonb_build_object(
      'ok', false,
      'error', coalesce(v_issue_result->>'reason', 'raffle_issue_failed'),
      'issueResult', v_issue_result
    );
  end if;

  v_event_id := nullif(v_issue_result->>'eventId', '')::uuid;

  if v_event_id is not null then
    update public.events
    set payload = coalesce(payload, '{}'::jsonb) || jsonb_build_object(
          'reason', 'admin_manual_raffle',
          'reasonText', v_condition_label,
          'adminManual', true
        )
    where id = v_event_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'user', v_profile.login_id,
    'ticketNo', v_issue_result->>'ticketNo',
    'eventId', v_issue_result->>'eventId',
    'conditionKey', v_condition_key,
    'activeCount', coalesce((v_issue_result->>'activeCount')::integer, 0)
  );
end;
$$;

revoke all on function public.admin_grant_raffle_ticket(text, text) from public, anon, authenticated;
grant execute on function public.admin_grant_raffle_ticket(text, text) to authenticated;

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260612000600_admin_ticket_status_revoke.sql
-- ============================================================================

-- 관리자 앱 가입자 탭에서 유저별 추첨권 현황 조회와 단일 회수를 처리한다.
begin;

create or replace function public.admin_get_profile_raffle_tickets(
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
  v_tickets jsonb := '[]'::jsonb;
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

  select coalesce(jsonb_agg(jsonb_build_object(
    'ticketNo', lpad(rt.ticket_no::text, 4, '0'),
    'conditionKey', rt.condition_key,
    'conditionLabel', coalesce(rc.label, rt.condition_key, '추첨권'),
    'issuedAt', rt.issued_at,
    'eventId', rt.event_id
  ) order by rt.ticket_no), '[]'::jsonb)
  into v_tickets
  from public.raffle_tickets rt
  left join public.raffle_conditions rc on rc.condition_key = rt.condition_key
  where rt.profile_id = v_profile.id
    and rt.active = true;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'admin', v_admin.login_id,
    'user', jsonb_build_object(
      'nickname', v_profile.login_id,
      'name', v_profile.name,
      'parish', v_profile.parish,
      'raffleExcluded', v_profile.raffle_excluded
    ),
    'activeCount', jsonb_array_length(v_tickets),
    'tickets', v_tickets
  );
end;
$$;

create or replace function public.admin_revoke_raffle_ticket(
  p_login_id text,
  p_ticket_no text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_ticket_no integer;
  v_ticket record;
  v_reason text := coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'admin_manual_revoke');
  v_event_id uuid;
  v_active_count integer := 0;
begin
  v_admin := public.bu_admin_profile();

  begin
    v_ticket_no := nullif(regexp_replace(coalesce(p_ticket_no, ''), '\D', '', 'g'), '')::integer;
  exception when invalid_text_representation then
    v_ticket_no := null;
  end;

  if v_ticket_no is null then
    return jsonb_build_object('ok', false, 'error', 'missing_ticket_no');
  end if;

  select *
  into v_profile
  from public.profiles
  where login_id = p_login_id
    and account_status = 'active'
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'error', 'user_not_found');
  end if;

  perform pg_advisory_xact_lock(hashtext('raffle_ticket_issue'), 0);
  perform pg_advisory_xact_lock(hashtext('raffle_ticket_profile'), hashtext(v_profile.id::text));

  select rt.ticket_no, rt.condition_key
  into v_ticket
  from public.raffle_tickets rt
  where rt.ticket_no = v_ticket_no
    and rt.profile_id = v_profile.id
    and rt.active = true
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'ticket_not_found');
  end if;

  update public.raffle_tickets
  set active = false,
      profile_id = null,
      condition_key = null,
      event_id = null,
      revoked_at = now(),
      revoked_reason = v_reason,
      updated_at = now()
  where ticket_no = v_ticket.ticket_no;

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    ref_id,
    amount,
    payload,
    source,
    created_by
  )
  values (
    v_profile.id,
    'raffle.revoked',
    'raffle_ticket',
    v_ticket.ticket_no::text,
    -1,
    jsonb_build_object(
      'conditionKey', v_ticket.condition_key,
      'ticketNo', lpad(v_ticket.ticket_no::text, 4, '0'),
      'reason', v_reason,
      'adminManual', true
    ),
    'admin',
    v_admin.id
  )
  returning id into v_event_id;

  v_active_count := public.bu_update_raffle_summary(v_profile.id);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'user', v_profile.login_id,
    'ticketNo', lpad(v_ticket.ticket_no::text, 4, '0'),
    'conditionKey', v_ticket.condition_key,
    'eventId', v_event_id,
    'activeCount', v_active_count
  );
end;
$$;

revoke all on function public.admin_get_profile_raffle_tickets(text) from public, anon, authenticated;
revoke all on function public.admin_revoke_raffle_ticket(text, text, text) from public, anon, authenticated;

grant execute on function public.admin_get_profile_raffle_tickets(text) to authenticated;
grant execute on function public.admin_revoke_raffle_ticket(text, text, text) to authenticated;

notify pgrst, 'reload schema';

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260612000700_admin_ticket_status_rpc.sql
-- ============================================================================

-- 관리자 앱 가입자 탭의 뽑기권/추첨권 현황 조회 RPC를 추가한다.
begin;

create or replace function public.admin_get_user_ticket_status(
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
  v_inventory public.user_inventory%rowtype;
  v_raffle_count integer := 0;
  v_card_count integer := 0;
  v_tickets jsonb := '[]'::jsonb;
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

  select coalesce(jsonb_agg(jsonb_build_object(
    'ticketNo', lpad(rt.ticket_no::text, 4, '0'),
    'conditionKey', rt.condition_key,
    'conditionLabel', coalesce(rc.label, rt.condition_key, '추첨권'),
    'issuedAt', rt.issued_at,
    'eventId', rt.event_id
  ) order by rt.ticket_no), '[]'::jsonb)
  into v_tickets
  from public.raffle_tickets rt
  left join public.raffle_conditions rc on rc.condition_key = rt.condition_key
  where rt.profile_id = v_profile.id
    and rt.active = true;

  v_raffle_count := jsonb_array_length(v_tickets);
  v_card_count := public.bu_raffle_card_count(v_profile.id);

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
    'activeRaffleTickets', v_tickets,
    'rewards', '[]'::jsonb
  );
end;
$$;

revoke all on function public.admin_get_user_ticket_status(text) from public, anon, authenticated;
grant execute on function public.admin_get_user_ticket_status(text) to authenticated;

notify pgrst, 'reload schema';

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260612000800_admin_card_pack_missed_rewards.sql
-- ============================================================================

-- 관리자 현황 카드에 카드 뽑기권 누락 보상 조회와 지급을 복원한다.
begin;

create or replace function public.admin_get_user_ticket_status(
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
  v_inventory public.user_inventory%rowtype;
  v_raffle_count integer := 0;
  v_card_count integer := 0;
  v_tickets jsonb := '[]'::jsonb;
  v_rewards jsonb := '[]'::jsonb;
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

  select coalesce(jsonb_agg(jsonb_build_object(
    'ticketNo', lpad(rt.ticket_no::text, 4, '0'),
    'conditionKey', rt.condition_key,
    'conditionLabel', coalesce(rc.label, rt.condition_key, '추첨권'),
    'issuedAt', rt.issued_at,
    'eventId', rt.event_id
  ) order by rt.ticket_no), '[]'::jsonb)
  into v_tickets
  from public.raffle_tickets rt
  left join public.raffle_conditions rc on rc.condition_key = rt.condition_key
  where rt.profile_id = v_profile.id
    and rt.active = true;

  v_raffle_count := jsonb_array_length(v_tickets);
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
      when not v_condition_met then 'condition_not_met'
      else null
    end;

    v_rewards := v_rewards || jsonb_build_array(jsonb_build_object(
      'rewardKey', 'mission_' || v_week.week_key,
      'type', 'card_pack',
      'label', coalesce(v_week.title, v_week.week_key) || ' 사전미션 카드 뽑기권',
      'description', '사전미션 주차 점수 ' || v_week.draw_threshold::text || '점 달성 보상',
      'conditionMet', v_condition_met,
      'claimed', v_claimed,
      'available', v_condition_met and not v_claimed,
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
      when not v_condition_met then 'condition_not_met'
      else null
    end;

    v_rewards := v_rewards || jsonb_build_array(jsonb_build_object(
      'rewardKey', 'hp_' || v_week.week_key,
      'type', 'card_pack',
      'label', v_week.title,
      'description', 'H&P 정답 1개 이상 보상',
      'conditionMet', v_condition_met,
      'claimed', v_claimed,
      'available', v_condition_met and not v_claimed,
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
    'activeRaffleTickets', v_tickets,
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
  v_week public.mission_weeks%rowtype;
  v_condition_met boolean := false;
  v_claimed boolean := false;
  v_card_index integer := null;
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

  perform pg_advisory_xact_lock(hashtext('admin_card_pack_reward:' || v_profile.id::text || ':' || v_reward_key));

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

    if not v_condition_met then
      return jsonb_build_object('ok', false, 'error', 'condition_not_met');
    end if;

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
      'user', v_profile.login_id
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

    if not v_condition_met then
      return jsonb_build_object('ok', false, 'error', 'condition_not_met');
    end if;

    if v_claimed then
      return jsonb_build_object('ok', false, 'error', 'already_claimed');
    end if;

    if not public.bu_award_hold_pray_ticket_if_eligible(v_profile.id, v_week_key, v_card_index, 'admin') then
      return jsonb_build_object('ok', false, 'error', 'issue_failed');
    end if;

    return jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'issued', true,
      'type', 'card_pack',
      'rewardKey', v_reward_key,
      'user', v_profile.login_id
    );
  end if;

  return jsonb_build_object('ok', false, 'error', 'unsupported_reward');
end;
$$;

revoke all on function public.admin_get_user_ticket_status(text) from public, anon, authenticated;
revoke all on function public.admin_issue_user_missed_reward(text, text) from public, anon, authenticated;

grant execute on function public.admin_get_user_ticket_status(text) to authenticated;
grant execute on function public.admin_issue_user_missed_reward(text, text) to authenticated;

notify pgrst, 'reload schema';

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260612000900_admin_card_pack_allow_unmet.sql
-- ============================================================================

-- 관리자 카드 뽑기권 보상을 조건 미충족이어도 미지급이면 지급 가능하게 한다.
begin;

create or replace function public.admin_get_user_ticket_status(
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
  v_inventory public.user_inventory%rowtype;
  v_raffle_count integer := 0;
  v_card_count integer := 0;
  v_tickets jsonb := '[]'::jsonb;
  v_rewards jsonb := '[]'::jsonb;
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

  select coalesce(jsonb_agg(jsonb_build_object(
    'ticketNo', lpad(rt.ticket_no::text, 4, '0'),
    'conditionKey', rt.condition_key,
    'conditionLabel', coalesce(rc.label, rt.condition_key, '추첨권'),
    'issuedAt', rt.issued_at,
    'eventId', rt.event_id
  ) order by rt.ticket_no), '[]'::jsonb)
  into v_tickets
  from public.raffle_tickets rt
  left join public.raffle_conditions rc on rc.condition_key = rt.condition_key
  where rt.profile_id = v_profile.id
    and rt.active = true;

  v_raffle_count := jsonb_array_length(v_tickets);
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
      'description', '사전미션 주차 점수 ' || v_week.draw_threshold::text || '점 기준 보상',
      'conditionMet', v_condition_met,
      'claimed', v_claimed,
      'available', not v_claimed,
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
      'description', 'H&P 보정용 카드 뽑기권',
      'conditionMet', v_condition_met,
      'claimed', v_claimed,
      'available', not v_claimed,
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
    'activeRaffleTickets', v_tickets,
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
  v_week public.mission_weeks%rowtype;
  v_condition_met boolean := false;
  v_claimed boolean := false;
  v_card_index integer := null;
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

  perform pg_advisory_xact_lock(hashtext('admin_card_pack_reward:' || v_profile.id::text || ':' || v_reward_key));

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
        'adminOverride', not v_condition_met,
        'rewardKey', v_reward_key,
        'weekTitle', v_week.title,
        'threshold', v_week.draw_threshold,
        'conditionMet', v_condition_met
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
      'conditionMet', v_condition_met
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
        'reason', 'admin_missed_hold_pray',
        'adminManual', true,
        'adminOverride', not v_condition_met,
        'rewardKey', v_reward_key,
        'cardIndex', v_card_index,
        'conditionMet', v_condition_met
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
      'conditionMet', v_condition_met
    );
  end if;

  return jsonb_build_object('ok', false, 'error', 'unsupported_reward');
end;
$$;

revoke all on function public.admin_get_user_ticket_status(text) from public, anon, authenticated;
revoke all on function public.admin_issue_user_missed_reward(text, text) from public, anon, authenticated;

grant execute on function public.admin_get_user_ticket_status(text) to authenticated;
grant execute on function public.admin_issue_user_missed_reward(text, text) to authenticated;

notify pgrst, 'reload schema';

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260612001000_counseling_pastor_only.sql
-- ============================================================================

-- 익명 고민상담 정책 변경
-- 1) profiles.is_pastor 컬럼 추가 (staff보다 상위 권한 — 답변 작성 권한)
-- 2) 사역자 4명에게 권한 부여 (이름+교구 매칭, 동명이인 없음 확인됨)
-- 3) get_counseling_entries: publicEntries 반환 제거 (다른 사람 공개 고민 보기 X)
-- 4) admin_reply_counseling_entry: 사역자(is_pastor)만 통과
-- 5) admin_get_counseling_entries: 응답에 currentAdmin.isPastor 추가 (클라 UI 분기용)
begin;

alter table public.profiles
  add column if not exists is_pastor boolean not null default false;

comment on column public.profiles.is_pastor is '사역자 권한. 익명 고민상담 답변 작성 권한 등 staff 상위 권한에 사용.';

-- 사역자 4명 권한 부여 (이름+교구 매칭). 기존 role이 admin/dev면 유지, 아니면 admin으로 승급.
update public.profiles
set is_pastor = true,
    role = case when role in ('admin', 'dev') then role else 'admin'::public.profile_role end,
    updated_at = now()
where (name = '유광훈' and parish = '1청')
   or (name = '임동표' and parish = '2청')
   or (name = '현성수' and parish = '3청')
   or (name = '남우진' and parish = '4청');

-- 본인 고민만 조회 (공개된 다른 사람 고민 영역 제거)
create or replace function public.get_counseling_entries(p_login_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_mine jsonb := '[]'::jsonb;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'content', content,
    'reply', nullif(reply, ''),
    'repliedAt', replied_at,
    'createdAt', created_at
  ) order by created_at desc), '[]'::jsonb)
  into v_mine
  from public.anonymous_counseling_entries
  where profile_id = v_profile.id;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'mine', v_mine
  );
end;
$$;

-- 어드민 조회 응답에 사역자 여부 같이 반환 (클라이언트 UI 분기용)
create or replace function public.admin_get_counseling_entries()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_entries jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'content', content,
    'reply', nullif(reply, ''),
    'repliedAt', replied_at,
    'createdAt', created_at
  ) order by created_at desc), '[]'::jsonb)
  into v_entries
  from public.anonymous_counseling_entries;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'entries', v_entries,
    'currentAdmin', jsonb_build_object(
      'isPastor', coalesce(v_admin.is_pastor, false)
    )
  );
end;
$$;

-- 답변 작성/수정/삭제는 사역자만
create or replace function public.admin_reply_counseling_entry(
  p_id uuid,
  p_reply text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_reply text := trim(coalesce(p_reply, ''));
begin
  v_admin := public.bu_admin_profile();

  if not coalesce(v_admin.is_pastor, false) then
    return jsonb_build_object('ok', false, 'error', 'pastor_required');
  end if;

  if char_length(v_reply) > 1200 then
    return jsonb_build_object('ok', false, 'error', 'reply_too_long');
  end if;

  update public.anonymous_counseling_entries
  set reply = nullif(v_reply, ''),
      replied_by = case when v_reply = '' then null else v_admin.id end,
      replied_at = case when v_reply = '' then null else now() end,
      updated_at = now()
  where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

notify pgrst, 'reload schema';

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260613000100_qt_three_answers.sql
-- ============================================================================

-- QT 6월 20일과 21일 묵상 답변 3개와 기도제목 저장을 지원한다.
begin;

alter table public.qt_submissions
  add column if not exists answer2_text text not null default '',
  add column if not exists answer3_text text not null default '';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'qt_submissions_answer2_text_len'
      and conrelid = 'public.qt_submissions'::regclass
  ) then
    alter table public.qt_submissions
      add constraint qt_submissions_answer2_text_len check (char_length(answer2_text) <= 500);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'qt_submissions_answer3_text_len'
      and conrelid = 'public.qt_submissions'::regclass
  ) then
    alter table public.qt_submissions
      add constraint qt_submissions_answer3_text_len check (char_length(answer3_text) <= 500);
  end if;
end $$;

comment on column public.qt_submissions.answer_text is '사용자가 작성한 QT 질문 1 답변.';
comment on column public.qt_submissions.answer2_text is '사용자가 작성한 QT 질문 2 답변.';
comment on column public.qt_submissions.answer3_text is '사용자가 작성한 QT 질문 3 답변.';

create or replace function public.bu_qt_reflection_enabled(p_content_date date)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_content_date in (date '2026-06-20', date '2026-06-21');
$$;

create or replace function public.get_qt_reflection(
  p_login_id text,
  p_content_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_content_date date := public.bu_qt_content_date(p_content_date);
  v_submission public.qt_submissions%rowtype;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  select *
  into v_submission
  from public.qt_submissions
  where profile_id = v_profile.id
    and content_date = v_content_date
  limit 1;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'contentDate', v_content_date,
    'reflectionEnabled', public.bu_qt_reflection_enabled(v_content_date),
    'answerText', coalesce(v_submission.answer_text, ''),
    'answerTexts', jsonb_build_array(
      coalesce(v_submission.answer_text, ''),
      coalesce(v_submission.answer2_text, ''),
      coalesce(v_submission.answer3_text, '')
    ),
    'prayerText', coalesce(v_submission.prayer_text, ''),
    'submittedAt', v_submission.submitted_at
  );
end;
$$;

create or replace function public.submit_qt_reflection_v2(
  p_login_id text,
  p_content_date date,
  p_answer1_text text default '',
  p_answer2_text text default '',
  p_answer3_text text default '',
  p_prayer_text text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_content_date date := public.bu_qt_content_date(p_content_date);
  v_answer1 text := left(trim(coalesce(p_answer1_text, '')), 500);
  v_answer2 text := left(trim(coalesce(p_answer2_text, '')), 500);
  v_answer3 text := left(trim(coalesce(p_answer3_text, '')), 500);
  v_prayer text := left(trim(coalesce(p_prayer_text, '')), 800);
  v_submission_id uuid;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if not public.bu_qt_reflection_enabled(v_content_date) then
    return jsonb_build_object('ok', false, 'error', 'qt_reflection_not_open');
  end if;

  if v_answer1 = '' and v_answer2 = '' and v_answer3 = '' and v_prayer = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_qt_reflection');
  end if;

  insert into public.qt_submissions (
    profile_id,
    content_date,
    answer_text,
    answer2_text,
    answer3_text,
    prayer_text,
    submitted_at
  )
  values (
    v_profile.id,
    v_content_date,
    v_answer1,
    v_answer2,
    v_answer3,
    v_prayer,
    now()
  )
  on conflict (profile_id, content_date) do update
  set answer_text = excluded.answer_text,
      answer2_text = excluded.answer2_text,
      answer3_text = excluded.answer3_text,
      prayer_text = excluded.prayer_text,
      updated_at = now()
  returning id into v_submission_id;

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    ref_id,
    amount,
    payload,
    source
  )
  values (
    v_profile.id,
    'qt.submitted',
    'qt',
    v_content_date::text,
    1,
    jsonb_build_object(
      'contentDate', v_content_date,
      'answerCount', (
        case when v_answer1 <> '' then 1 else 0 end
        + case when v_answer2 <> '' then 1 else 0 end
        + case when v_answer3 <> '' then 1 else 0 end
      ),
      'hasPrayer', v_prayer <> ''
    ),
    'web'
  );

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'id', v_submission_id,
    'contentDate', v_content_date
  );
end;
$$;

create or replace function public.submit_qt_reflection(
  p_login_id text,
  p_content_date date,
  p_answer_text text,
  p_prayer_text text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.submit_qt_reflection_v2(
    p_login_id,
    p_content_date,
    p_answer_text,
    '',
    '',
    p_prayer_text
  );
end;
$$;

revoke all on function public.bu_qt_reflection_enabled(date) from public, anon, authenticated;
revoke all on function public.get_qt_reflection(text, date) from public, anon, authenticated;
revoke all on function public.submit_qt_reflection_v2(text, date, text, text, text, text) from public, anon, authenticated;
revoke all on function public.submit_qt_reflection(text, date, text, text) from public, anon, authenticated;

grant execute on function public.bu_qt_reflection_enabled(date) to authenticated;
grant execute on function public.get_qt_reflection(text, date) to authenticated;
grant execute on function public.submit_qt_reflection_v2(text, date, text, text, text, text) to authenticated;
grant execute on function public.submit_qt_reflection(text, date, text, text) to authenticated;

notify pgrst, 'reload schema';

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260613000200_qt_completion_reward.sql
-- ============================================================================

-- 2026년 6월 20일 QT 완료 시 일반 카드팩 1장을 한 번만 지급한다.
begin;

create or replace function public.submit_qt_reflection_v2(
  p_login_id text,
  p_content_date date,
  p_answer1_text text default '',
  p_answer2_text text default '',
  p_answer3_text text default '',
  p_prayer_text text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_content_date date := public.bu_qt_content_date(p_content_date);
  v_answer1 text := left(trim(coalesce(p_answer1_text, '')), 500);
  v_answer2 text := left(trim(coalesce(p_answer2_text, '')), 500);
  v_answer3 text := left(trim(coalesce(p_answer3_text, '')), 500);
  v_prayer text := left(trim(coalesce(p_prayer_text, '')), 800);
  v_submission_id uuid;
  v_reward_reason text := 'qt_2026_06_20_complete';
  v_all_required_filled boolean := false;
  v_already_rewarded boolean := false;
  v_rewarded boolean := false;
  v_reward_event_id uuid;
  v_normal_pack_remaining integer := null;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if not public.bu_qt_reflection_enabled(v_content_date) then
    return jsonb_build_object('ok', false, 'error', 'qt_reflection_not_open');
  end if;

  if v_answer1 = '' and v_answer2 = '' and v_answer3 = '' and v_prayer = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_qt_reflection');
  end if;

  insert into public.qt_submissions (
    profile_id,
    content_date,
    answer_text,
    answer2_text,
    answer3_text,
    prayer_text,
    submitted_at
  )
  values (
    v_profile.id,
    v_content_date,
    v_answer1,
    v_answer2,
    v_answer3,
    v_prayer,
    now()
  )
  on conflict (profile_id, content_date) do update
  set answer_text = excluded.answer_text,
      answer2_text = excluded.answer2_text,
      answer3_text = excluded.answer3_text,
      prayer_text = excluded.prayer_text,
      updated_at = now()
  returning id into v_submission_id;

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    ref_id,
    amount,
    payload,
    source
  )
  values (
    v_profile.id,
    'qt.submitted',
    'qt',
    v_content_date::text,
    1,
    jsonb_build_object(
      'contentDate', v_content_date,
      'answerCount', (
        case when v_answer1 <> '' then 1 else 0 end
        + case when v_answer2 <> '' then 1 else 0 end
        + case when v_answer3 <> '' then 1 else 0 end
      ),
      'hasPrayer', v_prayer <> ''
    ),
    'web'
  );

  v_all_required_filled := v_content_date = date '2026-06-20'
    and v_answer1 <> ''
    and v_answer2 <> ''
    and v_answer3 <> ''
    and v_prayer <> '';

  if v_all_required_filled then
    perform pg_advisory_xact_lock(hashtext('qt_completion_reward:' || v_profile.id::text || ':' || v_content_date::text));

    select exists(
      select 1
      from public.events
      where profile_id = v_profile.id
        and event_type = 'ticket.granted'
        and ref_type = 'qt'
        and ref_id = v_content_date::text
        and payload ->> 'reason' = v_reward_reason
    )
    into v_already_rewarded;

    if not coalesce(v_already_rewarded, false) then
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
          updated_at = now()
      returning normal_pack_remaining into v_normal_pack_remaining;

      insert into public.events (
        profile_id,
        event_type,
        ref_type,
        ref_id,
        amount,
        payload,
        source
      )
      values (
        v_profile.id,
        'ticket.granted',
        'qt',
        v_content_date::text,
        1,
        jsonb_build_object(
          'reason', v_reward_reason,
          'label', '6월 20일 QT 완료',
          'contentDate', v_content_date,
          'answerCount', 3,
          'hasPrayer', true
        ),
        'web'
      )
      returning id into v_reward_event_id;

      v_rewarded := true;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'id', v_submission_id,
    'contentDate', v_content_date,
    'missionCleared', v_all_required_filled,
    'rewarded', v_rewarded,
    'alreadyRewarded', coalesce(v_already_rewarded, false),
    'rewardEventId', v_reward_event_id,
    'normalPackRemaining', v_normal_pack_remaining
  );
end;
$$;

create or replace function public.submit_qt_reflection(
  p_login_id text,
  p_content_date date,
  p_answer_text text,
  p_prayer_text text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.submit_qt_reflection_v2(
    p_login_id,
    p_content_date,
    p_answer_text,
    '',
    '',
    p_prayer_text
  );
end;
$$;

revoke all on function public.submit_qt_reflection_v2(text, date, text, text, text, text) from public, anon, authenticated;
revoke all on function public.submit_qt_reflection(text, date, text, text) from public, anon, authenticated;

grant execute on function public.submit_qt_reflection_v2(text, date, text, text, text, text) to authenticated;
grant execute on function public.submit_qt_reflection(text, date, text, text) to authenticated;

notify pgrst, 'reload schema';

commit;


-- ============================================================================
-- source: beyond_us/supabase/migrations/20260614000100_tab_settings_rename.sql
-- ============================================================================

-- 어드민 탭 활성화 패널에 노출되는 tab_settings.label 갱신
-- counseling: "익명 고민상담" → "목사님께 무물"
-- visible_radio: "보이는 라디오" → "별빛 우편함"
begin;

update public.tab_settings
set label = '목사님께 무물', updated_at = now()
where tab_key = 'counseling';

update public.tab_settings
set label = '별빛 우편함', updated_at = now()
where tab_key = 'visible_radio';

commit;
