-- H&P 응답을 초기화하고 관리자 기도제목 작성 RPC를 추가한다.
begin;

delete from public.hold_pray_hints;
delete from public.hold_pray_guesses;

create or replace function public.admin_upsert_hold_pray_entry(
  p_login_id text,
  p_week_key text default null,
  p_content text default '',
  p_anonymous boolean default false,
  p_visible boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_week_key text := coalesce(nullif(trim(coalesce(p_week_key, '')), ''), 'w' || public.bu_current_week()::text);
  v_content text := btrim(coalesce(p_content, ''));
  v_entry_id uuid;
begin
  v_admin := public.bu_admin_profile();

  if nullif(trim(coalesce(p_login_id, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'missing_user');
  end if;

  if v_content = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_content');
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

  select h.id
  into v_entry_id
  from public.hold_pray_entries h
  where h.profile_id = v_profile.id
    and coalesce(h.week_key, v_week_key) = v_week_key
  order by h.updated_at desc, h.id desc
  limit 1;

  if v_entry_id is null then
    insert into public.hold_pray_entries (
      profile_id,
      week_key,
      content,
      anonymous,
      visible
    )
    values (
      v_profile.id,
      v_week_key,
      v_content,
      coalesce(p_anonymous, false),
      coalesce(p_visible, true)
    )
    returning id into v_entry_id;
  else
    update public.hold_pray_entries
    set content = v_content,
        anonymous = coalesce(p_anonymous, false),
        visible = coalesce(p_visible, true),
        updated_at = now()
    where id = v_entry_id;
  end if;

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
    'hp.prayer_admin_upserted',
    'hold_pray',
    v_entry_id::text,
    0,
    v_week_key,
    jsonb_build_object('targetLoginId', v_profile.login_id, 'adminLoginId', v_admin.login_id),
    'admin',
    v_admin.id
  );

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'weekKey', v_week_key,
    'userId', v_profile.login_id,
    'entryId', v_entry_id,
    'content', v_content,
    'anonymous', coalesce(p_anonymous, false),
    'visible', coalesce(p_visible, true)
  );
end;
$$;

revoke all on function public.admin_upsert_hold_pray_entry(text, text, text, boolean, boolean) from public, anon, authenticated;
grant execute on function public.admin_upsert_hold_pray_entry(text, text, text, boolean, boolean) to authenticated;

commit;
