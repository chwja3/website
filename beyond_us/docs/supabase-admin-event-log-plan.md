# Supabase Admin Event 로그 탭 계획

개발자가 admin에서 Supabase `events` 로그를 바로 확인할 수 있도록 조회 전용 탭을 추가한다.

1. `admin_event_logs` RPC를 추가해 staff 권한 확인 후 최신 이벤트 로그를 반환한다.
2. 로그에는 이벤트 시각, 유저 닉네임, 이름, 교구, 이벤트 타입, ref, amount, source, payload를 포함한다.
3. admin 개발자 메뉴에 `Event 로그` 탭을 추가한다.
4. 탭에서는 최신순 조회, 이벤트 타입 필터, 닉네임/이름/참조 검색, 표시 개수 제한을 제공한다.

성공 기준.

- staff 계정만 `admin_event_logs`를 호출할 수 있다.
- admin에서 `Event 로그` 탭을 열면 최신 이벤트가 위에 보인다.
- 이벤트 타입과 검색어로 로그를 좁혀 볼 수 있다.
