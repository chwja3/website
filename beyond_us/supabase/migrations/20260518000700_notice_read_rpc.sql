-- 사용자 앱과 관리자 화면에서 Supabase 공지 목록을 읽는 RPC를 제공한다.
begin;

create or replace function public.get_notices()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb := '[]'::jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'rowIndex', id::text,
    'id', id,
    'title', title,
    'content', content,
    'imageUrl', image_path,
    'createdAt', created_at,
    'updatedAt', updated_at
  ) order by created_at desc), '[]'::jsonb)
  into v_result
  from public.notices
  where visible = true;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'notices', coalesce(v_result, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_notices() from public, anon, authenticated;
grant execute on function public.get_notices() to anon, authenticated;

commit;
