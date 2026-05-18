# Supabase 운영 가독성 정리 계획

Supabase Table Editor에서 운영자가 `id`, `profile_id`만 보고 판단하지 않도록, 원본 정규화 테이블은 유지하고 읽기 전용 운영 view를 추가한다.

1. `ops_*` view를 추가해 유저가 연결된 행마다 `login_id`, `display_name`, `name`, `parish`를 같이 보여준다.
2. 시간 컬럼이 있는 view는 최신 행이 위에 오도록 `ORDER BY ... DESC`를 둔다.
3. admin의 개발자 메뉴에서 `Events 관리`와 `시스템 상태`를 통합하고, Supabase 운영에서 의미가 없어진 Sheet 전환 도구를 제거한다.
4. 프론트 캐시 버전을 동기화하고 문서, 문법 검사를 끝낸 뒤 커밋한다.

성공 기준.

- Supabase SQL Editor에서 새 migration을 실행하면 `ops_events`, `ops_raffle_tickets`, `ops_mission_submissions` 등 운영용 view가 생성된다.
- admin 메뉴에는 별도 `시스템 상태` 항목이 사라지고, `Events 관리` 안에서 상태 확인과 파생 상태 재계산을 같이 할 수 있다.
- `cutoverDashboardRows`, `runProdCutoverDryRun`, `runProdCutoverApply` 참조가 admin에서 사라진다.
