-- 광범위수사 탭 숨김 기본값과 사용자 제출 RPC를 보강한다.
begin;

insert into public.tab_settings (tab_key, label, enabled, status, sort_order)
values ('investigation', '광범위수사', false, 'closed', 65)
on conflict (tab_key) do update
set label = excluded.label,
    enabled = false,
    status = 'closed'::public.tab_status,
    sort_order = excluded.sort_order,
    updated_at = now();

create table if not exists public.anonymous_counseling_entries (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  content text not null,
  public_visible boolean not null default false,
  reply text,
  replied_by uuid references public.profiles(id) on delete set null,
  replied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(trim(content)) between 1 and 700)
);

alter table public.anonymous_counseling_entries
  add column if not exists public_visible boolean not null default false,
  add column if not exists reply text,
  add column if not exists replied_by uuid references public.profiles(id) on delete set null,
  add column if not exists replied_at timestamptz;

create index if not exists anonymous_counseling_entries_profile_idx
on public.anonymous_counseling_entries (profile_id, created_at desc);

alter table public.anonymous_counseling_entries enable row level security;
revoke all on public.anonymous_counseling_entries from public, anon, authenticated;

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

  insert into public.anonymous_counseling_entries (profile_id, content, public_visible)
  values (v_profile.id, v_content, coalesce(p_public_visible, false))
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

create table if not exists public.visible_radio_stories (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  category_key text not null default 'mvp',
  category_label text not null default 'MVP',
  target_text text,
  content text not null,
  status text not null default 'candidate',
  is_anonymous boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(trim(content)) between 1 and 1000)
);

alter table public.visible_radio_stories
  add column if not exists category_key text not null default 'mvp',
  add column if not exists category_label text not null default 'MVP',
  add column if not exists target_text text,
  add column if not exists status text not null default 'candidate',
  add column if not exists is_anonymous boolean not null default false;

create index if not exists visible_radio_stories_profile_idx
on public.visible_radio_stories (profile_id, created_at desc);

create index if not exists visible_radio_stories_category_created_idx
on public.visible_radio_stories (category_key, created_at desc);

alter table public.visible_radio_stories enable row level security;
revoke all on public.visible_radio_stories from public, anon, authenticated;

create or replace function public.bu_visible_radio_category_label(p_key text)
returns text
language sql
immutable
as $$
  select case lower(coalesce(p_key, ''))
    when 'mvp' then 'MVP'
    when 'buddy' then '버디 칭찬'
    when 'moment' then '수련회 순간'
    when 'sorry' then '미안해요'
    when 'cheer' then '응원해요'
    when 'funny_praise' then '웃긴 찬양'
    else 'MVP'
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

create or replace function public.create_visible_radio_story(
  p_login_id text,
  p_category_key text,
  p_target_text text,
  p_content text,
  p_is_anonymous boolean default false
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

create or replace function public.update_visible_radio_story(
  p_login_id text,
  p_id uuid,
  p_category_key text,
  p_target_text text,
  p_content text,
  p_is_anonymous boolean default false
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

revoke all on function public.get_counseling_entries(text) from public, anon, authenticated;
revoke all on function public.create_counseling_entry(text, text, boolean) from public, anon, authenticated;
revoke all on function public.update_counseling_entry(text, uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.delete_counseling_entry(text, uuid) from public, anon, authenticated;
revoke all on function public.bu_visible_radio_category_label(text) from public, anon, authenticated;
revoke all on function public.get_visible_radio_stories(text) from public, anon, authenticated;
revoke all on function public.create_visible_radio_story(text, text, text, text, boolean) from public, anon, authenticated;
revoke all on function public.update_visible_radio_story(text, uuid, text, text, text, boolean) from public, anon, authenticated;
revoke all on function public.delete_visible_radio_story(text, uuid) from public, anon, authenticated;

grant execute on function public.get_counseling_entries(text) to authenticated;
grant execute on function public.create_counseling_entry(text, text, boolean) to authenticated;
grant execute on function public.update_counseling_entry(text, uuid, text, boolean) to authenticated;
grant execute on function public.delete_counseling_entry(text, uuid) to authenticated;
grant execute on function public.bu_visible_radio_category_label(text) to authenticated;
grant execute on function public.get_visible_radio_stories(text) to authenticated;
grant execute on function public.create_visible_radio_story(text, text, text, text, boolean) to authenticated;
grant execute on function public.update_visible_radio_story(text, uuid, text, text, text, boolean) to authenticated;
grant execute on function public.delete_visible_radio_story(text, uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
