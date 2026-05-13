# 특별 카드팩 Context

## 결정된 내용

- 여기서 말하는 현장 미션은 BBB MISSION 1, 2, 3을 뜻한다.
- BBB MISSION 1, 2, 3이 성공하면 각각 특별 카드팩을 1장씩 자동 지급한다.
- 이 방식이면 별도 admin 수동 지급 화면은 초기 필수 기능이 아니다.
- 특별 카드팩은 일반 카드팩과 별도 계수로 관리한다.
- 특별 카드팩 후보는 일반 카드 9종만 포함한다.
- 특별 카드팩은 미보유 일반 카드가 있으면 미보유 카드 확정으로 동작하고, 9종을 모두 보유한 경우에는 일반 카드팩처럼 1-9번 중 랜덤으로 동작한다.
- 히든 카드와 레어카드는 특별 카드팩 후보에서 무조건 제외한다.
- 사용자 앱에서는 특별 카드팩이라는 표현을 노출하지 않고 모두 “카드팩”으로 표시한다.
- 사용자 앱 카드팩 버튼은 하나만 둔다.
- 사용자 앱 배지는 `🎫`에 전체 사용 가능 카드팩 수를, `💜`에 그중 특별 카드팩 수를 표시한다.
- 일반 카드팩 잔여 수가 있으면 항상 일반 카드팩을 먼저 사용하고, 일반 카드팩이 없을 때만 특별 카드팩을 사용한다.
- admin 탭 활성화에서 특별 카드팩 토글을 켰을 때만 특별 카드팩 잔여 수를 사용자 카드팩 총량에 합산한다.
- 토글이 꺼져 있으면 기존 일반 카드팩 화면 그대로 유지한다.

## GAS 반영 내용

- `TabSettings` 기본 행에 `specialPack`을 추가했다.
- `getTabSettings()` 응답에 `specialPack` boolean을 추가했다.
- `setTabSettings()`에서 `specialPack` 저장을 처리한다.
- `userStatus` 응답에 `pendingSpecialPacks`를 추가했다.
- `drawSpecialCard` POST 액션을 추가했다.
- 프론트엔드는 단일 카드팩 버튼에서 일반 카드팩 우선순위에 따라 `drawCard` 또는 `drawSpecialCard`를 자동 선택한다.
- `drawSpecialCard`는 Lock 내부에서 Events 전체 projection을 다시 계산하고, 일반 카드 9종 중 미보유 카드가 있으면 미보유 카드만 후보로 삼는다.
- 미보유 일반 카드가 없으면 일반 카드팩과 같은 1-9번 랜덤 후보로 fallback 한다.
- 성공 시 `special_pack.consumed`와 `card.drawn` 이벤트를 함께 기록하고, Collection row를 재계산한다.
- UserDashboard 끝에 특별팩 획득·사용·잔여 수 컬럼을 추가했다.
- BBB MISSION 1, 2 승인 보상은 일반 `ticket.granted`가 아니라 `special_pack.granted`로 기록한다.
- BBB MISSION 3은 7곳 사진이 모두 채워진 시점에 `special_pack.granted`를 1회 기록한다.
- 기존 BBB 보상으로 남아 있는 `ticket.granted` 이벤트는 중복 지급 방지와 보안 감사에서 계속 인식한다.

## 확정 정책

- 모든 일반 카드를 보유한 유저의 특별 카드팩은 일반 카드팩처럼 1-9번 일반 카드 중 랜덤 지급한다.
