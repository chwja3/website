-- 2026년 6월 20일 QT 완료 시 일반 카드팩 1장을 한 번만 지급한다.
begin;

create or replace function public.submit_qt_reflection_v2(
  p_login_id text,
  p_content_date date,
  p_answer1_text text default '',
  p_answer2_text text default '',
  p_answer3_text text default '',
  p_prayer_text text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_content_date date := public.bu_qt_content_date(p_content_date);
  v_answer1 text := left(trim(coalesce(p_answer1_text, '')), 500);
  v_answer2 text := left(trim(coalesce(p_answer2_text, '')), 500);
  v_answer3 text := left(trim(coalesce(p_answer3_text, '')), 500);
  v_prayer text := left(trim(coalesce(p_prayer_text, '')), 800);
  v_submission_id uuid;
  v_reward_reason text := 'qt_2026_06_20_complete';
  v_all_required_filled boolean := false;
  v_already_rewarded boolean := false;
  v_rewarded boolean := false;
  v_reward_event_id uuid;
  v_normal_pack_remaining integer := null;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if not public.bu_qt_reflection_enabled(v_content_date) then
    return jsonb_build_object('ok', false, 'error', 'qt_reflection_not_open');
  end if;

  if v_answer1 = '' and v_answer2 = '' and v_answer3 = '' and v_prayer = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_qt_reflection');
  end if;

  insert into public.qt_submissions (
    profile_id,
    content_date,
    answer_text,
    answer2_text,
    answer3_text,
    prayer_text,
    submitted_at
  )
  values (
    v_profile.id,
    v_content_date,
    v_answer1,
    v_answer2,
    v_answer3,
    v_prayer,
    now()
  )
  on conflict (profile_id, content_date) do update
  set answer_text = excluded.answer_text,
      answer2_text = excluded.answer2_text,
      answer3_text = excluded.answer3_text,
      prayer_text = excluded.prayer_text,
      updated_at = now()
  returning id into v_submission_id;

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
    'qt.submitted',
    'qt',
    v_content_date::text,
    1,
    jsonb_build_object(
      'contentDate', v_content_date,
      'answerCount', (
        case when v_answer1 <> '' then 1 else 0 end
        + case when v_answer2 <> '' then 1 else 0 end
        + case when v_answer3 <> '' then 1 else 0 end
      ),
      'hasPrayer', v_prayer <> ''
    ),
    'web'
  );

  v_all_required_filled := v_content_date = date '2026-06-20'
    and v_answer1 <> ''
    and v_answer2 <> ''
    and v_answer3 <> ''
    and v_prayer <> '';

  if v_all_required_filled then
    perform pg_advisory_xact_lock(hashtext('qt_completion_reward:' || v_profile.id::text || ':' || v_content_date::text));

    select exists(
      select 1
      from public.events
      where profile_id = v_profile.id
        and event_type = 'ticket.granted'
        and ref_type = 'qt'
        and ref_id = v_content_date::text
        and payload ->> 'reason' = v_reward_reason
    )
    into v_already_rewarded;

    if not coalesce(v_already_rewarded, false) then
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
          updated_at = now()
      returning normal_pack_remaining into v_normal_pack_remaining;

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
        'ticket.granted',
        'qt',
        v_content_date::text,
        1,
        jsonb_build_object(
          'reason', v_reward_reason,
          'label', '6월 20일 QT 완료',
          'contentDate', v_content_date,
          'answerCount', 3,
          'hasPrayer', true
        ),
        'web'
      )
      returning id into v_reward_event_id;

      v_rewarded := true;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'id', v_submission_id,
    'contentDate', v_content_date,
    'missionCleared', v_all_required_filled,
    'rewarded', v_rewarded,
    'alreadyRewarded', coalesce(v_already_rewarded, false),
    'rewardEventId', v_reward_event_id,
    'normalPackRemaining', v_normal_pack_remaining
  );
end;
$$;

create or replace function public.submit_qt_reflection(
  p_login_id text,
  p_content_date date,
  p_answer_text text,
  p_prayer_text text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.submit_qt_reflection_v2(
    p_login_id,
    p_content_date,
    p_answer_text,
    '',
    '',
    p_prayer_text
  );
end;
$$;

revoke all on function public.submit_qt_reflection_v2(text, date, text, text, text, text) from public, anon, authenticated;
revoke all on function public.submit_qt_reflection(text, date, text, text) from public, anon, authenticated;

grant execute on function public.submit_qt_reflection_v2(text, date, text, text, text, text) to authenticated;
grant execute on function public.submit_qt_reflection(text, date, text, text) to authenticated;

notify pgrst, 'reload schema';

commit;
