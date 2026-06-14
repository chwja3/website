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
