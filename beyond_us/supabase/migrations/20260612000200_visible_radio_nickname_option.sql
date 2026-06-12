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
