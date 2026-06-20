-- BBB 미배정 인원만 자동으로 케어버디와 시크릿버디를 보강한다.
begin;

create or replace function public.admin_auto_fill_missing_bbb_buddies(
  p_group_no integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_batch text := '20260614';
  v_care_rows integer := 0;
  v_secret_rows integer := 0;
  v_singleton_rows integer := 0;
  v_tf_extra_rows integer := 0;
  v_unresolved_singletons integer := 0;
  v_remaining_missing_care integer := 0;
  v_remaining_missing_secret integer := 0;
  v_group_members integer := 0;
  v_assignments integer := 0;
  v_sync_result jsonb := '{}'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  perform public.bu_sync_group_roster_profile_matches(v_batch);

  with ordered as (
    select
      r.id,
      r.group_id,
      r.group_no,
      coalesce(r.participation_tier, '전참') as participation_tier,
      r.care_buddy_roster_id,
      r.secret_buddy_roster_id,
      count(*) over (
        partition by r.group_id, coalesce(r.participation_tier, '전참')
      )::integer as tier_member_count
    from public.retreat_group_roster r
    where r.source_batch = v_batch
      and r.group_id is not null
      and r.matched_profile_id is not null
      and (p_group_no is null or r.group_no = p_group_no)
  ),
  missing_care as (
    select *
    from ordered
    where tier_member_count > 1
      and care_buddy_roster_id is null
  ),
  resolved_care as (
    select distinct on (candidate.id)
      owner.id,
      candidate.id as care_buddy_roster_id
    from missing_care owner
    join lateral (
      select c.id
      from public.retreat_group_roster c
      where c.source_batch = v_batch
        and c.group_id = owner.group_id
        and coalesce(c.participation_tier, '전참') = owner.participation_tier
        and c.id <> owner.id
        and c.secret_buddy_roster_id is null
      order by
        case when c.care_buddy_roster_id is null then 0 else 1 end,
        md5(owner.id::text || ':missing-care:' || c.id::text)
      limit 1
    ) candidate on true
    order by
      candidate.id,
      md5(owner.id::text || ':claim:' || candidate.id::text)
  ),
  updated_care as (
    update public.retreat_group_roster r
    set care_buddy_roster_id = resolved_care.care_buddy_roster_id,
        updated_at = now()
    from resolved_care
    where r.id = resolved_care.id
      and r.care_buddy_roster_id is null
    returning r.id
  )
  select count(*)::integer
  into v_care_rows
  from updated_care;

  with target_scope as (
    select
      target.*,
      count(*) over (
        partition by target.group_id, coalesce(target.participation_tier, '전참')
      )::integer as tier_member_count
    from public.retreat_group_roster target
    where target.source_batch = v_batch
      and target.group_id is not null
      and target.matched_profile_id is not null
      and target.secret_buddy_roster_id is null
      and (p_group_no is null or target.group_no = p_group_no)
  ),
  owners as (
    select distinct on (target.id)
      target.id as target_id,
      owner.id as owner_id
    from target_scope target
    join public.retreat_group_roster owner
      on owner.care_buddy_roster_id = target.id
     and owner.source_batch = target.source_batch
    where owner.matched_profile_id is not null
      and not (
        target.tier_member_count = 1
        and coalesce(target.participation_tier, '전참') in ('토참', '일참')
      )
      order by
      target.id,
      case when target.group_id = owner.group_id then 0 else 1 end,
      case
        when coalesce(target.participation_tier, '전참') = coalesce(owner.participation_tier, '전참') then 0
        else 1
      end,
      owner.roster_order nulls last,
      owner.id
  ),
  updated_secret as (
    update public.retreat_group_roster target
    set secret_buddy_roster_id = owners.owner_id,
        updated_at = now()
    from owners
    where target.id = owners.target_id
      and target.secret_buddy_roster_id is null
    returning target.id
  )
  select count(*)::integer
  into v_secret_rows
  from updated_secret;

  with ordered as (
    select
      r.*,
      count(*) over (
        partition by r.group_id, coalesce(r.participation_tier, '전참')
      )::integer as tier_member_count
    from public.retreat_group_roster r
    where r.source_batch = v_batch
      and r.group_id is not null
      and r.matched_profile_id is not null
      and (p_group_no is null or r.group_no = p_group_no)
  ),
  singleton as (
    select *
    from ordered
    where tier_member_count = 1
      and coalesce(participation_tier, '전참') in ('토참', '일참')
      and (care_buddy_roster_id is null or secret_buddy_roster_id is null)
      and match_status <> 'manual_unmatched'
  ),
  resolved as (
    select
      s.id,
      coalesce(s.care_buddy_roster_id, full_candidate.id) as full_care_roster_id,
      coalesce(s.secret_buddy_roster_id, tf_candidate.id) as tf_secret_roster_id,
      case when s.secret_buddy_roster_id is null then tf_candidate.id else null end as new_tf_secret_roster_id
    from singleton s
    left join lateral (
      select c.id
      from public.retreat_group_roster c
      where c.source_batch = v_batch
        and c.group_id = s.group_id
        and c.id <> s.id
        and coalesce(c.participation_tier, '전참') = '전참'
        and c.matched_profile_id is not null
      order by md5(s.id::text || ':missing-full:' || c.id::text)
      limit 1
    ) full_candidate on s.care_buddy_roster_id is null
    left join lateral (
      select tf.id
      from public.retreat_group_roster tf
      join public.profiles p on p.id = tf.matched_profile_id
      where tf.source_batch = v_batch
        and tf.id <> s.id
        and p.account_status = 'active'
        and (p.role in ('admin', 'dev') or p.is_dev = true)
      order by
        case when tf.group_id = s.group_id then 0 else 1 end,
        md5(s.id::text || ':missing-tf:' || tf.id::text)
      limit 1
    ) tf_candidate on s.secret_buddy_roster_id is null
  ),
  updated_singletons as (
    update public.retreat_group_roster r
    set care_buddy_roster_id = case
          when r.care_buddy_roster_id is null then resolved.full_care_roster_id
          else r.care_buddy_roster_id
        end,
        secret_buddy_roster_id = case
          when r.secret_buddy_roster_id is null then resolved.tf_secret_roster_id
          else r.secret_buddy_roster_id
        end,
        updated_at = now()
    from resolved
    where r.id = resolved.id
      and resolved.full_care_roster_id is not null
      and resolved.tf_secret_roster_id is not null
      and (r.care_buddy_roster_id is null or r.secret_buddy_roster_id is null)
    returning r.id, resolved.new_tf_secret_roster_id
  ),
  extra_links as (
    insert into public.bbb_extra_care_roster_links (
      source_batch,
      care_giver_roster_id,
      care_receiver_roster_id,
      reason
    )
    select
      v_batch,
      us.new_tf_secret_roster_id,
      us.id,
      'singleton_partial_tf'
    from updated_singletons us
    where us.new_tf_secret_roster_id is not null
    on conflict (source_batch, care_giver_roster_id, care_receiver_roster_id) do update
    set reason = excluded.reason,
        updated_at = now()
    returning id
  )
  select
    (select count(*) from updated_singletons)::integer,
    (select count(*) from extra_links)::integer,
    (select count(*) from resolved where full_care_roster_id is null or tf_secret_roster_id is null)::integer
  into v_singleton_rows, v_tf_extra_rows, v_unresolved_singletons;

  v_sync_result := public.bu_sync_group_roster_profile_matches(v_batch);
  v_group_members := coalesce((v_sync_result->>'groupMembersTouched')::integer, 0);
  v_assignments := coalesce((v_sync_result->>'assignmentsTouched')::integer, 0);

  select
    count(*) filter (where care_buddy_roster_id is null)::integer,
    count(*) filter (where secret_buddy_roster_id is null)::integer
  into v_remaining_missing_care, v_remaining_missing_secret
  from public.retreat_group_roster r
  where r.source_batch = v_batch
    and r.group_id is not null
    and r.matched_profile_id is not null
    and r.match_status <> 'manual_unmatched'
    and (p_group_no is null or r.group_no = p_group_no);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'sourceBatch', v_batch,
    'groupNo', p_group_no,
    'preservedExisting', true,
    'filledCareRows', coalesce(v_care_rows, 0),
    'filledSecretRows', coalesce(v_secret_rows, 0),
    'singletonFallbackRows', coalesce(v_singleton_rows, 0),
    'tfExtraCareRows', coalesce(v_tf_extra_rows, 0),
    'unresolvedSingletonBuckets', coalesce(v_unresolved_singletons, 0),
    'remainingMissingCareRows', coalesce(v_remaining_missing_care, 0),
    'remainingMissingSecretRows', coalesce(v_remaining_missing_secret, 0),
    'groupMembersTouched', coalesce(v_group_members, 0),
    'assignmentsTouched', coalesce(v_assignments, 0)
  );
end;
$$;

revoke all on function public.admin_auto_fill_missing_bbb_buddies(integer) from public, anon, authenticated;
grant execute on function public.admin_auto_fill_missing_bbb_buddies(integer) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
