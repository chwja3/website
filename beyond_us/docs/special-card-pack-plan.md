# 특별 카드팩 Plan

## 목표

BBB MISSION 1, 2, 3 보상으로 일반 카드팩과 분리된 특별 카드팩을 지급하고, 특별 카드팩은 개봉 시점 기준 미보유 일반 카드 9종 중 하나만 나오도록 한다.

## 이번 로컬 작업 범위

- 앱 사전미션 카드팩 영역에는 사용자 기준 카드팩 버튼을 하나만 노출한다.
- 사용자 화면에서는 일반/특별 카드팩 구분 표현을 숨기고 모두 “카드팩”으로 표시한다.
- 카드팩 버튼을 누르면 일반 카드팩 잔여 수가 먼저 소비되고, 일반 카드팩이 없을 때만 내부적으로 `drawSpecialCard` 액션을 호출한다.
- 사용 가능한 카드팩 수 표시는 일반 카드팩과 특별 카드팩 잔여 수를 합산한다.
- BBB MISSION 1, 2는 운영진 승인 시 특별 카드팩을 지급한다.
- BBB MISSION 3은 7곳 사진을 모두 채운 시점에 특별 카드팩을 지급한다.

## 서버 계약

- `getTabSettings`와 dashboard 응답의 `tabSettings.specialPack`이 `true`일 때만 특별 카드팩 잔여 수를 사용자 카드팩 총량에 합산한다.
- `userStatus.pendingSpecialPacks`가 특별 카드팩 잔여 수다.
- BBB 미션 보상은 `special_pack.granted` 이벤트로 기록한다.
- 프론트엔드는 `pendingDraws > 0`이면 `drawCard`, `pendingDraws === 0 && pendingSpecialPacks > 0`이면 `drawSpecialCard`를 호출한다.
- `drawSpecialCard`는 개봉 시점의 최신 Collection 기준으로 일반 9종 중 미보유 카드만 후보로 잡는다.
- 미보유 일반 카드가 없으면 특별 카드팩을 소비하지 않고 `no_missing_cards` 또는 사용자용 메시지를 반환한다.

## 보류 정책

- 모든 일반 카드를 보유한 유저의 특별 카드팩 전환 보상은 추후 확정한다.
- 초기 구현에서는 “미보유 카드가 없습니다. 운영진에게 문의하세요.” 메시지만 보여준다.
