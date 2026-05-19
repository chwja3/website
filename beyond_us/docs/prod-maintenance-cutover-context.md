# PROD 점검 전환 컨텍스트

2026-05-19. 사용자는 main/Supabase 전환을 시작하기 전에 프로덕션 서버를 닫아달라고 요청했다. 일반 계정에는 `서버 이전 작업 중입니다. 더욱 빨라지고 쾌적해진 beyond us를 기대해주세요! 20:00~21:00` 문구를 표시하고, 개발자 계정 `SingSangSong`, `카니보어시즌2`만 통과시킨다.

2026-05-19. 새 Supabase 프로젝트 이름은 사용자가 `AGC retreat PROD`라고 알려줬다. 실제 프론트 상수 교체와 import 작업에는 PROD Supabase project URL, anon key, service role key가 필요하다.

2026-05-19. `APP_VERSION`은 `20260519a`로 올렸고, `app.html`, `sw.js`, `version.txt`를 같은 버전으로 맞췄다. `node --check beyond_us\app.js`, admin inline script syntax check, `git diff --check`를 통과했다.
