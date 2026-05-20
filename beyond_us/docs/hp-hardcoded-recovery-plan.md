# H&P 하드코딩 기도제목 복구 계획

## 목적

예전 GAS 코드의 `HOLD_PRAY_ENTRIES` 배열에 있던 H&P 기도제목과 작성자 정보가 Supabase 이관 과정에서 일부 누락되거나 작성자 매칭 없이 들어간 것으로 보인다. 이 배열을 원천 스냅샷으로 삼아 현재 Supabase `hold_pray_entries`를 보강한다.

## 접근

1. `beyond_us/Apps_Script`의 `HOLD_PRAY_ENTRIES` 배열을 파싱한다.
2. 하드코딩 원본의 `content`를 정규화한 키로 현재 `hold_pray_entries.content`와 매칭한다.
3. 기존 행이 있으면 `profile_id`, `owner_name_input`, `anonymous`, `visible`을 보강한다.
4. 기존 행이 없으면 누락된 기도제목으로 새 `hold_pray_entries` 행을 추가한다.
5. 작성자 매칭은 `nick`이 있으면 `profiles.login_id`를 우선하고, 없으면 실명 기준으로 활성 유저가 정확히 1명일 때만 연결한다.
6. 동명이인, 미가입자, 익명 행은 `profile_id`를 비워 두고 관리자 매칭 화면에서 후속 처리할 수 있게 `owner_name_input`만 남긴다.
7. 기존 H&P 정답 기록이 새 작성자 매칭을 반영하도록 `bu_recalculate_hold_pray_guesses(null)`를 실행한다.

## 성공 기준

- SQL 실행 결과에서 원본 116건이 로드된다.
- 기도본문 중복이 없어 본문 기준 업데이트가 모호하지 않다.
- 기존 행은 중복 삽입 없이 보강된다.
- 누락된 본문만 새로 삽입된다.
- 매칭 실패 또는 동명이인 후보는 결과 JSON에 표시되어 수동 확인할 수 있다.
