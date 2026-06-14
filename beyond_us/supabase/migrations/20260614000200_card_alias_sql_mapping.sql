-- 관리자 카드 별칭을 SQL/RPC 출력에서도 동일하게 사용한다.
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
  where uc.card_id between 1 and 9;

  select coalesce(jsonb_object_agg(c.id::text, coalesce(public.bu_card_alias(c.id), c.name) order by c.id), '{}'::jsonb)
  into v_card_aliases
  from public.cards c
  where c.id between 1 and 9 and c.enabled = true;

  select coalesce(jsonb_object_agg(c.id::text, c.name order by c.id), '{}'::jsonb)
  into v_card_virtue_names
  from public.cards c
  where c.id between 1 and 9 and c.enabled = true;

  select coalesce(jsonb_object_agg(c.id::text, coalesce(ct.qty, 0) order by c.id), '{}'::jsonb)
  into v_card_counts
  from public.cards c
  left join (
    select uc.card_id, sum(uc.quantity)::integer as qty
    from public.user_cards uc
    join public.profiles p on p.id = uc.profile_id and p.account_status = 'active'
    group by uc.card_id
  ) ct on ct.card_id = c.id
  where c.id between 1 and 9 and c.enabled = true;

  select coalesce(jsonb_object_agg(c.id::text, coalesce(rt.received, 0) order by c.id), '{}'::jsonb)
  into v_received_counts
  from public.cards c
  left join (
    select r.card_id, sum(r.received_qty)::integer as received
    from public.physical_card_receipts r
    join public.profiles p on p.id = r.profile_id and p.account_status = 'active'
    group by r.card_id
  ) rt on rt.card_id = c.id
  where c.id between 1 and 9 and c.enabled = true;

  with active_profiles as (
    select p.id, p.login_id, p.name
    from public.profiles p
    where p.account_status = 'active'
      and (
        exists (select 1 from public.user_cards uc where uc.profile_id = p.id and uc.quantity > 0)
        or exists (select 1 from public.physical_card_receipts r where r.profile_id = p.id and r.received_qty > 0)
      )
  ),
  normal_cards as (
    select id, coalesce(public.bu_card_alias(id), name) as alias_name, name as virtue_name, sort_order
    from public.cards
    where id between 1 and 9 and enabled = true
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
      from normal_cards c
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

create or replace view public.ops_cards
with (security_invoker = true)
as
select
  id,
  coalesce(public.bu_card_alias(id), name) as name,
  grade,
  image_path,
  enabled,
  sort_order,
  created_at,
  updated_at,
  name as virtue_name
from public.cards
order by sort_order, id;

create or replace view public.ops_events
with (security_invoker = true)
as
with event_rows as (
  select
    e.*,
    case
      when e.ref_type = 'card' and e.ref_id ~ '^[0-9]+$' then e.ref_id::integer
      when (e.payload ->> 'cardId') ~ '^[0-9]+$' then (e.payload ->> 'cardId')::integer
      when (e.payload ->> 'card_id') ~ '^[0-9]+$' then (e.payload ->> 'card_id')::integer
      else null
    end as event_card_id
  from public.events e
)
select
  e.occurred_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  e.event_type,
  e.ref_type,
  e.ref_id,
  e.amount,
  e.week_key,
  e.source,
  e.request_id,
  creator.login_id::text as created_by_login_id,
  creator.display_name as created_by_display_name,
  e.payload,
  e.created_at,
  e.id,
  e.profile_id,
  e.created_by,
  e.event_card_id,
  coalesce(public.bu_card_alias(event_card.id), event_card.name) as card_alias,
  event_card.name as card_virtue_name
from event_rows e
left join public.profiles p on p.id = e.profile_id
left join public.profiles creator on creator.id = e.created_by
left join public.cards event_card on event_card.id = e.event_card_id
order by e.occurred_at desc, e.created_at desc, e.id desc;

comment on view public.ops_events is 'Events 로그를 닉네임, 이름, 교구, 카드 별칭과 함께 최신순으로 보는 운영용 view.';

create or replace view public.ops_user_cards
with (security_invoker = true)
as
select
  uc.updated_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  uc.card_id,
  coalesce(public.bu_card_alias(c.id), c.name) as card_name,
  c.grade as card_grade,
  uc.quantity,
  uc.first_obtained_at,
  uc.profile_id,
  c.name as virtue_name
from public.user_cards uc
join public.profiles p on p.id = uc.profile_id
join public.cards c on c.id = uc.card_id
order by uc.updated_at desc, p.login_id, uc.card_id;

create or replace view public.ops_trades
with (security_invoker = true)
as
select
  t.created_at,
  requester.login_id::text as requester_login_id,
  requester.display_name as requester_display_name,
  requester.name as requester_name,
  t.requester_card_id,
  coalesce(public.bu_card_alias(requester_card.id), requester_card.name) as requester_card_name,
  target.login_id::text as target_login_id,
  target.display_name as target_display_name,
  target.name as target_name,
  t.target_card_id,
  coalesce(public.bu_card_alias(target_card.id), target_card.name) as target_card_name,
  t.status,
  t.resolved_at,
  t.id,
  t.requester_id,
  t.target_id,
  requester_card.name as requester_card_virtue_name,
  target_card.name as target_card_virtue_name
from public.trades t
join public.profiles requester on requester.id = t.requester_id
join public.profiles target on target.id = t.target_id
join public.cards requester_card on requester_card.id = t.requester_card_id
join public.cards target_card on target_card.id = t.target_card_id
order by t.created_at desc, t.id desc;

create or replace view public.ops_physical_card_receipts
with (security_invoker = true)
as
select
  r.updated_at,
  p.login_id::text as login_id,
  p.display_name,
  p.name,
  p.parish,
  r.card_id,
  coalesce(public.bu_card_alias(c.id), c.name) as card_name,
  r.received_qty,
  updater.login_id::text as updated_by_login_id,
  updater.display_name as updated_by_display_name,
  r.profile_id,
  r.updated_by,
  c.name as virtue_name
from public.physical_card_receipts r
join public.profiles p on p.id = r.profile_id
join public.cards c on c.id = r.card_id
left join public.profiles updater on updater.id = r.updated_by
order by r.updated_at desc, p.login_id, r.card_id;

revoke all on function public.bu_card_alias(integer) from public, anon, authenticated;
grant execute on function public.bu_card_alias(integer) to anon, authenticated;

revoke all on function public.admin_card_stats() from public, anon, authenticated;
grant execute on function public.admin_card_stats() to authenticated;

grant select on
  public.ops_cards,
  public.ops_events,
  public.ops_user_cards,
  public.ops_trades,
  public.ops_physical_card_receipts
to authenticated;

notify pgrst, 'reload schema';

commit;
