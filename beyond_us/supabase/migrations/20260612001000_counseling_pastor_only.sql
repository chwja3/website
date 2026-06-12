-- 익명 고민상담 정책 변경
-- 1) profiles.is_pastor 컬럼 추가 (staff보다 상위 권한 — 답변 작성 권한)
-- 2) 사역자 4명에게 권한 부여 (이름+교구 매칭, 동명이인 없음 확인됨)
-- 3) get_counseling_entries: publicEntries 반환 제거 (다른 사람 공개 고민 보기 X)
-- 4) admin_reply_counseling_entry: 사역자(is_pastor)만 통과
-- 5) admin_get_counseling_entries: 응답에 currentAdmin.isPastor 추가 (클라 UI 분기용)
begin;

alter table public.profiles
  add column if not exists is_pastor boolean not null default false;

comment on column public.profiles.is_pastor is '사역자 권한. 익명 고민상담 답변 작성 권한 등 staff 상위 권한에 사용.';

-- 사역자 4명 권한 부여 (이름+교구 매칭). 기존 role이 admin/dev면 유지, 아니면 admin으로 승급.
update public.profiles
set is_pastor = true,
    role = case when role in ('admin', 'dev') then role else 'admin'::public.profile_role end,
    updated_at = now()
where (name = '유광훈' and parish = '1청')
   or (name = '임동표' and parish = '2청')
   or (name = '현성수' and parish = '3청')
   or (name = '남우진' and parish = '4청');

-- 본인 고민만 조회 (공개된 다른 사람 고민 영역 제거)
create or replace function public.get_counseling_entries(p_login_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_mine jsonb := '[]'::jsonb;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'content', content,
    'reply', nullif(reply, ''),
    'repliedAt', replied_at,
    'createdAt', created_at
  ) order by created_at desc), '[]'::jsonb)
  into v_mine
  from public.anonymous_counseling_entries
  where profile_id = v_profile.id;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'mine', v_mine
  );
end;
$$;

-- 어드민 조회 응답에 사역자 여부 같이 반환 (클라이언트 UI 분기용)
create or replace function public.admin_get_counseling_entries()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_entries jsonb := '[]'::jsonb;
begin
  v_admin := public.bu_admin_profile();

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'content', content,
    'reply', nullif(reply, ''),
    'repliedAt', replied_at,
    'createdAt', created_at
  ) order by created_at desc), '[]'::jsonb)
  into v_entries
  from public.anonymous_counseling_entries;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'entries', v_entries,
    'currentAdmin', jsonb_build_object(
      'isPastor', coalesce(v_admin.is_pastor, false)
    )
  );
end;
$$;

-- 답변 작성/수정/삭제는 사역자만
create or replace function public.admin_reply_counseling_entry(
  p_id uuid,
  p_reply text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.profiles%rowtype;
  v_reply text := trim(coalesce(p_reply, ''));
begin
  v_admin := public.bu_admin_profile();

  if not coalesce(v_admin.is_pastor, false) then
    return jsonb_build_object('ok', false, 'error', 'pastor_required');
  end if;

  if char_length(v_reply) > 1200 then
    return jsonb_build_object('ok', false, 'error', 'reply_too_long');
  end if;

  update public.anonymous_counseling_entries
  set reply = nullif(v_reply, ''),
      replied_by = case when v_reply = '' then null else v_admin.id end,
      replied_at = case when v_reply = '' then null else now() end,
      updated_at = now()
  where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true, 'source', 'supabase');
end;
$$;

notify pgrst, 'reload schema';

commit;
