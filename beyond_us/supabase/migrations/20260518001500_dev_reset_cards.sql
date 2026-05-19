-- DEV 개발자 계정의 카드와 카드팩 상태를 Supabase 기준으로 초기화한다.
begin;

create or replace function public.dev_reset_my_cards(p_login_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_removed_cards integer := 0;
  v_raffle_released integer := 0;
  v_release jsonb := '{}'::jsonb;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if v_profile.is_dev is not true then
    return jsonb_build_object('ok', false, 'error', 'dev_only');
  end if;

  delete from public.user_cards
  where profile_id = v_profile.id;
  get diagnostics v_removed_cards = row_count;

  insert into public.user_inventory (
    profile_id,
    normal_pack_earned,
    normal_pack_consumed,
    normal_pack_remaining,
    special_pack_earned,
    special_pack_consumed,
    special_pack_remaining,
    updated_at
  )
  values (v_profile.id, 0, 0, 0, 0, 0, 0, now())
  on conflict (profile_id) do update
  set normal_pack_earned = 0,
      normal_pack_consumed = 0,
      normal_pack_remaining = 0,
      special_pack_earned = 0,
      special_pack_consumed = 0,
      special_pack_remaining = 0,
      updated_at = now();

  v_release := public.bu_release_raffle_ticket_condition(v_profile.id, 'card_3', 'dev_reset_cards', 'dev', v_profile.id);
  v_raffle_released := v_raffle_released + coalesce((v_release->>'released')::integer, 0);

  v_release := public.bu_release_raffle_ticket_condition(v_profile.id, 'card_5', 'dev_reset_cards', 'dev', v_profile.id);
  v_raffle_released := v_raffle_released + coalesce((v_release->>'released')::integer, 0);

  v_release := public.bu_release_raffle_ticket_condition(v_profile.id, 'card_10', 'dev_reset_cards', 'dev', v_profile.id);
  v_raffle_released := v_raffle_released + coalesce((v_release->>'released')::integer, 0);

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    amount,
    payload,
    source,
    created_by
  )
  values (
    v_profile.id,
    'dev.cards_reset',
    'dev',
    v_removed_cards,
    jsonb_build_object('removedCards', v_removed_cards, 'raffleReleased', v_raffle_released),
    'admin',
    v_profile.id
  );

  perform public.bu_sync_profile_raffle_tickets(v_profile.id, 'dev_reset_cards', v_profile.id);
  perform public.bu_refresh_profile_summary(v_profile.id);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'removed', v_removed_cards,
    'raffleReleased', v_raffle_released
  );
end;
$$;

revoke all on function public.dev_reset_my_cards(text) from public, anon, authenticated;
grant execute on function public.dev_reset_my_cards(text) to authenticated;

commit;
