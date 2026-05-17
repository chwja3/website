-- 사진 인증, H&P, 관리자 화면을 Supabase RPC로 전환하는 함수 모음
begin;

insert into storage.buckets (id, name, "public")
values (
  'beyond-us-photos',
  'beyond-us-photos',
  true
)
on conflict (id) do update
set "public" = excluded."public";

drop policy if exists "beyond_us_photos_select" on storage.objects;
drop policy if exists "beyond_us_photos_insert" on storage.objects;
drop policy if exists "beyond_us_photos_update" on storage.objects;
drop policy if exists "beyond_us_photos_delete" on storage.objects;

create policy "beyond_us_photos_select"
on storage.objects for select
to anon, authenticated
using (bucket_id = 'beyond-us-photos');

create policy "beyond_us_photos_insert"
on storage.objects for insert
to authenticated
with check (bucket_id = 'beyond-us-photos');

create policy "beyond_us_photos_update"
on storage.objects for update
to authenticated
using (bucket_id = 'beyond-us-photos')
with check (bucket_id = 'beyond-us-photos');

create policy "beyond_us_photos_delete"
on storage.objects for delete
to authenticated
using (bucket_id = 'beyond-us-photos');

create or replace function public.bu_admin_profile()
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_auth_uid uuid := auth.uid();
begin
  if v_auth_uid is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select *
  into v_profile
  from public.profiles
  where auth_user_id = v_auth_uid
    and account_status = 'active'
    and (role in ('admin', 'dev') or is_dev = true)
  limit 1;

  if v_profile.id is null then
    raise exception 'admin_required' using errcode = 'P0001';
  end if;

  return v_profile;
end;
$$;

create or replace function public.bu_bbb_section_open(p_key text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settings jsonb := '{}'::jsonb;
  v_open text;
begin
  select coalesce(value_json, '{}'::jsonb)
  into v_settings
  from public.app_settings
  where key = 'bbb_settings';

  v_open := v_settings -> coalesce(p_key, '') ->> 'open';
  if v_open is null then
    return false;
  end if;
  return v_open::boolean;
exception when others then
  return false;
end;
$$;

create or replace function public.bu_photo_payload(p_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m1 public.mission_photo_submissions%rowtype;
  v_m2 public.mission_photo_submissions%rowtype;
  v_m3 jsonb := '[]'::jsonb;
  v_spots jsonb := '[]'::jsonb;
  v_rewarded boolean := false;
begin
  select *
  into v_m1
  from public.mission_photo_submissions
  where profile_id = p_profile_id
    and mission_key = 'bbb_m1'
  order by updated_at desc
  limit 1;

  select *
  into v_m2
  from public.mission_photo_submissions
  where profile_id = p_profile_id
    and mission_key = 'bbb_m2'
  order by updated_at desc
  limit 1;

  select coalesce(jsonb_agg(s.storage_path order by gs.idx), '[]'::jsonb)
  into v_m3
  from generate_series(0, 6) as gs(idx)
  left join lateral (
    select storage_path
    from public.mission_photo_submissions
    where profile_id = p_profile_id
      and mission_key = 'pilgrim'
      and spot_index = gs.idx
      and approval_status <> 'rejected'
    order by updated_at desc
    limit 1
  ) s on true;

  select coalesce(to_jsonb(spot_indices), '[]'::jsonb),
         reward_event_id is not null
  into v_spots, v_rewarded
  from public.pilgrim_assignments
  where profile_id = p_profile_id;

  return jsonb_build_object(
    'myPhoto', v_m1.storage_path,
    'm1ApprovalStatus', coalesce(v_m1.approval_status::text, ''),
    'm1Rewarded', v_m1.reward_event_id is not null,
    'myPhotoM2', v_m2.storage_path,
    'm2ApprovalStatus', coalesce(v_m2.approval_status::text, ''),
    'm2Rewarded', v_m2.reward_event_id is not null,
    'myPhotoM3', coalesce(v_m3, '[]'::jsonb),
    'm3AssignedSpots', coalesce(v_spots, '[]'::jsonb),
    'm3Rewarded', coalesce(v_rewarded, false)
  );
end;
$$;

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
  v_photos jsonb := '{}'::jsonb;
  v_caught boolean := false;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  v_photos := public.bu_photo_payload(v_profile.id);

  select *
  into v_assignment
  from public.bbb_assignments
  where profile_id = v_profile.id;

  if v_assignment.profile_id is null then
    return jsonb_build_object(
      'ok', false,
      'source', 'supabase',
      'error', 'no_match'
    ) || v_photos;
  end if;

  select *
  into v_care
  from public.profiles
  where id = v_assignment.care_buddy_id;

  select *
  into v_secret
  from public.profiles
  where id = v_assignment.secret_buddy_id;

  select exists(
    select 1
    from public.bbb_assignments other_assignment
    where other_assignment.care_buddy_id = v_profile.id
      and other_assignment.secret_revealed = true
  )
  into v_caught;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'careBuddy', jsonb_build_object(
      'name', coalesce(v_care.display_name, v_care.name, v_care.login_id),
      'nickname', v_care.login_id
    ),
    'secretBuddy', case
      when v_secret.id is null then null
      when v_assignment.secret_revealed then jsonb_build_object(
        'revealed', true,
        'name', coalesce(v_secret.display_name, v_secret.name, v_secret.login_id),
        'nickname', v_secret.login_id
      )
      else jsonb_build_object('revealed', false)
    end,
    'caughtByBuddy', coalesce(v_caught, false)
  ) || v_photos;
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
  v_spots smallint[];
  v_completed integer := 0;
  v_required integer := 2;
  v_rewarded boolean := false;
  v_reward_event_id uuid;
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
    v_mission_key := 'pilgrim';
    if not (v_profile.is_dev or public.bu_bbb_section_open('m3')) then
      return jsonb_build_object('ok', false, 'error', 'not_open');
    end if;
    begin
      v_spot_index := coalesce(p_spot_index, split_part(v_mission_type, '_', 2)::integer)::smallint;
    exception when others then
      return jsonb_build_object('ok', false, 'error', 'invalid_spot');
    end;
    if v_spot_index < 0 or v_spot_index > 6 then
      return jsonb_build_object('ok', false, 'error', 'invalid_spot');
    end if;
  else
    return jsonb_build_object('ok', false, 'error', 'invalid_mission_type');
  end if;

  if v_mission_key in ('bbb_m1', 'bbb_m2') then
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
  end if;

  select spot_indices
  into v_spots
  from public.pilgrim_assignments
  where profile_id = v_profile.id
  for update;

  if v_spots is null then
    select array_agg(spot_index order by random())
    into v_spots
    from (
      select spot_index
      from public.pilgrim_spots
      where enabled = true
      order by random()
      limit 2
    ) selected_spots;

    if array_length(v_spots, 1) <> 2 then
      return jsonb_build_object('ok', false, 'error', 'not_enough_spots');
    end if;

    insert into public.pilgrim_assignments (profile_id, spot_indices)
    values (v_profile.id, v_spots);
  end if;

  if not (v_spot_index = any(v_spots)) then
    return jsonb_build_object('ok', false, 'error', 'not_assigned_spot');
  end if;

  select *
  into v_existing
  from public.mission_photo_submissions
  where profile_id = v_profile.id
    and mission_key = 'pilgrim'
    and spot_index = v_spot_index
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
      v_profile.id,
      'pilgrim',
      v_spot_index,
      v_storage_path,
      'approved',
      now()
    );
  else
    update public.mission_photo_submissions
    set storage_path = v_storage_path,
        approval_status = 'approved',
        approved_at = now(),
        rejected_at = null,
        rejected_by = null,
        rejection_reason = null,
        updated_at = now()
    where id = v_existing.id;
  end if;

  select count(distinct spot_index)::integer
  into v_completed
  from public.mission_photo_submissions
  where profile_id = v_profile.id
    and mission_key = 'pilgrim'
    and approval_status = 'approved'
    and spot_index = any(v_spots);

  v_required := coalesce(array_length(v_spots, 1), 2);

  if v_completed >= v_required then
    select reward_event_id
    into v_reward_event_id
    from public.pilgrim_assignments
    where profile_id = v_profile.id
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
          v_profile.id,
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
        v_profile.id,
        'card.granted',
        'pilgrim',
        '10',
        1,
        jsonb_build_object('reason', 'pilgrim_completed', 'spots', to_jsonb(v_spots)),
        'web'
      )
      returning id into v_reward_event_id;

      update public.pilgrim_assignments
      set completed_at = coalesce(completed_at, now()),
          reward_event_id = v_reward_event_id
      where profile_id = v_profile.id;

      v_rewarded := true;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'pendingApproval', false,
    'rewarded', v_rewarded
  ) || public.bu_photo_payload(v_profile.id);
end;
$$;

create or replace function public.delete_mission_photo(
  p_login_id text,
  p_mission_type text,
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
  v_mission_key text;
  v_spot_index smallint;
  v_existing public.mission_photo_submissions%rowtype;
  v_reward_event_id uuid;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if v_mission_type in ('', 'm1', 'bbb_m1') then
    v_mission_key := 'bbb_m1';
  elsif v_mission_type in ('m2', 'bbb_m2') then
    v_mission_key := 'bbb_m2';
  elsif v_mission_type like 'm3_%' or v_mission_type = 'pilgrim' then
    v_mission_key := 'pilgrim';
    begin
      v_spot_index := coalesce(p_spot_index, split_part(v_mission_type, '_', 2)::integer)::smallint;
    exception when others then
      return jsonb_build_object('ok', false, 'error', 'invalid_spot');
    end;
  else
    return jsonb_build_object('ok', false, 'error', 'invalid_mission_type');
  end if;

  if v_mission_key = 'pilgrim' then
    select reward_event_id
    into v_reward_event_id
    from public.pilgrim_assignments
    where profile_id = v_profile.id;

    if v_reward_event_id is not null then
      return jsonb_build_object('ok', false, 'error', 'rewarded_locked');
    end if;
  end if;

  select *
  into v_existing
  from public.mission_photo_submissions
  where profile_id = v_profile.id
    and mission_key = v_mission_key
    and (v_mission_key <> 'pilgrim' or spot_index = v_spot_index)
  order by updated_at desc
  limit 1;

  if v_existing.id is null then
    return jsonb_build_object('ok', true, 'source', 'supabase', 'deleted', false) || public.bu_photo_payload(v_profile.id);
  end if;

  if v_existing.approval_status = 'approved' and v_existing.reward_event_id is not null then
    return jsonb_build_object('ok', false, 'error', 'approved_locked');
  end if;

  delete from public.mission_photo_submissions
  where id = v_existing.id;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'deleted', true,
    'deletedStoragePath', v_existing.storage_path
  ) || public.bu_photo_payload(v_profile.id);
end;
$$;

create or replace function public.get_hold_pray(
  p_login_id text,
  p_week_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_week_key text := nullif(trim(coalesce(p_week_key, '')), '');
  v_cards jsonb := '[]'::jsonb;
  v_correct_map jsonb := '{}'::jsonb;
  v_revision text := '';
  v_ticket_awarded boolean := false;
  v_ticket_idx integer := -1;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  v_week_key := coalesce(v_week_key, 'w' || public.bu_current_week()::text);

  with ordered_cards as (
    select
      row_number() over (order by created_at, id) - 1 as card_index,
      content,
      anonymous,
      updated_at
    from public.hold_pray_entries
    where visible = true
      and coalesce(week_key, v_week_key) = v_week_key
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'content', content,
      'anon', anonymous
    ) order by card_index), '[]'::jsonb),
    coalesce(max(updated_at)::text, '')
  into v_cards, v_revision
  from ordered_cards;

  select coalesce(jsonb_object_agg(card_index::text, guessed_name), '{}'::jsonb)
  into v_correct_map
  from public.hold_pray_guesses
  where profile_id = v_profile.id
    and week_key = v_week_key
    and correct = true;

  select exists(
    select 1
    from public.events
    where profile_id = v_profile.id
      and event_type = 'ticket.granted'
      and ref_type = 'hold_pray'
      and week_key = v_week_key
  )
  into v_ticket_awarded;

  select coalesce((payload ->> 'cardIndex')::integer, -1)
  into v_ticket_idx
  from public.events
  where profile_id = v_profile.id
    and event_type = 'ticket.granted'
    and ref_type = 'hold_pray'
    and week_key = v_week_key
  order by occurred_at desc
  limit 1;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'weekKey', v_week_key,
    'hpRevision', v_revision,
    'cards', coalesce(v_cards, '[]'::jsonb),
    'correctMap', coalesce(v_correct_map, '{}'::jsonb),
    'ticketAlreadyAwarded', coalesce(v_ticket_awarded, false),
    'ticketCardIdx', coalesce(v_ticket_idx, -1),
    'hintReplies', '{}'::jsonb
  );
end;
$$;

create or replace function public.submit_hold_pray_guess(
  p_login_id text,
  p_week_key text,
  p_card_index integer,
  p_guess text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_week_key text := coalesce(nullif(trim(coalesce(p_week_key, '')), ''), 'w' || public.bu_current_week()::text);
  v_guess text := trim(coalesce(p_guess, ''));
  v_entry record;
  v_owner public.profiles%rowtype;
  v_correct boolean := false;
  v_ticket_awarded boolean := false;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  if v_guess = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_guess');
  end if;

  select *
  into v_entry
  from (
    select
      row_number() over (order by hp.created_at, hp.id) - 1 as card_index,
      hp.*
    from public.hold_pray_entries hp
    where hp.visible = true
      and coalesce(hp.week_key, v_week_key) = v_week_key
  ) ordered_cards
  where card_index = p_card_index;

  if v_entry.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_entry.profile_id is not null and v_entry.anonymous = false then
    select *
    into v_owner
    from public.profiles
    where id = v_entry.profile_id;

    v_correct := lower(v_guess) in (
      lower(coalesce(v_owner.login_id, '')),
      lower(coalesce(v_owner.name, '')),
      lower(coalesce(v_owner.display_name, ''))
    );
  end if;

  insert into public.hold_pray_guesses (
    profile_id,
    week_key,
    card_index,
    guessed_name,
    correct,
    answered_at
  )
  values (
    v_profile.id,
    v_week_key,
    p_card_index,
    v_guess,
    v_correct,
    now()
  )
  on conflict (profile_id, week_key, card_index) do update
  set guessed_name = excluded.guessed_name,
      correct = excluded.correct,
      answered_at = now();

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    ref_id,
    week_key,
    payload,
    source
  )
  values (
    v_profile.id,
    'hp.guessed',
    'hold_pray',
    p_card_index::text,
    v_week_key,
    jsonb_build_object('guess', v_guess, 'correct', v_correct),
    'web'
  );

  if v_correct and v_week_key in ('w3', 'w6') and not exists(
    select 1
    from public.events
    where profile_id = v_profile.id
      and event_type = 'ticket.granted'
      and ref_type = 'hold_pray'
      and week_key = v_week_key
  ) then
    insert into public.user_inventory (
      profile_id,
      normal_pack_earned,
      normal_pack_remaining
    )
    values (
      v_profile.id,
      1,
      1
    )
    on conflict (profile_id) do update
    set normal_pack_earned = public.user_inventory.normal_pack_earned + 1,
        normal_pack_remaining = public.user_inventory.normal_pack_remaining + 1,
        updated_at = now();

    insert into public.events (
      profile_id,
      event_type,
      ref_type,
      amount,
      week_key,
      payload,
      source
    )
    values (
      v_profile.id,
      'ticket.granted',
      'hold_pray',
      1,
      v_week_key,
      jsonb_build_object('reason', 'hold_pray_guess', 'cardIndex', p_card_index),
      'web'
    );

    v_ticket_awarded := true;
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'correct', v_correct,
    'ticketAwarded', v_ticket_awarded
  );
end;
$$;

create or replace function public.post_hold_pray_hint(
  p_login_id text,
  p_week_key text,
  p_card_index integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_week_key text := coalesce(nullif(trim(coalesce(p_week_key, '')), ''), 'w' || public.bu_current_week()::text);
  v_entry record;
  v_owner public.profiles%rowtype;
  v_answer text := '';
  v_hint_id uuid;
  v_inquiry_id uuid;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  select *
  into v_entry
  from (
    select
      row_number() over (order by hp.created_at, hp.id) - 1 as card_index,
      hp.*
    from public.hold_pray_entries hp
    where hp.visible = true
      and coalesce(hp.week_key, v_week_key) = v_week_key
  ) ordered_cards
  where card_index = p_card_index;

  if v_entry.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_entry.profile_id is not null then
    select *
    into v_owner
    from public.profiles
    where id = v_entry.profile_id;
    v_answer := coalesce(v_owner.display_name, v_owner.name, v_owner.login_id, '');
  end if;

  insert into public.hold_pray_hints (
    profile_id,
    week_key,
    card_index,
    hint_text
  )
  values (
    v_profile.id,
    v_week_key,
    p_card_index,
    'requested'
  )
  returning id into v_hint_id;

  insert into public.inquiries (
    profile_id,
    content
  )
  values (
    v_profile.id,
    '[H&P 힌트 요청] 주차: ' || v_week_key || ', 카드: ' || (p_card_index + 1)::text || '번 | 정답: ' || v_answer
  )
  returning id into v_inquiry_id;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'id', v_inquiry_id,
    'hintId', v_hint_id
  );
end;
$$;

create or replace function public.bu_issue_special_pack_for_photo(
  p_profile_id uuid,
  p_mission_key text,
  p_admin_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
begin
  insert into public.user_inventory (
    profile_id,
    special_pack_earned,
    special_pack_remaining
  )
  values (
    p_profile_id,
    1,
    1
  )
  on conflict (profile_id) do update
  set special_pack_earned = public.user_inventory.special_pack_earned + 1,
      special_pack_remaining = public.user_inventory.special_pack_remaining + 1,
      updated_at = now();

  insert into public.events (
    profile_id,
    event_type,
    ref_type,
    amount,
    payload,
    source,
    created_by
  )
  values (
    p_profile_id,
    'special_pack.granted',
    p_mission_key,
    1,
    jsonb_build_object('reason', 'photo_approved', 'missionKey', p_mission_key),
    'admin',
    p_admin_id
  )
  returning id into v_event_id;

  return v_event_id;
end;
$$;

create or replace function public.admin_dispatch(
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_action text := coalesce(p_action, '');
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_result jsonb;
  v_week integer;
  v_week_key text;
  v_query text;
  v_limit integer;
  v_profile public.profiles%rowtype;
  v_submission public.mission_photo_submissions%rowtype;
  v_event_id uuid;
  v_released integer := 0;
begin
  v_admin := public.bu_admin_profile();

  if v_action = 'getUsers' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'nickname', login_id,
      'name', name,
      'parish', parish,
      'createdAt', created_at
    ) order by created_at desc), '[]'::jsonb)
    into v_result
    from public.profiles
    where account_status = 'active';

    return jsonb_build_object('ok', true, 'source', 'supabase', 'users', coalesce(v_result, '[]'::jsonb));
  end if;

  if v_action = 'dashboard' then
    return public.get_app_bootstrap();
  end if;

  if v_action = 'getCurrentWeek' then
    return jsonb_build_object('ok', true, 'source', 'supabase', 'week', public.bu_current_week());
  end if;

  if v_action = 'setCurrentWeek' then
    v_week := greatest(1, least(6, coalesce((v_payload ->> 'week')::integer, 1)));
    insert into public.app_settings (key, value_json, value_type, note)
    values ('current_week', to_jsonb(v_week), 'number', '현재 주차')
    on conflict (key) do update
    set value_json = excluded.value_json,
        value_type = excluded.value_type,
        updated_at = now();
    return jsonb_build_object('ok', true, 'source', 'supabase', 'week', v_week);
  end if;

  if v_action = 'getMissionConfig' then
    v_week := coalesce((v_payload ->> 'week')::integer, public.bu_current_week());
    v_week_key := 'w' || v_week::text;

    select jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'week', v_week,
      'weekKey', mw.week_key,
      'title', mw.title,
      'threshold', mw.draw_threshold,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
          'item', mi.item_text,
          'score', mi.score_weight,
          'cat', coalesce(mi.category, 'L')
        ) order by mi.item_no)
        from public.mission_items mi
        where mi.week_key = mw.week_key
          and mi.enabled = true
      ), '[]'::jsonb)
    )
    into v_result
    from public.mission_weeks mw
    where mw.week_key = v_week_key;

    return coalesce(v_result, jsonb_build_object('ok', false, 'error', 'not_found'));
  end if;

  if v_action = 'setMissionConfig' then
    v_week := coalesce((v_payload ->> 'week')::integer, public.bu_current_week());
    v_week_key := 'w' || v_week::text;

    insert into public.mission_weeks (week_key, week_order, title, draw_threshold, enabled)
    values (
      v_week_key,
      v_week,
      coalesce(nullif(v_payload ->> 'title', ''), v_week::text || '주차'),
      coalesce((v_payload ->> 'threshold')::integer, 6),
      true
    )
    on conflict (week_key) do update
    set title = excluded.title,
        draw_threshold = excluded.draw_threshold,
        enabled = true,
        updated_at = now();

    update public.mission_items
    set enabled = false,
        updated_at = now()
    where week_key = v_week_key;

    insert into public.mission_items (week_key, item_no, item_text, score_weight, category, enabled)
    select
      v_week_key,
      ordinality::integer,
      coalesce(item ->> 'item', ''),
      coalesce((item ->> 'score')::integer, 1),
      coalesce(item ->> 'cat', 'L'),
      true
    from jsonb_array_elements(coalesce(v_payload -> 'items', '[]'::jsonb)) with ordinality as items(item, ordinality)
    where nullif(trim(coalesce(item ->> 'item', '')), '') is not null
    on conflict (week_key, item_no) do update
    set item_text = excluded.item_text,
        score_weight = excluded.score_weight,
        category = excluded.category,
        enabled = true,
        updated_at = now();

    return jsonb_build_object('ok', true, 'source', 'supabase', 'week', v_week);
  end if;

  if v_action = 'getTabSettings' then
    return public.bu_tab_settings_json();
  end if;

  if v_action = 'setTabSettings' then
    if jsonb_typeof(v_payload -> 'tabItems') = 'array' then
      insert into public.tab_settings (tab_key, label, enabled, status, sort_order)
      select
        item ->> 'key',
        coalesce(existing.label, item ->> 'key'),
        coalesce((item ->> 'enabled')::boolean, false),
        case when item ->> 'status' = 'open' then 'open' else 'closed' end::public.tab_status,
        coalesce(existing.sort_order, ordinality::integer * 10)
      from jsonb_array_elements(v_payload -> 'tabItems') with ordinality as items(item, ordinality)
      left join public.tab_settings existing on existing.tab_key = item ->> 'key'
      where nullif(item ->> 'key', '') is not null
      on conflict (tab_key) do update
      set enabled = excluded.enabled,
          status = excluded.status,
          updated_at = now();
    end if;

    if v_payload ? 'bbbSections' then
      insert into public.app_settings (key, value_json, value_type, note)
      values ('bbb_settings', v_payload -> 'bbbSections', 'json', 'B.B.B 섹션 오픈 상태')
      on conflict (key) do update
      set value_json = excluded.value_json,
          updated_at = now();
    end if;

    return public.bu_tab_settings_json();
  end if;

  if v_action = 'getNotices' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'rowIndex', id::text,
      'id', id,
      'title', title,
      'content', content,
      'imageUrl', image_path,
      'createdAt', created_at
    ) order by created_at desc), '[]'::jsonb)
    into v_result
    from public.notices
    where visible = true;

    return jsonb_build_object('ok', true, 'source', 'supabase', 'notices', coalesce(v_result, '[]'::jsonb));
  end if;

  if v_action = 'postNotice' then
    insert into public.notices (title, content, image_path, visible)
    values (
      coalesce(v_payload ->> 'title', ''),
      coalesce(v_payload ->> 'content', ''),
      nullif(v_payload ->> 'imageUrl', ''),
      true
    );
    return jsonb_build_object('ok', true, 'source', 'supabase');
  end if;

  if v_action = 'editNotice' then
    update public.notices
    set title = coalesce(v_payload ->> 'title', title),
        content = coalesce(v_payload ->> 'content', content),
        updated_at = now()
    where id = (v_payload ->> 'rowIndex')::uuid;
    return jsonb_build_object('ok', true, 'source', 'supabase');
  end if;

  if v_action = 'deleteNotice' then
    update public.notices
    set visible = false,
        updated_at = now()
    where id = (v_payload ->> 'rowIndex')::uuid;
    return jsonb_build_object('ok', true, 'source', 'supabase');
  end if;

  if v_action = 'getInquiries' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', i.id,
      'nickname', coalesce(p.login_id, ''),
      'name', coalesce(p.name, ''),
      'content', i.content,
      'reply', coalesce(i.reply, ''),
      'createdAt', i.created_at
    ) order by i.created_at desc), '[]'::jsonb)
    into v_result
    from public.inquiries i
    left join public.profiles p on p.id = i.profile_id;

    return jsonb_build_object('ok', true, 'source', 'supabase', 'inquiries', coalesce(v_result, '[]'::jsonb));
  end if;

  if v_action = 'replyInquiry' then
    update public.inquiries
    set reply = coalesce(v_payload ->> 'reply', ''),
        reply_by = v_admin.id,
        replied_at = case when coalesce(v_payload ->> 'reply', '') = '' then null else now() end,
        updated_at = now()
    where id = (v_payload ->> 'id')::uuid;
    return jsonb_build_object('ok', true, 'source', 'supabase');
  end if;

  if v_action = 'deleteInquiry' then
    delete from public.inquiries
    where id = (v_payload ->> 'id')::uuid;
    return jsonb_build_object('ok', true, 'source', 'supabase');
  end if;

  if v_action = 'adminGetBBBPhotoApprovals' then
    with photo_rows as (
      select
        s.*,
        p.login_id,
        p.name
      from public.mission_photo_submissions s
      join public.profiles p on p.id = s.profile_id
      where s.mission_key in ('bbb_m1', 'bbb_m2')
        and p.account_status = 'active'
    )
    select jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'pendingCount', count(*) filter (where approval_status = 'pending'),
      'approvedCount', count(*) filter (where approval_status = 'approved'),
      'rejectedCount', count(*) filter (where approval_status = 'rejected'),
      'photos', coalesce(jsonb_agg(jsonb_build_object(
        'userId', login_id,
        'name', name,
        'missionType', case mission_key when 'bbb_m1' then 'm1' else 'm2' end,
        'approvalStatus', approval_status,
        'photoBase64', storage_path,
        'uploadedAt', created_at,
        'rewardEventId', reward_event_id
      ) order by created_at desc), '[]'::jsonb)
    )
    into v_result
    from photo_rows;

    return coalesce(v_result, jsonb_build_object('ok', true, 'source', 'supabase', 'photos', '[]'::jsonb));
  end if;

  if v_action in ('adminApproveBBBPhoto', 'adminRejectBBBPhoto') then
    select *
    into v_profile
    from public.profiles
    where login_id = v_payload ->> 'userId'
      and account_status = 'active'
    limit 1;

    if v_profile.id is null then
      return jsonb_build_object('ok', false, 'error', 'user_not_found');
    end if;

    select *
    into v_submission
    from public.mission_photo_submissions
    where profile_id = v_profile.id
      and mission_key = case when v_payload ->> 'missionType' = 'm2' then 'bbb_m2' else 'bbb_m1' end
    order by updated_at desc
    limit 1
    for update;

    if v_submission.id is null then
      return jsonb_build_object('ok', false, 'error', 'photo_not_found');
    end if;

    if v_action = 'adminRejectBBBPhoto' then
      update public.mission_photo_submissions
      set approval_status = 'rejected',
          rejected_at = now(),
          rejected_by = v_admin.id,
          rejection_reason = 'admin_rejected',
          updated_at = now()
      where id = v_submission.id;
      return jsonb_build_object('ok', true, 'source', 'supabase', 'rejected', true);
    end if;

    if v_submission.reward_event_id is null then
      v_event_id := public.bu_issue_special_pack_for_photo(v_profile.id, v_submission.mission_key, v_admin.id);
    else
      v_event_id := v_submission.reward_event_id;
    end if;

    update public.mission_photo_submissions
    set approval_status = 'approved',
        approved_at = now(),
        approved_by = v_admin.id,
        reward_event_id = v_event_id,
        updated_at = now()
    where id = v_submission.id;

    return jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'rewarded', v_submission.reward_event_id is null,
      'rewardEventId', v_event_id
    );
  end if;

  if v_action = 'adminGetRaffleAttendance' then
    v_query := lower(trim(coalesce(v_payload ->> 'query', '')));
    v_limit := greatest(1, least(500, coalesce((v_payload ->> 'limit')::integer, 80)));

    with active_users as (
      select
        p.*,
        coalesce(ra.attended, false) as attended,
        (select count(*) from public.raffle_tickets rt where rt.profile_id = p.id and rt.active = true) as raffle_tickets
      from public.profiles p
      left join public.retreat_attendance ra on ra.profile_id = p.id
      where p.account_status = 'active'
        and (
          v_query = ''
          or lower(p.login_id::text) like '%' || v_query || '%'
          or lower(p.name) like '%' || v_query || '%'
          or lower(p.parish) like '%' || v_query || '%'
        )
      order by p.created_at desc
      limit v_limit
    ),
    deleted_users as (
      select *
      from public.profiles p
      where p.account_status <> 'active'
      order by p.deleted_at desc nulls last, p.updated_at desc
      limit 80
    )
    select jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'totalUsers', (select count(*) from public.profiles where account_status = 'active'),
      'attendedCount', (select count(*) from public.retreat_attendance ra join public.profiles p on p.id = ra.profile_id where p.account_status = 'active' and ra.attended = true),
      'raffleExcludedCount', (select count(*) from public.profiles where account_status = 'active' and raffle_excluded = true),
      'deletedCount', (select count(*) from public.profiles where account_status <> 'active'),
      'returnedUsers', (select count(*) from active_users),
      'filteredUsers', (select count(*) from active_users),
      'usersHasMore', false,
      'users', coalesce((select jsonb_agg(jsonb_build_object(
        'nickname', login_id,
        'name', name,
        'parish', parish,
        'attended', attended,
        'raffleExcluded', raffle_excluded,
        'raffleTickets', raffle_tickets
      ) order by created_at desc) from active_users), '[]'::jsonb),
      'deletedUsers', coalesce((select jsonb_agg(jsonb_build_object(
        'nickname', login_id,
        'name', name,
        'parish', parish,
        'inactiveAt', coalesce(deleted_at, updated_at)
      ) order by coalesce(deleted_at, updated_at) desc) from deleted_users), '[]'::jsonb)
    )
    into v_result;

    return v_result;
  end if;

  if v_action = 'adminSetRaffleAttendance' then
    select *
    into v_profile
    from public.profiles
    where login_id = v_payload ->> 'nickname'
      and account_status = 'active'
    limit 1;
    if v_profile.id is null then
      return jsonb_build_object('ok', false, 'error', 'user_not_found');
    end if;

    insert into public.retreat_attendance (profile_id, attended, attendance_status, updated_by)
    values (
      v_profile.id,
      coalesce((v_payload ->> 'attended')::boolean, false),
      (case when coalesce((v_payload ->> 'attended')::boolean, false) then 'attending' else 'pending' end)::public.attendance_status,
      v_admin.id
    )
    on conflict (profile_id) do update
    set attended = excluded.attended,
        attendance_status = excluded.attendance_status,
        updated_by = excluded.updated_by,
        updated_at = now();

    return jsonb_build_object('ok', true, 'source', 'supabase');
  end if;

  if v_action = 'adminSetRaffleExcluded' then
    select *
    into v_profile
    from public.profiles
    where login_id = v_payload ->> 'nickname'
      and account_status = 'active'
    limit 1;
    if v_profile.id is null then
      return jsonb_build_object('ok', false, 'error', 'user_not_found');
    end if;

    update public.profiles
    set raffle_excluded = coalesce((v_payload ->> 'excluded')::boolean, false),
        updated_at = now()
    where id = v_profile.id;

    if coalesce((v_payload ->> 'excluded')::boolean, false) then
      update public.raffle_tickets
      set active = false,
          profile_id = null,
          condition_key = null,
          revoked_at = now(),
          revoked_reason = 'admin_excluded',
          updated_at = now()
      where profile_id = v_profile.id
        and active = true;
      get diagnostics v_released = row_count;
    end if;

    return jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'released', v_released,
      'raffleTickets', (select count(*) from public.raffle_tickets where profile_id = v_profile.id and active = true)
    );
  end if;

  if v_action = 'adminDeactivateUser' then
    select *
    into v_profile
    from public.profiles
    where login_id = v_payload ->> 'nickname'
    limit 1;
    if v_profile.id is null then
      return jsonb_build_object('ok', false, 'error', 'user_not_found');
    end if;

    update public.raffle_tickets
    set active = false,
        profile_id = null,
        condition_key = null,
        revoked_at = now(),
        revoked_reason = 'user_deactivated',
        updated_at = now()
    where profile_id = v_profile.id
      and active = true;
    get diagnostics v_released = row_count;

    delete from public.user_cards where profile_id = v_profile.id;
    delete from public.user_inventory where profile_id = v_profile.id;

    update public.profiles
    set account_status = 'inactive',
        deleted_at = now(),
        updated_at = now()
    where id = v_profile.id;

    return jsonb_build_object('ok', true, 'source', 'supabase', 'nickname', v_profile.login_id, 'raffleReleased', v_released);
  end if;

  if v_action = 'adminRestoreUser' then
    update public.profiles
    set account_status = 'active',
        restored_at = now(),
        updated_at = now()
    where login_id = v_payload ->> 'nickname'
    returning * into v_profile;

    if v_profile.id is null then
      return jsonb_build_object('ok', false, 'error', 'user_not_found');
    end if;

    return jsonb_build_object('ok', true, 'source', 'supabase', 'nickname', v_profile.login_id, 'raffleIssued', '[]'::jsonb);
  end if;

  if v_action = 'adminGetRaffleTickets' then
    v_query := lower(trim(coalesce(v_payload ->> 'query', '')));
    v_limit := greatest(1, least(1000, coalesce((v_payload ->> 'limit')::integer, 80)));

    with ticket_rows as (
      select
        rt.*,
        p.login_id,
        p.name,
        p.parish,
        rc.label as condition_label
      from public.raffle_tickets rt
      left join public.profiles p on p.id = rt.profile_id
      left join public.raffle_conditions rc on rc.condition_key = rt.condition_key
      where v_query = ''
        or lpad(rt.ticket_no::text, 4, '0') like '%' || v_query || '%'
        or lower(coalesce(p.login_id::text, '')) like '%' || v_query || '%'
        or lower(coalesce(p.name, '')) like '%' || v_query || '%'
      order by rt.ticket_no
      limit v_limit
    )
    select jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'activeCount', (select count(*) from public.raffle_tickets where active = true),
      'availableCount', (select count(*) from public.raffle_tickets where active = false),
      'availableNumbers', coalesce((select jsonb_agg(lpad(ticket_no::text, 4, '0') order by ticket_no) from public.raffle_tickets where active = false limit 200), '[]'::jsonb),
      'returned', (select count(*) from ticket_rows),
      'filteredTotal', (select count(*) from ticket_rows),
      'hasMore', false,
      'tickets', coalesce((select jsonb_agg(jsonb_build_object(
        'ticket_no', lpad(ticket_no::text, 4, '0'),
        'active', active,
        'userId', login_id,
        'name', name,
        'parish', parish,
        'condition', condition_key,
        'condition_label', condition_label,
        'week_key', '',
        'issued_at', issued_at
      ) order by ticket_no) from ticket_rows), '[]'::jsonb)
    )
    into v_result;

    return v_result;
  end if;

  if v_action = 'adminFindRaffleTicket' then
    select jsonb_build_object(
      'ok', rt.active,
      'source', 'supabase',
      'ticket_no', lpad(rt.ticket_no::text, 4, '0'),
      'userId', p.login_id,
      'name', p.name,
      'parish', p.parish,
      'condition', rt.condition_key,
      'condition_label', rc.label,
      'week_key', '',
      'issued_at', rt.issued_at,
      'error', case when rt.active then null else 'available' end
    )
    into v_result
    from public.raffle_tickets rt
    left join public.profiles p on p.id = rt.profile_id
    left join public.raffle_conditions rc on rc.condition_key = rt.condition_key
    where rt.ticket_no = regexp_replace(coalesce(v_payload ->> 'ticket_no', ''), '[^0-9]', '', 'g')::integer;

    return coalesce(v_result, jsonb_build_object(
      'ok', false,
      'source', 'supabase',
      'error', 'not_found',
      'ticket_no', coalesce(v_payload ->> 'ticket_no', '')
    ));
  end if;

  if v_action = 'setCardReceivedQty' then
    select *
    into v_profile
    from public.profiles
    where login_id = v_payload ->> 'nickname'
      and account_status = 'active'
    limit 1;
    if v_profile.id is null then
      return jsonb_build_object('ok', false, 'error', 'user_not_found');
    end if;

    insert into public.physical_card_receipts (profile_id, card_id, received_qty, updated_by)
    values (
      v_profile.id,
      (v_payload ->> 'cardId')::smallint,
      greatest(0, coalesce((v_payload ->> 'qty')::integer, 0)),
      v_admin.id
    )
    on conflict (profile_id, card_id) do update
    set received_qty = excluded.received_qty,
        updated_by = excluded.updated_by,
        updated_at = now();

    return jsonb_build_object('ok', true, 'source', 'supabase');
  end if;

  if v_action = 'getTicketStats' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'nickname', p.login_id,
      'name', p.name,
      'remaining', coalesce(ui.normal_pack_remaining, 0) + coalesce(ui.special_pack_remaining, 0),
      'earned', coalesce(ui.normal_pack_earned, 0) + coalesce(ui.special_pack_earned, 0),
      'consumed', coalesce(ui.normal_pack_consumed, 0) + coalesce(ui.special_pack_consumed, 0)
    ) order by p.login_id), '[]'::jsonb)
    into v_result
    from public.profiles p
    left join public.user_inventory ui on ui.profile_id = p.id
    where p.account_status = 'active';

    return jsonb_build_object('ok', true, 'source', 'supabase', 'users', coalesce(v_result, '[]'::jsonb));
  end if;

  if v_action = 'getAdminTrades' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id,
      'status', case when t.status::text = 'requested' then 'pending' else t.status::text end,
      'requester', rp.login_id,
      'target', tp.login_id,
      'requesterCardName', rc.name,
      'targetCardName', tc.name,
      'createdAt', t.created_at
    ) order by t.created_at desc), '[]'::jsonb)
    into v_result
    from public.trades t
    join public.profiles rp on rp.id = t.requester_id
    join public.profiles tp on tp.id = t.target_id
    join public.cards rc on rc.id = t.requester_card_id
    join public.cards tc on tc.id = t.target_card_id;

    return jsonb_build_object('ok', true, 'source', 'supabase', 'trades', coalesce(v_result, '[]'::jsonb));
  end if;

  if v_action = 'adminGetBBB' then
    select jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'matches', coalesce((select jsonb_agg(jsonb_build_object(
        'from', p.login_id,
        'careBuddy', cp.login_id,
        'secretBuddy', sp.login_id
      ) order by p.login_id)
      from public.bbb_assignments ba
      join public.profiles p on p.id = ba.profile_id
      left join public.profiles cp on cp.id = ba.care_buddy_id
      left join public.profiles sp on sp.id = ba.secret_buddy_id), '[]'::jsonb),
      'messages', coalesce((select jsonb_agg(jsonb_build_object(
        'from', fp.login_id,
        'to', tp.login_id,
        'message', bm.message,
        'createdAt', bm.created_at
      ) order by bm.created_at desc)
      from public.bbb_messages bm
      join public.profiles fp on fp.id = bm.from_profile_id
      join public.profiles tp on tp.id = bm.to_profile_id), '[]'::jsonb)
    )
    into v_result;

    return v_result;
  end if;

  return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'unsupported_admin_action', 'action', v_action);
exception
  when invalid_text_representation then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'invalid_payload', 'action', v_action);
  when others then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', SQLERRM, 'action', v_action);
end;
$$;

grant execute on function public.bu_admin_profile() to authenticated;
grant execute on function public.bu_bbb_section_open(text) to authenticated;
grant execute on function public.bu_photo_payload(uuid) to authenticated;
grant execute on function public.get_bbb_status(text) to authenticated;
grant execute on function public.submit_mission_photo(text, text, text, integer) to authenticated;
grant execute on function public.delete_mission_photo(text, text, integer) to authenticated;
grant execute on function public.get_hold_pray(text, text) to authenticated;
grant execute on function public.submit_hold_pray_guess(text, text, integer, text) to authenticated;
grant execute on function public.post_hold_pray_hint(text, text, integer) to authenticated;
grant execute on function public.bu_issue_special_pack_for_photo(uuid, text, uuid) to authenticated;
grant execute on function public.admin_dispatch(text, jsonb) to authenticated;

commit;
