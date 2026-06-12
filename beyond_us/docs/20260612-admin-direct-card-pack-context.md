# 2026-06-12 관리자 카드 뽑기권 직접 지급 컨텍스트

## 대체됨

- 이후 요청으로 앱 가입자 탭의 직접 지급 버튼은 카드 뽑기권이 아니라 추첨권을 지급하도록 바뀌었다.
- admin UI는 더 이상 `admin_grant_card_pack_ticket`을 호출하지 않는다.
- 현재 직접 지급 기능은 `20260612000500_admin_direct_raffle_ticket_grant.sql`의 `admin_grant_raffle_ticket`을 사용한다.

## 배경

- 워십팀과 운영팀에서 이번 주 허브존 이벤트 룰렛 등에 카드 뽑기권을 직접 넣어줄 수 있는 운영 도구를 요청했다.
- 기존 누락 보상 도구는 특정 주차 미션이나 H&P 보상 항목을 기준으로 설계되어 있다.
- 이번 요청은 특정 보상 조건과 무관하게 운영자 판단으로 카드 뽑기권 1장을 추가하는 기능이다.

## 결정

- 앱 가입자 탭의 기존 검색 기능을 그대로 사용한다.
- 각 유저 행에 `뽑기권 +1` 버튼을 추가한다.
- 서버에서는 `user_inventory.normal_pack_earned`와 `normal_pack_remaining`을 각각 1 증가시킨다.
- `events`에는 `ticket.granted` 이벤트를 `ref_type = admin_manual`로 남긴다.

## 구현 메모

- 새 RPC는 `admin_grant_card_pack_ticket(p_login_id, p_reason)`이다.
- 운영자 확인은 기존 `bu_admin_profile()`을 사용한다.
- 이벤트 payload에는 `reason = admin_manual_card_pack`, `reasonText`, `adminManual = true`를 남긴다.
- 지급 후 앱 가입자 목록을 다시 불러오고, 누락 보상 카드가 열려 있으면 해당 유저 보상 현황도 다시 불러온다.

## 검증

- `admin.html` inline script를 `new Function()`으로 문법 확인했다.
- `git diff --check` 통과.
- 충돌 마커 검색 결과 없음.
