# Admin 앱 가입자 정렬 컨텍스트

2026-05-18. admin `앱 가입자` 탭은 기존 `adminGetRaffleAttendance` action을 통해 Supabase `admin_dispatch`를 호출한다. 현재 DB 함수는 active user를 `created_at desc`로 정렬하고 limit을 먼저 적용한다. 프론트에서만 정렬하면 첫 페이지에 포함된 일부 사용자만 교구/이름순이 되므로, 서버에서 정렬한 뒤 limit을 적용하는 새 RPC를 두기로 했다.

2026-05-18. `20260518001400_admin_attendance_sorted.sql`에서 `admin_get_raffle_attendance` RPC를 추가했다. active 가입자는 `1청`, `2청`, `3청`, `4청`, `VIP`, `교회학교/목양교구`, 기타 순으로 먼저 정렬하고, 같은 교구 안에서는 이름과 닉네임순으로 정렬한다. admin 프론트는 앱 가입자 탭 로드 시 이 RPC를 직접 호출한다.
