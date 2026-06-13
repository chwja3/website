-- QT 6월 20일과 21일 묵상 답변 3개와 기도제목 저장을 지원한다.
begin;

alter table public.qt_submissions
  add column if not exists answer2_text text not null default '',
  add column if not exists answer3_text text not null default '';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'qt_submissions_answer2_text_len'
      and conrelid = 'public.qt_submissions'::regclass
  ) then
    alter table public.qt_submissions
      add constraint qt_submissions_answer2_text_len check (char_length(answer2_text) <= 500);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'qt_submissions_answer3_text_len'
      and conrelid = 'public.qt_submissions'::regclass
  ) then
    alter table public.qt_submissions
      add constraint qt_submissions_answer3_text_len check (char_length(answer3_text) <= 500);
  end if;
end $$;

comment on column public.qt_submissions.answer_text is '사용자가 작성한 QT 질문 1 답변.';
comment on column public.qt_submissions.answer2_text is '사용자가 작성한 QT 질문 2 답변.';
comment on column public.qt_submissions.answer3_text is '사용자가 작성한 QT 질문 3 답변.';

create or replace function public.bu_qt_reflection_enabled(p_content_date date)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_content_date in (date '2026-06-20', date '2026-06-21');
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
    'reflectionEnabled', public.bu_qt_reflection_enabled(v_content_date),
    'answerText', coalesce(v_submission.answer_text, ''),
    'answerTexts', jsonb_build_array(
      coalesce(v_submission.answer_text, ''),
      coalesce(v_submission.answer2_text, ''),
      coalesce(v_submission.answer3_text, '')
    ),
    'prayerText', coalesce(v_submission.prayer_text, ''),
    'submittedAt', v_submission.submitted_at
  );
end;
$$;

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

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'id', v_submission_id,
    'contentDate', v_content_date
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

revoke all on function public.bu_qt_reflection_enabled(date) from public, anon, authenticated;
revoke all on function public.get_qt_reflection(text, date) from public, anon, authenticated;
revoke all on function public.submit_qt_reflection_v2(text, date, text, text, text, text) from public, anon, authenticated;
revoke all on function public.submit_qt_reflection(text, date, text, text) from public, anon, authenticated;

grant execute on function public.bu_qt_reflection_enabled(date) to authenticated;
grant execute on function public.get_qt_reflection(text, date) to authenticated;
grant execute on function public.submit_qt_reflection_v2(text, date, text, text, text, text) to authenticated;
grant execute on function public.submit_qt_reflection(text, date, text, text) to authenticated;

notify pgrst, 'reload schema';

commit;
