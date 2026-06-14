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
