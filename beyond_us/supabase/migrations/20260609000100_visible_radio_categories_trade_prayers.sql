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
