-- 관리자 앱 가입자 탭에서 추첨권을 직접 1장 지급하는 RPC를 추가한다.
begin;

create or replace function public.admin_grant_raffle_ticket(
  p_login_id text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_condition_key text := 'admin_manual_' || replace(gen_random_uuid()::text, '-', '');
  v_condition_label text := coalesce(v_reason, '운영 수동 지급');
  v_issue_result jsonb;
  v_event_id uuid;
begin
  v_admin := public.bu_admin_profile();

  select *
  into v_profile
  from public.profiles
  where login_id = p_login_id
    and account_status = 'active'
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'error', 'user_not_found');
  end if;

  if coalesce(v_profile.raffle_excluded, false) then
    return jsonb_build_object('ok', false, 'error', 'raffle_excluded');
  end if;

  insert into public.raffle_conditions (
    condition_key,
    label,
    enabled,
    sort_order
  )
  values (
    v_condition_key,
    v_condition_label,
    true,
    9000
  );

  v_issue_result := public.bu_issue_raffle_ticket(
    v_profile.id,
    v_condition_key,
    'admin',
    v_admin.id
  );

  if coalesce((v_issue_result->>'issued')::boolean, false) = false then
    return jsonb_build_object(
      'ok', false,
      'error', coalesce(v_issue_result->>'reason', 'raffle_issue_failed'),
      'issueResult', v_issue_result
    );
  end if;

  v_event_id := nullif(v_issue_result->>'eventId', '')::uuid;

  if v_event_id is not null then
    update public.events
    set payload = coalesce(payload, '{}'::jsonb) || jsonb_build_object(
          'reason', 'admin_manual_raffle',
          'reasonText', v_condition_label,
          'adminManual', true
        )
    where id = v_event_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'user', v_profile.login_id,
    'ticketNo', v_issue_result->>'ticketNo',
    'eventId', v_issue_result->>'eventId',
    'conditionKey', v_condition_key,
    'activeCount', coalesce((v_issue_result->>'activeCount')::integer, 0)
  );
end;
$$;

revoke all on function public.admin_grant_raffle_ticket(text, text) from public, anon, authenticated;
grant execute on function public.admin_grant_raffle_ticket(text, text) to authenticated;

commit;
