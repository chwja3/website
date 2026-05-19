# PROD 점검 전환 컨텍스트

2026-05-19. 사용자는 main/Supabase 전환을 시작하기 전에 프로덕션 서버를 닫아달라고 요청했다. 일반 계정에는 `서버 이전 작업 중입니다. 더욱 빨라지고 쾌적해진 beyond us를 기대해주세요! 20:00~21:00` 문구를 표시하고, 개발자 계정 `SingSangSong`, `카니보어시즌2`만 통과시킨다.

2026-05-19. 새 Supabase 프로젝트 이름은 사용자가 `AGC retreat PROD`라고 알려줬다. 실제 프론트 상수 교체와 import 작업에는 PROD Supabase project URL, anon key, service role key가 필요하다.

2026-05-19. `APP_VERSION`은 `20260519a`로 올렸고, `app.html`, `sw.js`, `version.txt`를 같은 버전으로 맞췄다. `node --check beyond_us\app.js`, admin inline script syntax check, `git diff --check`를 통과했다.

2026-05-19. dev 커밋 `048b080`을 원격에 push했고, main에 병합 후 원격 main을 `75f1866`까지 push했다. Cloudflare `website-78h.pages.dev`에서 앱과 admin 모두 점검 모드 상수와 안내 문구가 배포된 것을 확인했다.

2026-05-19. 점검 중 신규 가입, 비밀번호 재설정, 닉네임 찾기, legacy password upgrade 같은 비개발자 쓰기/조회 진입도 막도록 보강했다. 캐시 버전은 `20260519b`로 올렸다.

2026-05-19. PROD Supabase 프로젝트 URL과 publishable key를 받았고, 프론트 `app.js`, `admin.html`이 `AGC retreat PROD` 프로젝트를 바라보도록 바꿨다. service role key와 password pepper는 repo에 기록하지 않는다. 캐시 버전은 `20260519c`로 올렸다.

2026-05-19. PROD Supabase Edge Functions `app-auth`, `legacy-password-upgrade`, `admin-reset-password`를 `AGC retreat PROD` 프로젝트에 배포했다. Dashboard secret에는 `LEGACY_PASSWORD_PEPPER`만 수동 추가했고, `SUPABASE_URL`, `SUPABASE_SECRET_KEYS`는 Supabase 기본 제공 secret을 사용한다.

2026-05-19. SQL migration은 PROD bundle로 실행했고, `20260518001500_dev_reset_cards.sql`은 제외했다. PROD Sheet export 파일은 `beyond_us_supabase_export_prod_20260519_204734.json`이고, `sourceEnvironment`는 `prod`, 총 25개 sheet, 2,187 row다.

2026-05-19. PROD import 결과: 원본 row 2,187개를 `legacy_sheet_rows`에 적재했고, 정규 테이블에는 profiles 170, active profiles 167, events 846, user inventory 166, user cards 55, user summary 167, mission progress 139, raffle tickets 155, H&P entries 160, H&P guesses 50, notices 3, inquiries 76을 적재했다. legacy auth hashes 170개와 Supabase Auth user 170개도 생성했다.

2026-05-19. 검증 결과: active profile 중 `auth_user_id` 누락 0, raffle excluded user의 active raffle ticket 0. 추첨권 import가 `raffle.*` 이벤트 155개를 추가 생성해 최종 Events count는 1,001이다. 공개 RPC `get_app_bootstrap`는 currentWeek 2, `get_notices`는 3건으로 정상 응답했다. migration warning은 `TabSettings`의 `specialPack` 중복 1건과 유저 참조 없는 과거 `BBBPhotos` 4건이다.
