-- BBB 들킴 배지가 내가 돌보는 대상의 정답 여부만 보도록 계산 방향을 교정한다.
begin;

create or replace function public.get_bbb_status(p_login_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_assignment public.bbb_assignments%rowtype;
  v_care public.profiles%rowtype;
  v_secret public.profiles%rowtype;
  v_roster_id uuid;
  v_care_roster_id uuid;
  v_secret_roster_id uuid;
  v_care_roster_name text := '';
  v_secret_roster_name text := '';
  v_care_profile_id uuid;
  v_secret_profile_id uuid;
  v_care_name text := '';
  v_secret_name text := '';
  v_extra_care_buddies jsonb := '[]'::jsonb;
  v_photos jsonb := '{}'::jsonb;
  v_caught boolean := false;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  v_photos := public.bu_photo_payload(v_profile.id);

  select *
  into v_assignment
  from public.bbb_assignments
  where profile_id = v_profile.id;

  select
    r.id,
    care.id,
    secret.id,
    public.bu_clean_display_text(care.participant_name),
    public.bu_clean_display_text(secret.participant_name),
    care.matched_profile_id,
    secret.matched_profile_id
  into
    v_roster_id,
    v_care_roster_id,
    v_secret_roster_id,
    v_care_roster_name,
    v_secret_roster_name,
    v_care_profile_id,
    v_secret_profile_id
  from public.retreat_group_roster r
  left join public.retreat_group_roster care on care.id = r.care_buddy_roster_id
  left join public.retreat_group_roster secret on secret.id = r.secret_buddy_roster_id
  where r.source_batch = '20260614'
    and r.matched_profile_id = v_profile.id
  order by r.roster_order
  limit 1;

  v_care_profile_id := coalesce(v_assignment.care_buddy_id, v_care_profile_id);
  v_secret_profile_id := coalesce(v_assignment.secret_buddy_id, v_secret_profile_id);

  if v_assignment.profile_id is null and v_roster_id is null then
    return jsonb_build_object(
      'ok', false,
      'source', 'supabase',
      'error', 'no_match'
    ) || v_photos;
  end if;

  if v_care_profile_id is not null then
    select *
    into v_care
    from public.profiles
    where id = v_care_profile_id;
  end if;

  if v_secret_profile_id is not null then
    select *
    into v_secret
    from public.profiles
    where id = v_secret_profile_id;
  end if;

  if v_roster_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'name', coalesce(
        public.bu_clean_display_text(receiver.participant_name),
        public.bu_clean_display_text(rp.name),
        public.bu_clean_display_text(rp.display_name),
        public.bu_clean_display_text(rp.login_id::text),
        '이름 확인 중'
      ),
      'participantName', public.bu_clean_display_text(receiver.participant_name),
      'displayName', public.bu_clean_display_text(rp.display_name),
      'nickname', coalesce(public.bu_clean_display_text(rp.login_id::text), ''),
      'groupNo', receiver.group_no,
      'tier', coalesce(receiver.participation_tier, '')
    ) order by receiver.group_no, receiver.roster_order), '[]'::jsonb)
    into v_extra_care_buddies
    from public.bbb_extra_care_roster_links link
    join public.retreat_group_roster receiver on receiver.id = link.care_receiver_roster_id
    left join public.profiles rp on rp.id = receiver.matched_profile_id
    where link.source_batch = '20260614'
      and link.care_giver_roster_id = v_roster_id;
  end if;

  v_care_name := coalesce(
    public.bu_clean_display_text(v_care_roster_name),
    public.bu_clean_display_text(v_care.name),
    public.bu_clean_display_text(v_care.display_name),
    public.bu_clean_display_text(v_care.login_id::text),
    '이름 확인 중'
  );

  v_secret_name := coalesce(
    public.bu_clean_display_text(v_secret_roster_name),
    public.bu_clean_display_text(v_secret.name),
    public.bu_clean_display_text(v_secret.display_name),
    public.bu_clean_display_text(v_secret.login_id::text),
    ''
  );

  with cared_targets as (
    select
      v_care_profile_id as profile_id,
      v_care_roster_id as roster_id
    where v_care_profile_id is not null
       or v_care_roster_id is not null
    union
    select
      receiver.matched_profile_id as profile_id,
      receiver.id as roster_id
    from public.bbb_extra_care_roster_links link
    join public.retreat_group_roster receiver
      on receiver.id = link.care_receiver_roster_id
    where link.source_batch = '20260614'
      and link.care_giver_roster_id = v_roster_id
      and receiver.matched_profile_id is not null
  )
  select exists(
    select 1
    from cared_targets target
    join public.bbb_assignments target_assignment
      on target_assignment.profile_id = target.profile_id
    where target_assignment.secret_revealed = true
      and target_assignment.secret_buddy_id = v_profile.id
  )
  into v_caught;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'careBuddy', jsonb_build_object(
      'name', v_care_name,
      'participantName', public.bu_clean_display_text(v_care_roster_name),
      'displayName', public.bu_clean_display_text(v_care.display_name),
      'nickname', coalesce(public.bu_clean_display_text(v_care.login_id::text), '')
    ),
    'extraCareBuddies', coalesce(v_extra_care_buddies, '[]'::jsonb),
    'secretBuddy', case
      when v_secret_profile_id is null and v_secret_roster_id is null then null
      when coalesce(v_assignment.secret_revealed, false) then jsonb_build_object(
        'revealed', true,
        'name', coalesce(public.bu_clean_display_text(v_secret_name), '이름 확인 중'),
        'participantName', public.bu_clean_display_text(v_secret_roster_name),
        'displayName', public.bu_clean_display_text(v_secret.display_name),
        'nickname', coalesce(public.bu_clean_display_text(v_secret.login_id::text), '')
      )
      else jsonb_build_object(
        'revealed', false,
        'hint', '아직 비밀이에요'
      )
    end,
    'caughtByBuddy', v_caught
  ) || v_photos;
end;
$$;

revoke all on function public.get_bbb_status(text) from public, anon, authenticated;
grant execute on function public.get_bbb_status(text) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
