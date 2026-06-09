-- MAIN 반영 전 미적용 DEV Supabase SQL을 순서대로 묶은 실행 파일이다.
-- 생성일: 2026-06-09
-- 기준: origin/main...dev 에서 main에 없는 Supabase migration 4개.
-- 실행 순서: 광범위수사/익명 고민상담 -> 고민상담 답변 -> 보이는 라디오 기본 -> 보이는 라디오 카테고리/교환 기도제목.


-- ============================================================================
-- Source: beyond_us\supabase\migrations\20260606000100_investigation_counseling_tabs.sql
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
-- Source: beyond_us\supabase\migrations\20260606000200_admin_counseling_replies.sql
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
-- Source: beyond_us\supabase\migrations\20260606000300_visible_radio_stories.sql
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
-- Source: beyond_us\supabase\migrations\20260609000100_visible_radio_categories_trade_prayers.sql
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
