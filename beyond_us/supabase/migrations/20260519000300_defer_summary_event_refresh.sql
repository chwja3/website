-- 이벤트 작성 후 사용자 요약 재계산이 트랜잭션 마지막에 실행되도록 보정한다.
begin;

drop trigger if exists refresh_summary_from_events on public.events;

create constraint trigger refresh_summary_from_events
after insert on public.events
deferrable initially deferred
for each row execute function public.bu_refresh_summary_from_event_trigger();

do $$
declare
  v_profile_id uuid;
begin
  for v_profile_id in
    select id
    from public.profiles
    where account_status = 'active'
  loop
    perform public.bu_refresh_profile_summary(v_profile_id);
  end loop;
end;
$$;

commit;
