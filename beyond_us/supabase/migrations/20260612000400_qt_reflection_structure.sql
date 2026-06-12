-- QT 말씀 묵상 답변과 기도제목을 사용자별 날짜 단위로 저장하는 구조를 추가한다.
begin;

create table if not exists public.qt_submissions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  content_date date not null,
  answer_text text not null default '',
  prayer_text text not null default '',
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (profile_id, content_date),
  check (char_length(answer_text) <= 1200),
  check (char_length(prayer_text) <= 800)
);

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'set_qt_submissions_updated_at'
  ) then
    create trigger set_qt_submissions_updated_at
    before update on public.qt_submissions
    for each row execute function public.set_updated_at();
  end if;
end $$;

create index if not exists qt_submissions_profile_date_idx
on public.qt_submissions (profile_id, content_date desc);

alter table public.qt_submissions enable row level security;
revoke all on public.qt_submissions from public, anon, authenticated;

comment on table public.qt_submissions is '사용자별 Q.T. 말씀 묵상 답변과 기도제목 제출 내역.';
comment on column public.qt_submissions.content_date is 'QT 본문이 표시된 날짜.';
comment on column public.qt_submissions.answer_text is '사용자가 작성한 QT 질문 답변.';
comment on column public.qt_submissions.prayer_text is '사용자가 작성한 기도제목.';

create or replace function public.bu_qt_content_date(p_content_date date default null)
returns date
language sql
stable
set search_path = public
as $$
  select coalesce(p_content_date, (now() at time zone 'Asia/Seoul')::date);
$$;

create or replace function public.get_qt_reflection(
  p_login_id text,
  p_content_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_content_date date := public.bu_qt_content_date(p_content_date);
  v_submission public.qt_submissions%rowtype;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  select *
  into v_submission
  from public.qt_submissions
  where profile_id = v_profile.id
    and content_date = v_content_date
  limit 1;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'contentDate', v_content_date,
    'answerText', coalesce(v_submission.answer_text, ''),
    'prayerText', coalesce(v_submission.prayer_text, ''),
    'submittedAt', v_submission.submitted_at
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
declare
  v_profile public.profiles%rowtype;
  v_content_date date := public.bu_qt_content_date(p_content_date);
  v_answer text := left(trim(coalesce(p_answer_text, '')), 1200);
  v_prayer text := left(trim(coalesce(p_prayer_text, '')), 800);
  v_submission_id uuid;
begin
  v_profile := public.bu_auth_profile(p_login_id);

  if v_answer = '' and v_prayer = '' then
    return jsonb_build_object('ok', false, 'error', 'empty_qt_reflection');
  end if;

  insert into public.qt_submissions (
    profile_id,
    content_date,
    answer_text,
    prayer_text,
    submitted_at
  )
  values (
    v_profile.id,
    v_content_date,
    v_answer,
    v_prayer,
    now()
  )
  on conflict (profile_id, content_date) do update
  set answer_text = excluded.answer_text,
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
      'hasAnswer', v_answer <> '',
      'hasPrayer', v_prayer <> ''
    ),
    'web'
  );

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'id', v_submission_id,
    'contentDate', v_content_date
  );
end;
$$;

revoke all on function public.bu_qt_content_date(date) from public, anon, authenticated;
revoke all on function public.get_qt_reflection(text, date) from public, anon, authenticated;
revoke all on function public.submit_qt_reflection(text, date, text, text) from public, anon, authenticated;

grant execute on function public.bu_qt_content_date(date) to authenticated;
grant execute on function public.get_qt_reflection(text, date) to authenticated;
grant execute on function public.submit_qt_reflection(text, date, text, text) to authenticated;

commit;
