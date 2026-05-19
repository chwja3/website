# 주차별 교구 전체 요약 컨텍스트

2026-05-20. 사용자가 admin 대시보드의 `주차별 교구 참여 기록`에서 `교회학교/목양교구` 뒤쪽에 전체 참여자, 날짜 합계, 점수도 함께 보고 싶다고 요청했다.

현재 Supabase `admin_dashboard_summary`는 각 주차의 `parishSummaries`를 내려주고, 각 교구 summary에는 `participantCount`, `activeDays`, `totalScore`, `users`가 있다. 따라서 서버 SQL을 바꾸지 않고 admin 프론트에서 선택 주차의 교구 summary를 합산하면 된다.

2026-05-20. `admin.html`의 주차별 교구 참여 렌더링에만 `전체` summary를 삽입했다. `전체`는 각 교구의 참여자 수, 날짜 합계, 점수를 합산하고, 상세 목록에는 해당 주차 전체 참여자를 점수와 날짜 합계 내림차순으로 보여준다. 일반 `교구별 이번 주 참여` 카드에는 영향을 주지 않는다.
