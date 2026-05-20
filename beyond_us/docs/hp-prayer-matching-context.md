# H&P 기도제목 작성자 매칭 컨텍스트

## 결정

- 매칭 대상은 `hold_pray_entries.profile_id`가 비어 있는 H&P 기도제목이다.
- 관리자가 입력한 이름은 `hold_pray_entries.owner_name_input`에 저장한다.
- 입력 이름이 활성 유저의 `profiles.name`과 정확히 1명 매칭될 때만 `profile_id`를 연결한다.
- 유저를 못 찾거나 동명이인이 있으면 `profile_id`는 비워두고 입력 이름만 남긴다.
- 매칭을 저장하거나 해제하면 H&P 정답 여부를 다시 계산한다.
- 기도제목 작성자 매칭은 주차별 통계가 아니라 기도제목 행 자체의 작성자 연결이므로 전체 엔트리 기준으로 본다.

## 이유

H&P 정답 판정은 실명 기준으로 고정되어 있다. 따라서 기도제목도 작성자 프로필과 연결되어 있어야 사용자별 랜덤 3장, 본인 제외, 정답 판정, 운영 현황이 같은 기준으로 동작한다.

## 후속 보강

- 새 RPC가 Supabase PostgREST schema cache에 바로 보이지 않을 수 있어 `notify pgrst, 'reload schema'` hotfix를 추가했다.
- Admin 화면의 H&P 기도 매칭 로딩 실패 메시지는 실제 RPC 오류 코드를 같이 보여주도록 변경했다.
- dev 호스트가 PROD Supabase를 바라보면 DEV에 실행한 RPC가 없다고 나올 수 있어, 앱과 admin 모두 `dev.website-78h.pages.dev`에서는 DEV Supabase, 그 외 운영 호스트에서는 PROD Supabase를 보도록 분기했다.
- H&P 기도 매칭 탭의 주차 입력은 제거하고 전체 기도제목을 대상으로 조회하게 바꿨다.
