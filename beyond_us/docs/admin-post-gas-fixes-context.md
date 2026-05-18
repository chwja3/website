# Admin post-GAS fixes 컨텍스트

2026-05-18. GAS 제거 후 admin 운영 확인 중 세 가지 문제가 보고됐다. 추첨권 번호 탭에서 회수된 번호 목록이 끝까지 보이지 않고, 유저 비밀번호 초기화 목록 정렬이 앱 가입자 탭과 맞지 않으며, 시스템 상태의 audit 체크가 `admin_admin_audit_user_state_failed`로 실패한다.

2026-05-18. 이번 작업은 admin 화면과 필요한 Supabase RPC 보강만 다룬다. 앱 사용자 화면 동작은 건드리지 않는다.

2026-05-18. 추첨권 번호 탭은 기존 `adminDispatch.adminGetRaffleTickets`의 `filteredTotal`과 `hasMore`가 페이지네이션을 반영하지 못해 뒤쪽 번호로 이어지는 UI가 막힐 수 있었다. 전용 RPC `admin_get_raffle_tickets`를 추가해 전체 개수, 반환 개수, 더 보기 여부를 분리했다.

2026-05-18. 상단 회수된 번호 칩은 24개까지만 보여주던 제한을 제거하고, 카드 폭 전체와 내부 스크롤을 사용하게 했다. 번호가 많아도 화면 밖으로 잘리지 않게 하는 목적이다.

2026-05-18. 시스템 상태 audit은 실제 불일치가 있을 때 `ok:false`를 정상 결과로 반환한다. 기존 admin RPC wrapper가 이를 예외로 처리해서 `admin_admin_audit_user_state_failed`처럼 보였으므로, 상태 점검에서는 `ok:false` 응답을 결과로 받아 mismatch 정보를 표시하게 했다.
