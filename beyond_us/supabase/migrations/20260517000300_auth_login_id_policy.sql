-- Supabase Auth 전환을 위해 로그인 아이디의 대소문자 구분 정책을 고정하는 마이그레이션
begin;

alter table public.profiles
  alter column login_id type text using login_id::text;

comment on column public.profiles.login_id is '사용자가 로그인할 때 입력하는 아이디. 대소문자를 구분하며 synthetic Auth email 생성의 기준값으로 사용한다.';
comment on column public.profiles.password_migration_required is '기존 Sheet 계정 이관 후 사용자가 Supabase Auth 비밀번호를 새로 설정해야 하는지 여부.';

commit;
