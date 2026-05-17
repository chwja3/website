# Supabase Auth user import 가이드

## 목적

`profiles`에 이관된 기존 Sheet 유저를 Supabase Auth 사용자로 생성하고, `profiles.auth_user_id`와 연결한다. 기존 Sheet 비밀번호 해시는 Auth로 가져오지 않는다.

## 원칙

- Auth email은 사용자가 보지 않는 synthetic email을 쓴다.
- synthetic email 규칙은 `u_<sha256(trim(login_id))>@auth.beyond-us.local`이다.
- 생성 시 임시 랜덤 비밀번호를 사용하지만 출력하거나 저장하지 않는다.
- 모든 기존 유저는 `password_migration_required=true` 상태로 둔다.
- 실제 사용자는 이후 `reset_password_by_profile` 흐름으로 새 비밀번호를 설정해야 한다.
- service role key는 PowerShell 환경변수로만 넣고 코드, 문서, 채팅에 남기지 않는다.

## Dry Run

JSON export만 기준으로 볼 때는 Supabase 연결 없이 실행할 수 있다.

```powershell
node "beyond_us\tools\supabase_import\create_auth_users.mjs" --file "C:\path\to\beyond_us_supabase_export_dev_YYYYMMDD_HHMMSS.json" --dry-run
```

Supabase에 이미 들어간 `profiles`와 실제 Auth 사용자 목록을 기준으로 보려면 환경변수를 넣고 실행한다.

```powershell
$env:SUPABASE_URL="https://프로젝트-ref.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="Supabase service role key"
node "beyond_us\tools\supabase_import\create_auth_users.mjs" --dry-run
```

한 명만 확인하려면 아래처럼 실행한다.

```powershell
node "beyond_us\tools\supabase_import\create_auth_users.mjs" --dry-run --login-id "SingSangSong"
```

## Apply 권장 순서

처음에는 개발자 계정 한 명만 생성해서 Auth email 형식과 profile 연결이 정상인지 확인한다.

```powershell
node "beyond_us\tools\supabase_import\create_auth_users.mjs" --apply --login-id "SingSangSong"
```

문제가 없으면 전체 생성한다.

```powershell
node "beyond_us\tools\supabase_import\create_auth_users.mjs" --apply
```

이 스크립트는 재실행 가능하다. 이미 `profiles.auth_user_id`가 있으면 건너뛰고, Auth 사용자만 존재하면 해당 Auth ID를 profile에 연결한다.

## 확인 쿼리

```sql
select count(*) as profiles from public.profiles;

select count(*) as linked_profiles
from public.profiles
where auth_user_id is not null;

select login_id, name, role, account_status, password_migration_required
from public.profiles
where auth_user_id is null
order by participant_no
limit 20;
```

`linked_profiles`가 `profiles`와 같으면 Auth 계정 생성과 연결이 완료된 것이다.

## 다음 보류 작업

- 사용자가 아이디, 이름, 교구, 새 비밀번호로 Auth password를 재설정하는 `reset_password_by_profile` Edge Function.
- 관리자가 특정 유저의 Auth password를 재설정하는 `admin_reset_password` Edge Function.
- 프론트 로그인에서 `login_id`를 synthetic email로 바꿔 `signInWithPassword`를 호출하는 API client.
