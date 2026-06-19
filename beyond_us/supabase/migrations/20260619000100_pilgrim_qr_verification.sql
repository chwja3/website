-- 천로역정 스팟 완료를 스팟별 QR 토큰 검증으로 전환한다.
begin;

alter table public.pilgrim_spots
add column if not exists qr_token text;

update public.pilgrim_spots
set qr_token = replace(gen_random_uuid()::text, '-', '')
where qr_token is null
   or btrim(qr_token) = '';

alter table public.pilgrim_spots
alter column qr_token set not null;

create unique index if not exists pilgrim_spots_qr_token_uidx
on public.pilgrim_spots (qr_token);

comment on column public.pilgrim_spots.qr_token is '천로역정 스팟별 QR 검증 토큰. 관리자만 출력용 URL 생성에 사용한다.';

create or replace function public.bu_complete_pilgrim_spot(
  p_profile_id uuid,
  p_spot_index smallint,
  p_source text default 'qr'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.mission_photo_submissions%rowtype;
  v_spots smallint[];
  v_completed integer := 0;
  v_required integer := 2;
  v_rewarded boolean := false;
  v_reward_event_id uuid;
  v_storage_path text;
begin
  if p_spot_index is null or p_spot_index < 0 or p_spot_index > 6 then
    return jsonb_build_object('ok', false, 'error', 'invalid_spot');
  end if;

  if not exists (
    select 1
    from public.pilgrim_spots
    where spot_index = p_spot_index
      and enabled = true
  ) then
    return jsonb_build_object('ok', false, 'error', 'invalid_spot');
  end if;

  v_spots := public.bu_ensure_pilgrim_assignment(p_profile_id);

  if not (p_spot_index = any(v_spots)) then
    return jsonb_build_object('ok', false, 'error', 'not_assigned_spot');
  end if;

  v_storage_path := 'pilgrim_qr_verified/' || p_spot_index::text;

  select *
  into v_existing
  from public.mission_photo_submissions
  where profile_id = p_profile_id
    and mission_key = 'pilgrim'
    and spot_index = p_spot_index
  order by updated_at desc
  limit 1
  for update;

  if v_existing.id is null then
    insert into public.mission_photo_submissions (
      profile_id,
      mission_key,
      spot_index,
      storage_path,
      approval_status,
      approved_at
    )
    values (
      p_profile_id,
      'pilgrim',
      p_spot_index,
      v_storage_path,
      'approved',
      now()
    );
  else
    update public.mission_photo_submissions
    set storage_path = v_storage_path,
        approval_status = 'approved',
        approved_at = coalesce(approved_at, now()),
        rejected_at = null,
        rejected_by = null,
        rejection_reason = null,
        updated_at = now()
    where id = v_existing.id;
  end if;

  select count(distinct spot_index)::integer
  into v_completed
  from public.mission_photo_submissions
  where profile_id = p_profile_id
    and mission_key = 'pilgrim'
    and approval_status = 'approved'
    and spot_index = any(v_spots);

  v_required := coalesce(array_length(v_spots, 1), 2);

  if v_completed >= v_required then
    select reward_event_id
    into v_reward_event_id
    from public.pilgrim_assignments
    where profile_id = p_profile_id
    for update;

    if v_reward_event_id is null then
      if exists(select 1 from public.cards where id = 10) then
        insert into public.user_cards (
          profile_id,
          card_id,
          quantity,
          first_obtained_at
        )
        values (
          p_profile_id,
          10,
          1,
          now()
        )
        on conflict (profile_id, card_id) do update
        set quantity = public.user_cards.quantity + 1,
            first_obtained_at = coalesce(public.user_cards.first_obtained_at, now()),
            updated_at = now();
      end if;

      insert into public.events (
        profile_id,
        event_type,
        ref_type,
        ref_id,
        amount,
        payload,
        source
      )
      values (
        p_profile_id,
        'card.granted',
        'pilgrim',
        '10',
        1,
        jsonb_build_object('reason', 'pilgrim_completed', 'spots', to_jsonb(v_spots)),
        coalesce(nullif(p_source, ''), 'qr')
      )
      returning id into v_reward_event_id;

      update public.pilgrim_assignments
      set completed_at = coalesce(completed_at, now()),
          reward_event_id = v_reward_event_id
      where profile_id = p_profile_id;

      v_rewarded := true;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'pendingApproval', false,
    'rewarded', v_rewarded,
    'completedSpot', p_spot_index
  ) || public.bu_photo_payload(p_profile_id);
end;
$$;

create or replace function public.verify_pilgrim_qr(
  p_login_id text,
  p_spot_index integer,
  p_qr_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_spot_index smallint;
  v_token text := lower(btrim(coalesce(p_qr_token, '')));
  v_expected text;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if not (v_profile.is_dev or public.bu_bbb_section_open('m3')) then
    return jsonb_build_object('ok', false, 'error', 'not_open');
  end if;

  begin
    v_spot_index := p_spot_index::smallint;
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'invalid_spot');
  end;

  if v_spot_index < 0 or v_spot_index > 6 then
    return jsonb_build_object('ok', false, 'error', 'invalid_spot');
  end if;

  select lower(qr_token)
  into v_expected
  from public.pilgrim_spots
  where spot_index = v_spot_index
    and enabled = true;

  if v_expected is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_spot');
  end if;

  if v_token = '' or v_token is distinct from v_expected then
    return jsonb_build_object('ok', false, 'error', 'invalid_qr');
  end if;

  return public.bu_complete_pilgrim_spot(v_profile.id, v_spot_index, 'qr');
end;
$$;

create or replace function public.admin_get_pilgrim_qr_codes(
  p_app_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_base text := regexp_replace(btrim(coalesce(p_app_url, '')), '/+$', '');
  v_joiner text;
  v_rows jsonb;
begin
  v_admin := public.bu_admin_profile();

  if v_base = '' then
    v_base := 'app.html';
  end if;

  v_joiner := case when position('?' in v_base) > 0 then '&' else '?' end;

  select coalesce(jsonb_agg(jsonb_build_object(
    'spotIndex', spot_index,
    'spotNumber', spot_index + 1,
    'label', label,
    'enabled', enabled,
    'qrToken', qr_token,
    'qrUrl', v_base || v_joiner || 'pilgrimSpot=' || spot_index::text || '&pilgrimCode=' || qr_token
  ) order by spot_index), '[]'::jsonb)
  into v_rows
  from public.pilgrim_spots;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

create or replace function public.submit_mission_photo(
  p_login_id text,
  p_mission_type text,
  p_storage_path text,
  p_spot_index integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_mission_type text := lower(trim(coalesce(p_mission_type, '')));
  v_storage_path text := nullif(trim(coalesce(p_storage_path, '')), '');
  v_mission_key text;
  v_spot_index smallint;
  v_existing public.mission_photo_submissions%rowtype;
  v_assignment public.bbb_assignments%rowtype;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  if v_storage_path is null then
    return jsonb_build_object('ok', false, 'error', 'missing_photo');
  end if;

  if v_mission_type in ('m1', 'bbb_m1') then
    v_mission_key := 'bbb_m1';
    if not (v_profile.is_dev or public.bu_bbb_section_open('m1')) then
      return jsonb_build_object('ok', false, 'error', 'not_open');
    end if;
  elsif v_mission_type in ('m2', 'bbb_m2') then
    v_mission_key := 'bbb_m2';
    if not (v_profile.is_dev or public.bu_bbb_section_open('m2')) then
      return jsonb_build_object('ok', false, 'error', 'not_open');
    end if;
  elsif v_mission_type like 'm3_%' or v_mission_type = 'pilgrim' then
    begin
      v_spot_index := coalesce(p_spot_index, split_part(v_mission_type, '_', 2)::integer)::smallint;
    exception when others then
      return jsonb_build_object('ok', false, 'error', 'invalid_spot');
    end;
    if v_spot_index < 0 or v_spot_index > 6 then
      return jsonb_build_object('ok', false, 'error', 'invalid_spot');
    end if;
    return jsonb_build_object('ok', false, 'error', 'qr_required') || public.bu_photo_payload(v_profile.id);
  else
    return jsonb_build_object('ok', false, 'error', 'invalid_mission_type');
  end if;

  select *
  into v_assignment
  from public.bbb_assignments
  where profile_id = v_profile.id;

  if v_assignment.profile_id is null or v_assignment.care_buddy_id is null then
    return jsonb_build_object('ok', false, 'error', 'no_match');
  end if;

  select *
  into v_existing
  from public.mission_photo_submissions
  where profile_id = v_profile.id
    and mission_key = v_mission_key
  order by updated_at desc
  limit 1
  for update;

  if v_existing.id is not null and v_existing.approval_status = 'approved' and v_existing.reward_event_id is not null then
    return jsonb_build_object('ok', false, 'error', 'approved_locked');
  end if;

  if v_existing.id is null then
    insert into public.mission_photo_submissions (
      profile_id,
      mission_key,
      storage_path,
      approval_status
    )
    values (
      v_profile.id,
      v_mission_key,
      v_storage_path,
      'pending'
    );
  else
    update public.mission_photo_submissions
    set storage_path = v_storage_path,
        approval_status = 'pending',
        approved_at = null,
        approved_by = null,
        rejected_at = null,
        rejected_by = null,
        rejection_reason = null,
        updated_at = now()
    where id = v_existing.id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'pendingApproval', true,
    'rewarded', false
  ) || public.bu_photo_payload(v_profile.id);
end;
$$;

revoke all on function public.bu_complete_pilgrim_spot(uuid, smallint, text) from public, anon, authenticated;
revoke all on function public.verify_pilgrim_qr(text, integer, text) from public, anon, authenticated;
revoke all on function public.admin_get_pilgrim_qr_codes(text) from public, anon, authenticated;
revoke all on function public.submit_mission_photo(text, text, text, integer) from public, anon, authenticated;

grant execute on function public.verify_pilgrim_qr(text, integer, text) to authenticated;
grant execute on function public.admin_get_pilgrim_qr_codes(text) to authenticated;
grant execute on function public.submit_mission_photo(text, text, text, integer) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
