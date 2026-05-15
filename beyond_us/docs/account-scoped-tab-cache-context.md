# 계정별 탭 캐시 버그 컨텍스트

2026-05-15. 사용자가 user1로 H&P, B.B.B. 미션, 천로역정 탭에 들어간 뒤 로그아웃하고 user2로 로그인하면 user1 정보가 계속 보인다고 보고했다. 원인은 localStorage는 로그아웃 시 지워지지만 앱 메모리의 `_hpCards`, `_bbbData`, `_bbbLoadedOnce`, 사진 DOM, M3 스팟 DOM이 초기화되지 않는 구조다.

H&P는 `_hpCards.length === 3`이면 계정 확인 전에 즉시 렌더링한다. BBB와 천로역정은 같은 `loadBBB()`를 쓰고, `_bbbLoadedOnce`와 60초 TTL만 보고 반환할 수 있어서 계정 전환 직후 이전 사용자 화면이 남는다. 비동기 요청도 계정 전환 뒤 늦게 돌아오면 현재 DOM에 덮어쓸 위험이 있다.

첫 로딩이 느린 문제는 숨은 탭 데이터를 탭 진입 시점에 처음 가져오는 영향이 크다. 앱 진입 직후 핵심 화면을 먼저 띄운 다음 H&P와 BBB를 조용히 prefetch하면 사용자가 해당 탭을 눌렀을 때 대기 시간이 줄어든다.

2026-05-15. `resetAccountScopedState()`를 추가해 로그아웃과 다른 계정 로그인 시 사용자 상태, 교환 캐시, H&P 상태, BBB와 천로역정 DOM을 초기화한다. H&P는 `_hpLoadedFor`를 추가해 현재 계정과 로드된 계정이 같을 때만 메모리 캐시를 사용하고, 정답과 힌트 localStorage 키도 계정별로 분리했다. BBB는 `_bbbLoadedFor`와 `_bbbLoadingFor`를 추가해 60초 TTL이 다른 계정에 재사용되지 않게 했고, 늦게 돌아온 비동기 응답은 현재 계정이 아니면 DOM에 반영하지 않는다.

2026-05-15. `syncInitialData()`가 끝난 뒤 `scheduleFeaturePreload()`를 호출해 H&P, BBB, 천로역정 지도 이미지를 1.2초 뒤 조용히 예열한다. 이 prefetch는 로그인 사용자가 그대로 유지될 때만 실행된다. 프론트 캐시 버전은 `20260515n`이다.
