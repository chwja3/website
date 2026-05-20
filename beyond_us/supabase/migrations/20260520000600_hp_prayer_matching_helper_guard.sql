-- H&P 기도 작성자 매칭 저장에 필요한 내부 helper를 보강한다.
begin;

create or replace function public.bu_hp_answer_key(p_text text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(btrim(coalesce(p_text, '')), '[[:space:]]+', '', 'g'));
$$;

create or replace function public.bu_hold_pray_cards_for_profile(
  p_profile_id uuid,
  p_week_key text
)
returns table (
  card_index integer,
  entry_id uuid,
  entry_profile_id uuid,
  content text,
  anonymous boolean,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with eligible_cards as (
    select
      hp.*,
      md5(p_profile_id::text || ':' || p_week_key || ':' || hp.id::text) as hp_sort_key
    from public.hold_pray_entries hp
    where hp.visible = true
      and coalesce(hp.week_key, p_week_key) = p_week_key
      and (hp.profile_id is null or hp.profile_id <> p_profile_id)
  ),
  picked_cards as (
    select *
    from eligible_cards
    order by hp_sort_key, created_at, id
    limit 3
  )
  select
    (row_number() over (order by pc.hp_sort_key, pc.created_at, pc.id) - 1)::integer as card_index,
    pc.id as entry_id,
    pc.profile_id as entry_profile_id,
    pc.content as content,
    pc.anonymous as anonymous,
    pc.updated_at as updated_at
  from picked_cards pc;
$$;

create or replace function public.bu_recalculate_hold_pray_guesses(p_week_key text default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_key text := nullif(trim(coalesce(p_week_key, '')), '');
  v_updated integer := 0;
begin
  with recalculated as (
    select
      g.profile_id,
      g.week_key,
      g.card_index,
      public.bu_hp_answer_key(g.guessed_name) <> ''
        and public.bu_hp_answer_key(g.guessed_name) = public.bu_hp_answer_key(owner.name) as next_correct
    from public.hold_pray_guesses g
    join lateral public.bu_hold_pray_cards_for_profile(g.profile_id, g.week_key) hpc
      on hpc.card_index = g.card_index
    left join public.profiles owner on owner.id = hpc.entry_profile_id
    where v_week_key is null or g.week_key = v_week_key
  ),
  updated as (
    update public.hold_pray_guesses g
    set correct = r.next_correct
    from recalculated r
    where g.profile_id = r.profile_id
      and g.week_key = r.week_key
      and g.card_index = r.card_index
      and g.correct is distinct from r.next_correct
    returning 1
  )
  select count(*)::integer into v_updated from updated;

  return coalesce(v_updated, 0);
end;
$$;

revoke all on function public.bu_hp_answer_key(text) from public, anon, authenticated;
revoke all on function public.bu_hold_pray_cards_for_profile(uuid, text) from public, anon, authenticated;
revoke all on function public.bu_recalculate_hold_pray_guesses(text) from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;
