-- B.B.B. 조 명단과 신규 가입자 프로필 매칭을 재동기화하는 SQL.
begin;

create or replace function public.bu_sync_group_roster_profile_matches_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.bu_sync_group_roster_profile_matches('20260614');
  return new;
end;
$$;

drop trigger if exists sync_group_roster_profile_after_change on public.profiles;

create trigger sync_group_roster_profile_after_change
after insert or update of name, parish, account_status, is_dev, is_test
on public.profiles
for each row execute function public.bu_sync_group_roster_profile_matches_trigger();

select public.bu_sync_group_roster_profile_matches('20260614') as sync_result;

select pg_notify('pgrst', 'reload schema');

commit;

select
  match_status,
  count(*)::integer as row_count
from public.retreat_group_roster
where source_batch = '20260614'
group by match_status
order by match_status;

select
  r.group_label,
  r.roster_order,
  r.participant_name,
  r.parish_norm as roster_parish,
  r.participation_tier,
  r.match_status,
  r.match_detail,
  jsonb_array_length(coalesce(r.candidate_profiles, '[]'::jsonb)) as candidate_count,
  r.candidate_profiles
from public.retreat_group_roster r
where r.source_batch = '20260614'
  and r.match_status in (
    'nickname_missing',
    'duplicate_same_parish',
    'duplicate_roster_same_parish',
    'duplicate_needs_check'
  )
order by
  case r.match_status
    when 'nickname_missing' then 1
    when 'duplicate_same_parish' then 2
    when 'duplicate_roster_same_parish' then 3
    else 4
  end,
  r.group_no,
  r.roster_order;

select
  r.group_label,
  r.roster_order,
  r.participant_name,
  r.parish_norm as roster_parish,
  p.login_id,
  p.display_name,
  p.name as profile_name,
  p.parish as profile_parish,
  r.match_status,
  r.match_detail
from public.retreat_group_roster r
left join public.profiles p on p.id = r.matched_profile_id
where r.source_batch = '20260614'
  and r.matched_profile_id is not null
order by r.group_no, r.roster_order;
