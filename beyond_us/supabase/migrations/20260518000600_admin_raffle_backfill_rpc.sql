-- 관리자 화면에서 추첨권 정책 보정을 실행하는 RPC를 제공한다.
begin;

create or replace function public.admin_backfill_raffle_tickets()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_result jsonb;
begin
  v_admin := public.bu_admin_profile();
  v_result := public.backfill_raffle_tickets();

  return coalesce(v_result, '{}'::jsonb) || jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'admin', v_admin.login_id
  );
end;
$$;

revoke all on function public.admin_backfill_raffle_tickets() from public, anon, authenticated;
grant execute on function public.admin_backfill_raffle_tickets() to authenticated;

commit;
