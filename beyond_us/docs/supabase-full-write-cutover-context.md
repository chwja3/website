# Supabase 전체 쓰기 전환 Context

2026-05-18. 사용자 요청에 따라 사진 업로드/삭제, H&P, admin 전환까지 이어서 진행한다. 이전 커밋에서는 카드팩, 교환, 문의, BBB 메시지와 시크릿 추측을 Supabase 우선으로 전환했다.

사진은 DB에 base64를 저장하지 않고 `beyond-us-photos` Storage bucket에 저장한다. 기존 앱 렌더링은 이미지 URL 문자열을 그대로 받으면 동작하므로, RPC는 signed/public URL 대신 Storage public URL을 내려주는 방향으로 시작한다.

admin은 기존 `ADMIN_PASSWORD`만으로는 Supabase RPC 권한을 안전하게 증명할 수 없다. 따라서 admin 페이지는 `beyondus_supabase_access_token`이 있고 해당 Auth 사용자의 `profiles.role`이 `admin` 또는 `dev`일 때 Supabase RPC를 먼저 호출한다. 토큰이 없으면 기존 GAS 호출이 유지된다.

## 2026-05-18 진행 기록

- `20260518000400_storage_hp_admin_rpcs.sql`를 추가했다.
- Supabase Storage bucket은 `beyond-us-photos`로 고정하고, 인증 사용자 업로드/수정/삭제와 공개 읽기 정책을 둔다.
- 사용자 앱 사진 제출은 Storage 업로드 후 `submit_mission_photo` RPC에 경로를 저장하는 방식으로 전환했다.
- MISSION 1, 2 사진은 제출 후 `pending` 상태가 되고, admin 승인 시 현장미션 카드팩 1장이 지급된다.
- MISSION 3 사진은 배정된 천로역정 스팟만 제출 가능하고, 두 스팟 완료 시 rare 카드 보상 이벤트를 만든다.
- H&P 읽기, 정답 추측, 힌트 요청은 `get_hold_pray`, `submit_hold_pray_guess`, `post_hold_pray_hint` RPC로 전환했다.
- admin 페이지의 공통 `get/post`는 Supabase Auth 토큰이 있을 때 `admin_dispatch`를 먼저 호출하고, 실패하거나 토큰이 없으면 GAS로 돌아간다.
- 공지 row id가 UUID가 될 수 있어서 inline handler 인자를 문자열로 안전하게 감쌌다.
- 앱 버전은 `20260518n`으로 동기화했다.
