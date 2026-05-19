# H&P 관리자 작성과 응답 초기화 컨텍스트

2026-05-19. H&P 카드 선택 기준이 바뀌면서 기존 `hold_pray_guesses`의 `card_index`가 새 랜덤 3장 기준과 섞일 수 있다. 이 경우 이전 응답이 새 카드 위치에 붙어 정답이 제대로 반영되지 않을 수 있으므로, 기도제목 원본인 `hold_pray_entries`는 유지하고 응답 기록인 `hold_pray_guesses`와 힌트 기록인 `hold_pray_hints`만 초기화한다.

2026-05-19. 운영자가 H&P 미작성자의 기도제목을 대신 입력할 수 있어야 한다. 이를 위해 `admin_upsert_hold_pray_entry` RPC를 추가하고, 관리자 `H&P 현황` 탭에서 미작성자에게 textarea와 작성 버튼을 보여준다. 기존 작성자가 있는 경우에는 중복 row를 만들지 않고 최신 row를 갱신하는 형태로 방어한다.

2026-05-19. 관리자 페이지는 Supabase access/refresh token을 localStorage에 저장하지만, admin 권한 힌트는 sessionStorage 위주라 강력 새로고침 또는 탭 상태 변화 후 로그인 gate로 돌아갈 수 있다. admin 권한 힌트를 localStorage에도 보존하고, 페이지 로드 시 저장된 token으로 권한 확인 후 admin panel을 자동 복원하도록 한다.
