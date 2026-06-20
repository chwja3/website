-- B.B.B. 조 명단 수동 매칭에서 이미 매칭된 앱 계정을 새 row로 이동할 수 있게 한다.
begin;

create or replace function public.admin_resolve_group_roster_profile(
  p_roster_id uuid,
  p_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_roster public.retreat_group_roster%rowtype;
  v_profile public.profiles%rowtype;
  v_existing_roster_ids uuid[] := array[]::uuid[];
  v_reassigned integer := 0;
begin
  v_admin := public.bu_admin_profile();

  select *
  into v_roster
  from public.retreat_group_roster
  where id = p_roster_id;

  if v_roster.id is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'roster_not_found');
  end if;

  select *
  into v_profile
  from public.profiles
  where id = p_profile_id
    and account_status = 'active';

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'profile_not_found');
  end if;

  if public.bu_group_roster_normalize_name(v_profile.name) is distinct from v_roster.name_norm then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'name_mismatch');
  end if;

  select coalesce(array_agg(r.id order by r.roster_order), array[]::uuid[])
  into v_existing_roster_ids
  from public.retreat_group_roster r
  where r.source_batch = v_roster.source_batch
    and r.matched_profile_id = p_profile_id
    and r.id <> p_roster_id;

  if coalesce(array_length(v_existing_roster_ids, 1), 0) > 0 then
    update public.retreat_group_roster r
    set matched_profile_id = null,
        match_status = 'manual_unmatched',
        match_detail = '관리자 수동 매칭 이동으로 기존 연결 해제',
        updated_at = now()
    where r.id = any(v_existing_roster_ids);

    get diagnostics v_reassigned = row_count;
  end if;

  update public.retreat_group_roster
  set matched_profile_id = p_profile_id,
      match_status = 'matched_manual',
      match_detail = '관리자 수동 매칭',
      updated_at = now()
  where id = p_roster_id;

  if v_roster.group_id is not null then
    insert into public.group_members (
      group_id,
      profile_id,
      group_role,
      assigned_at
    )
    values (
      v_roster.group_id,
      p_profile_id,
      v_roster.group_role,
      now()
    )
    on conflict (profile_id) do update
    set group_id = excluded.group_id,
        group_role = excluded.group_role,
        assigned_at = now();
  end if;

  perform public.bu_sync_bbb_assignments_from_roster(v_roster.source_batch);

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'rosterId', p_roster_id,
    'profileId', p_profile_id,
    'matchStatus', 'matched_manual',
    'reassignedFromRosterIds', to_jsonb(v_existing_roster_ids),
    'reassignedRows', coalesce(v_reassigned, 0)
  );
end;
$$;

revoke all on function public.admin_resolve_group_roster_profile(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_resolve_group_roster_profile(uuid, uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
