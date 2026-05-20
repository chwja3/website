-- H&P 기도제목 매칭 RPC가 PostgREST에 즉시 보이도록 스키마 캐시를 새로고침한다.
begin;

alter table public.hold_pray_entries
  add column if not exists owner_name_input text;

do $$
begin
  if to_regprocedure('public.admin_hold_pray_entry_matching(text)') is not null then
    grant execute on function public.admin_hold_pray_entry_matching(text) to authenticated;
  end if;

  if to_regprocedure('public.admin_match_hold_pray_entry(uuid,text)') is not null then
    grant execute on function public.admin_match_hold_pray_entry(uuid, text) to authenticated;
  end if;
end;
$$;

notify pgrst, 'reload schema';

commit;
