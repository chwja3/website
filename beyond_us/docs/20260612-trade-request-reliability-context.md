# 교환 신청 간헐 실패 컨텍스트

## 현재 상태

- 작업 기준 브랜치는 `main`.
- 현재 로컬은 `origin/main`보다 1커밋 앞서 있다.
- 사용자 요청은 main에서 교환 신청이 가끔 안 가는 원인 확인이다.

## 초기 관찰

- 앱의 교환 신청은 `app.js`에서 `apiClient.requestTrade()`를 통해 Supabase RPC `request_trade`를 호출한다.
- 교환 가능 UI는 내 카드와 상대 카드가 각각 2장 이상인 경우를 기준으로 표시한다.
- 서버 쪽 실제 검증은 `request_trade`, `accept_trade` 함수에 나뉘어 있다.

## 원인 판단

- 검색 시점의 상대 컬렉션과 신청 시점의 실제 `user_cards` 사이에 차이가 생기면 `request_trade`가 `not_enough_target_card`를 반환한다.
- 기존 UI는 이 코드를 그대로 보여주거나 연결 오류처럼 보이게 할 수 있어서 사용자는 “신청이 안 갔다”고 느낄 수 있다.
- 수락 단계는 현재 `quantity > 0`만 검사한다. 신청 실패 직접 원인은 아니지만, 여러 교환이 겹치면 중복 카드 교환 정책과 어긋날 수 있다.

## 적용한 보강

- 교환 신청 버튼을 누른 순간 상대 컬렉션을 다시 조회한다.
- 상대가 더 이상 해당 카드를 2장 이상 갖고 있지 않으면 신청 RPC를 호출하지 않고, 최신 카드 목록으로 되돌린다.
- `not_enough_target_card`, `not_enough_requester_card`, `target_not_found`, `unauthorized` 등 주요 실패 코드를 한국어 안내로 바꾼다.
- 인증 불일치 예외가 발생하면 단순 연결 오류 대신 다시 로그인 안내로 보이게 한다.

## 검증

- `node --check beyond_us\app.js` 통과.
- `git diff --check` 통과.
- 충돌 마커 검색 결과 없음.
