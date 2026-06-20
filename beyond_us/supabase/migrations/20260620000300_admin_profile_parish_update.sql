-- 관리자 앱 가입자 탭에서 프로필 교구를 수정하는 RPC를 제공한다.
begin;

create or replace function public.admin_update_profile_parish(
  p_login_id text,
  p_parish text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_login_id text := trim(coalesce(p_login_id, ''));
  v_parish text := trim(coalesce(p_parish, ''));
  v_allowed_parishes constant text[] := array['1청', '2청', '3청', '4청', 'VIP', '교회학교', '목양교구', '교회학교/목양교구'];
begin
  v_admin := public.bu_admin_profile();

  if v_login_id = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_login_id');
  end if;

  if v_parish = '' or not (v_parish = any(v_allowed_parishes)) then
    return jsonb_build_object('ok', false, 'error', 'invalid_parish');
  end if;

  update public.profiles
  set parish = v_parish
  where login_id = v_login_id
    and account_status = 'active'
  returning *
  into v_profile;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'error', 'profile_not_found');
  end if;

  insert into public.events (
    profile_id,
    event_type,
    source,
    payload,
    created_by
  )
  values (
    v_profile.id,
    'admin.profile.parish_updated',
    'admin',
    jsonb_build_object(
      'loginId', v_profile.login_id,
      'name', v_profile.name,
      'parish', v_profile.parish,
      'adminLoginId', v_admin.login_id
    ),
    v_admin.id
  );

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'nickname', v_profile.login_id,
    'name', v_profile.name,
    'parish', v_profile.parish
  );
end;
$$;

revoke all on function public.admin_update_profile_parish(text, text) from public, anon, authenticated;
grant execute on function public.admin_update_profile_parish(text, text) to authenticated;

commit;
