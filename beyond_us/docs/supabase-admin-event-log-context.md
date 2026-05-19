# Supabase Admin Event 로그 탭 컨텍스트

2026-05-18. 운영자는 Supabase Table Editor에서 `ops_events` view를 볼 수 있지만, admin 화면 안에서도 전체 이벤트 로그를 확인할 개발자용 탭이 필요하다. 이 기능은 이벤트를 수정하지 않고 조회만 하므로 기존 `Events·시스템`의 카드 수동 지급, 파생 상태 재계산과 분리한다.

2026-05-18. 조회는 `admin_dispatch` action을 추가하지 않고 독립 RPC `admin_event_logs`로 둔다. 이미 admin 페이지가 `callSupabaseAdminRpc()`로 직접 RPC를 호출하는 패턴을 쓰고 있고, 이벤트 로그는 명확한 읽기 전용 기능이라 독립 함수가 관리하기 쉽다.
