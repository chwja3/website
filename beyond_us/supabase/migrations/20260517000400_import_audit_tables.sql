-- Google Sheet 이관 원본과 변환 결과를 추적하는 감사 테이블 마이그레이션
begin;

create table if not exists public.migration_batches (
  id uuid primary key default gen_random_uuid(),
  source_environment text not null check (source_environment in ('dev', 'prod')),
  source_spreadsheet_id text,
  source_snapshot_label text,
  status text not null default 'planned' check (status in ('planned', 'running', 'completed', 'failed', 'cancelled')),
  started_at timestamptz,
  completed_at timestamptz,
  row_counts jsonb not null default '{}'::jsonb,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.legacy_sheet_rows (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid references public.migration_batches(id) on delete set null,
  source_environment text not null check (source_environment in ('dev', 'prod')),
  sheet_name text not null,
  row_number integer not null check (row_number > 0),
  row_key text,
  source_hash text not null,
  row_payload jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now()
);

create unique index if not exists legacy_sheet_rows_env_sheet_row_uid
on public.legacy_sheet_rows (source_environment, sheet_name, row_number);

create index if not exists legacy_sheet_rows_batch_idx
on public.legacy_sheet_rows (batch_id);

create index if not exists legacy_sheet_rows_sheet_idx
on public.legacy_sheet_rows (source_environment, sheet_name);

create table if not exists public.legacy_import_refs (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid references public.migration_batches(id) on delete set null,
  legacy_row_id uuid references public.legacy_sheet_rows(id) on delete cascade,
  source_environment text not null check (source_environment in ('dev', 'prod')),
  sheet_name text not null,
  row_number integer not null check (row_number > 0),
  target_table text not null,
  target_pk text,
  target_event_type text,
  transform_note text,
  created_at timestamptz not null default now()
);

create unique index if not exists legacy_import_refs_target_uid
on public.legacy_import_refs (
  source_environment,
  sheet_name,
  row_number,
  target_table,
  coalesce(target_event_type, '')
);

create index if not exists legacy_import_refs_batch_idx
on public.legacy_import_refs (batch_id);

create index if not exists legacy_import_refs_target_idx
on public.legacy_import_refs (target_table, target_pk);

create table if not exists public.migration_issues (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid references public.migration_batches(id) on delete set null,
  source_environment text not null check (source_environment in ('dev', 'prod')),
  sheet_name text,
  row_number integer,
  severity text not null default 'warning' check (severity in ('info', 'warning', 'error')),
  issue_code text not null,
  message text not null,
  payload jsonb not null default '{}'::jsonb,
  resolved boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists migration_issues_batch_idx
on public.migration_issues (batch_id, severity, resolved);

comment on table public.migration_batches is 'Google Sheet 데이터를 Supabase로 이관할 때 실행 단위를 기록하는 테이블.';
comment on column public.migration_batches.source_environment is 'dev 또는 prod 원본 구분.';
comment on column public.migration_batches.source_snapshot_label is '스냅샷 시각, 백업 이름, 실행 메모 등 사람이 읽는 기준값.';
comment on column public.migration_batches.row_counts is '시트별 읽은 행 수와 변환된 행 수 요약.';

comment on table public.legacy_sheet_rows is '원본 Google Sheet 행을 jsonb로 그대로 보관하는 감사 테이블.';
comment on column public.legacy_sheet_rows.sheet_name is '원본 Google Sheet 탭 이름.';
comment on column public.legacy_sheet_rows.row_number is '원본 시트의 1-based 행 번호.';
comment on column public.legacy_sheet_rows.row_key is 'nickname, eventId 등 원본 행을 사람이 식별하기 쉬운 값.';
comment on column public.legacy_sheet_rows.source_hash is '원본 row payload 기준 해시. 재실행 시 변경 여부 확인에 사용한다.';
comment on column public.legacy_sheet_rows.row_payload is '헤더와 값을 매핑한 원본 행 데이터.';

comment on table public.legacy_import_refs is '원본 Sheet 행이 어떤 Supabase 테이블과 행으로 변환됐는지 연결하는 테이블.';
comment on column public.legacy_import_refs.target_table is '변환 후 기록된 Supabase 대상 테이블.';
comment on column public.legacy_import_refs.target_pk is '변환 후 대상 행의 primary key 문자열.';
comment on column public.legacy_import_refs.target_event_type is 'events 변환일 때 event_type을 구분하기 위한 값.';

comment on table public.migration_issues is '이관 중 발견된 누락, 충돌, 검증 실패를 기록하는 테이블.';
comment on column public.migration_issues.issue_code is 'duplicate_login_id, unknown_user, event_projection_mismatch 같은 문제 코드.';
comment on column public.migration_issues.payload is '문제 재현과 확인에 필요한 추가 데이터.';

alter table public.migration_batches enable row level security;
alter table public.legacy_sheet_rows enable row level security;
alter table public.legacy_import_refs enable row level security;
alter table public.migration_issues enable row level security;

commit;
