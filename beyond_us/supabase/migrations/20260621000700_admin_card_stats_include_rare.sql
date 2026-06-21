-- 실물 카드 수령 통계가 10번 레어 카드까지 포함하도록 조정한다.
begin;

create or replace function public.bu_card_alias(p_card_id integer)
returns text
language sql
immutable
set search_path = public
as $$
  select case p_card_id
    when 1 then '사모'
    when 2 then '라라'
    when 3 then '달래'
    when 4 then '오참'
    when 5 then '네헤'
    when 6 then '더무'
    when 7 then '고'
    when 8 then '엔'
    when 9 then '버터'
    when 10 then 'BetWeEn'
    else null
  end;
$$;

comment on function public.bu_card_alias(integer) is '관리자 화면과 운영 SQL에서 사용하는 카드 별칭을 카드 번호 기준으로 반환한다.';

create or replace function public.admin_card_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_total_draws integer := 0;
  v_card_counts jsonb := '{}'::jsonb;
  v_received_counts jsonb := '{}'::jsonb;
  v_user_stats jsonb := '[]'::jsonb;
  v_card_aliases jsonb := '{}'::jsonb;
  v_card_virtue_names jsonb := '{}'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  select coalesce(sum(quantity), 0)::integer
  into v_total_draws
  from public.user_cards uc
  join public.profiles p on p.id = uc.profile_id and p.account_status = 'active'
  where uc.card_id between 1 and 10;

  select coalesce(jsonb_object_agg(c.id::text, coalesce(public.bu_card_alias(c.id), c.name) order by c.id), '{}'::jsonb)
  into v_card_aliases
  from public.cards c
  where c.id between 1 and 10 and c.enabled = true;

  select coalesce(jsonb_object_agg(c.id::text, c.name order by c.id), '{}'::jsonb)
  into v_card_virtue_names
  from public.cards c
  where c.id between 1 and 10 and c.enabled = true;

  select coalesce(jsonb_object_agg(c.id::text, coalesce(ct.qty, 0) order by c.id), '{}'::jsonb)
  into v_card_counts
  from public.cards c
  left join (
    select uc.card_id, sum(uc.quantity)::integer as qty
    from public.user_cards uc
    join public.profiles p on p.id = uc.profile_id and p.account_status = 'active'
    group by uc.card_id
  ) ct on ct.card_id = c.id
  where c.id between 1 and 10 and c.enabled = true;

  select coalesce(jsonb_object_agg(c.id::text, coalesce(rt.received, 0) order by c.id), '{}'::jsonb)
  into v_received_counts
  from public.cards c
  left join (
    select r.card_id, sum(r.received_qty)::integer as received
    from public.physical_card_receipts r
    join public.profiles p on p.id = r.profile_id and p.account_status = 'active'
    group by r.card_id
  ) rt on rt.card_id = c.id
  where c.id between 1 and 10 and c.enabled = true;

  with active_profiles as (
    select p.id, p.login_id, p.name
    from public.profiles p
    where p.account_status = 'active'
      and (
        exists (select 1 from public.user_cards uc where uc.profile_id = p.id and uc.quantity > 0)
        or exists (select 1 from public.physical_card_receipts r where r.profile_id = p.id and r.received_qty > 0)
      )
  ),
  receipt_cards as (
    select id, coalesce(public.bu_card_alias(id), name) as alias_name, name as virtue_name, sort_order
    from public.cards
    where id between 1 and 10 and enabled = true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'nickname', ap.login_id,
    'name', ap.name,
    'cards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'cardId', c.id,
        'cardName', c.alias_name,
        'virtueName', c.virtue_name,
        'drew', coalesce(uc.quantity, 0),
        'received', coalesce(r.received_qty, 0),
        'needed', greatest(0, coalesce(uc.quantity, 0) - coalesce(r.received_qty, 0)),
        'tfTarget', coalesce(uc.quantity, 0),
        'tradeOut', 0,
        'tradeOutTo', '[]'::jsonb,
        'tradeInFrom', '[]'::jsonb,
        'tradeInFromDetails', '[]'::jsonb
      ) order by c.sort_order, c.id)
      from receipt_cards c
      left join public.user_cards uc on uc.profile_id = ap.id and uc.card_id = c.id
      left join public.physical_card_receipts r on r.profile_id = ap.id and r.card_id = c.id
    ), '[]'::jsonb)
  ) order by ap.login_id), '[]'::jsonb)
  into v_user_stats
  from active_profiles ap;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'totalDraws', v_total_draws,
    'cardCounts', v_card_counts,
    'receivedCounts', v_received_counts,
    'cardAliases', v_card_aliases,
    'cardVirtueNames', v_card_virtue_names,
    'userStats', v_user_stats
  );
end;
$$;

revoke all on function public.bu_card_alias(integer) from public, anon, authenticated;
grant execute on function public.bu_card_alias(integer) to anon, authenticated;

revoke all on function public.admin_card_stats() from public, anon, authenticated;
grant execute on function public.admin_card_stats() to authenticated;

notify pgrst, 'reload schema';

commit;
