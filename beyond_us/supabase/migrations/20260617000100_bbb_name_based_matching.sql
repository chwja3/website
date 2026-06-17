-- BBB 케어버디와 시크릿버디를 이름 기준으로 표시하고 판정한다.

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
      'name', coalesce(v_care.name, v_care.display_name, v_care.login_id),
      'nickname', v_care.login_id
    ),
    'secretBuddy', case
      when v_secret.id is null then null
      when v_assignment.secret_revealed then jsonb_build_object(
        'revealed', true,
        'name', coalesce(v_secret.name, v_secret.display_name, v_secret.login_id),
        'nickname', v_secret.login_id
      )
      else jsonb_build_object('revealed', false)
    end,
    'caughtByBuddy', coalesce(v_caught, false)
  ) || v_photos;
end;
$$;

revoke all on function public.get_bbb_status(text) from public, anon, authenticated;
grant execute on function public.get_bbb_status(text) to authenticated;

create or replace function public.guess_bbb_secret(p_login_id text, p_guess text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_assignment public.bbb_assignments%rowtype;
  v_secret public.profiles%rowtype;
  v_guess text := lower(trim(coalesce(p_guess, '')));
  v_secret_name text;
  v_correct boolean := false;
  v_rewarded boolean := false;
begin
  v_profile := public.bu_auth_profile(p_login_id);
  if v_guess = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_guess');
  end if;

  select *
  into v_assignment
  from public.bbb_assignments
  where profile_id = v_profile.id
  for update;

  if v_assignment.profile_id is null or v_assignment.secret_buddy_id is null then
    return jsonb_build_object('ok', false, 'error', 'no_match');
  end if;

  select *
  into v_secret
  from public.profiles
  where id = v_assignment.secret_buddy_id;

  v_secret_name := lower(trim(coalesce(v_secret.name, '')));
  v_correct := v_secret_name <> '' and v_guess = v_secret_name;

  if not v_correct then
    return jsonb_build_object('ok', true, 'source', 'supabase', 'correct', false);
  end if;

  if v_assignment.secret_revealed = false then
    update public.bbb_assignments
    set secret_revealed = true,
        updated_at = now()
    where profile_id = v_profile.id;

    insert into public.user_inventory (
      profile_id,
      special_pack_earned,
      special_pack_remaining
    )
    values (v_profile.id, 1, 1)
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
      source
    )
    values (
      v_profile.id,
      'special_pack.granted',
      'bbb_secret',
      1,
      jsonb_build_object('reason', 'bbb_secret_guess', 'secretBuddyName', v_secret.name),
      'web'
    );

    v_rewarded := true;
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'correct', true,
    'rewarded', v_rewarded,
    'alreadyRevealed', not v_rewarded,
    'secretName', coalesce(v_secret.name, v_secret.display_name, v_secret.login_id),
    'secretNickname', v_secret.login_id
  );
end;
$$;

revoke all on function public.guess_bbb_secret(text, text) from public, anon, authenticated;
grant execute on function public.guess_bbb_secret(text, text) to authenticated;

select pg_notify('pgrst', 'reload schema');
