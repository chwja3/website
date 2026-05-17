-- 기존 GAS 비밀번호 해시를 Supabase Auth 승격 전까지만 보관하는 마이그레이션
begin;

create table if not exists public.legacy_auth_hashes (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  login_id text not null unique,
  hash_version text not null default 'pwv1',
  password_hash text,
  migrated_at timestamptz,
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz,
  last_attempt_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (password_hash is not null or migrated_at is not null)
);

create trigger set_legacy_auth_hashes_updated_at
before update on public.legacy_auth_hashes
for each row execute function public.set_updated_at();

create index if not exists legacy_auth_hashes_login_idx
on public.legacy_auth_hashes (login_id);

create index if not exists legacy_auth_hashes_migration_idx
on public.legacy_auth_hashes (migrated_at, locked_until);

comment on table public.legacy_auth_hashes is 'GAS pwv1 비밀번호 해시를 Supabase Auth 비밀번호 승격 전까지만 보관하는 임시 테이블.';
comment on column public.legacy_auth_hashes.password_hash is 'pwv1$iterations$salt$hash 형식의 기존 GAS 해시. 승격 성공 후 null로 지운다.';
comment on column public.legacy_auth_hashes.migrated_at is '기존 비밀번호 검증 후 Supabase Auth password로 승격된 시각.';
comment on column public.legacy_auth_hashes.failed_attempts is 'legacy password 검증 실패 횟수. Edge Function rate limit에 사용한다.';
comment on column public.legacy_auth_hashes.locked_until is '실패 횟수 초과 시 임시 잠금 해제 시각.';

alter table public.legacy_auth_hashes enable row level security;

commit;
