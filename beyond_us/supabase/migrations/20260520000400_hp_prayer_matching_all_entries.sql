-- H&P 기도제목 작성자 매칭을 주차와 무관한 전체 엔트리 기준으로 변경한다.
begin;

alter table public.hold_pray_entries
  add column if not exists owner_name_input text;

create or replace function public.admin_hold_pray_entry_matching(p_week_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_unmatched jsonb := '[]'::jsonb;
  v_unresolved jsonb := '[]'::jsonb;
  v_matched jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  with base as (
    select
      h.id,
      coalesce(h.week_key, '') as week_key,
      h.content,
      h.anonymous,
      h.visible,
      h.profile_id,
      nullif(btrim(coalesce(h.owner_name_input, '')), '') as owner_name_input,
      h.created_at,
      h.updated_at,
      p.login_id::text as matched_user_id,
      p.name as matched_name,
      p.parish as matched_parish
    from public.hold_pray_entries h
    left join public.profiles p on p.id = h.profile_id
  ),
  candidate_counts as (
    select
      b.id,
      count(mp.id)::integer as candidate_count
    from base b
    left join public.profiles mp
      on b.owner_name_input is not null
     and mp.account_status = 'active'
     and public.bu_hp_answer_key(mp.name) = public.bu_hp_answer_key(b.owner_name_input)
    group by b.id
  ),
  rows as (
    select
      b.*,
      coalesce(cc.candidate_count, 0) as candidate_count,
      case
        when b.profile_id is not null then 'matched'
        when b.owner_name_input is null then 'unmatched'
        when coalesce(cc.candidate_count, 0) > 1 then 'multiple'
        when coalesce(cc.candidate_count, 0) = 1 then 'needs_save'
        else 'not_found'
      end as match_state
    from base b
    left join candidate_counts cc on cc.id = b.id
  ),
  json_rows as (
    select
      match_state,
      updated_at,
      jsonb_build_object(
        'entryId', id,
        'weekKey', week_key,
        'content', content,
        'anonymous', coalesce(anonymous, false),
        'visible', coalesce(visible, false),
        'ownerNameInput', coalesce(owner_name_input, ''),
        'matchedUserId', coalesce(matched_user_id, ''),
        'matchedName', coalesce(matched_name, ''),
        'matchedParish', coalesce(matched_parish, ''),
        'candidateCount', candidate_count,
        'matchState', match_state,
        'createdAt', created_at,
        'updatedAt', updated_at
      ) as row_json
    from rows
  )
  select
    coalesce(jsonb_agg(row_json order by updated_at desc) filter (where match_state = 'unmatched'), '[]'::jsonb),
    coalesce(jsonb_agg(row_json order by updated_at desc) filter (where match_state in ('not_found', 'multiple', 'needs_save')), '[]'::jsonb),
    coalesce(jsonb_agg(row_json order by updated_at desc) filter (where match_state = 'matched'), '[]'::jsonb)
  into v_unmatched, v_unresolved, v_matched
  from json_rows;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'scope', 'all',
    'unmatched', coalesce(v_unmatched, '[]'::jsonb),
    'unresolved', coalesce(v_unresolved, '[]'::jsonb),
    'matched', coalesce(v_matched, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.admin_hold_pray_entry_matching(text) to authenticated;

notify pgrst, 'reload schema';

commit;
