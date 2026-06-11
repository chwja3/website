-- 교환현황(get_user_trades) 상대 기도제목 노출에서 익명 entry를 제외한다.
-- 교환현황 화면은 상대 닉네임이 이미 노출되므로 익명 entry를 보여주면 익명의 의미가 사라진다.
-- H&P 캐러셀 등 다른 화면의 익명 동작에는 영향 없음 (bu_trade_prayer_for_profile만 수정).
begin;

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
      and coalesce(h.anonymous, false) = false
      and trim(coalesce(h.content, '')) <> ''
    order by
      case when h.week_key = 'w' || public.bu_current_week()::text then 0 else 1 end,
      h.created_at desc
    limit 1
  ), '');
$$;

notify pgrst, 'reload schema';

commit;
