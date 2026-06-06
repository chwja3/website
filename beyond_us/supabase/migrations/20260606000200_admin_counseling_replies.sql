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
