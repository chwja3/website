# Case Variant User Data Plan

## 목표

대소문자만 다른 닉네임이 Users 시트에 동시에 있을 때 inactive 행의 Collection, RaffleTickets 데이터가 active 행에 섞이지 않게 한다.

## 구현 방향

1. Users 조회는 정확히 같은 닉네임을 먼저 찾고, 정확한 행이 없을 때만 대소문자 보정으로 active 유저를 찾는다.
2. Collection과 RaffleTickets처럼 유저 소유 데이터는 Users에 정확한 닉네임 행이 존재하면 대소문자 다른 행과 섞지 않는다.
3. Users에 없는 단순 대소문자 흔들림은 기존처럼 active 유저로 보정해 예전 이벤트 데이터를 살린다.
4. 기존 시트 데이터를 정리할 수 있도록 dry run/apply 점검 함수를 추가한다.

## 검증 기준

- `Oh! New`가 inactive이고 `oh! New`가 active이면 `Oh! New`의 추첨권과 Collection은 `oh! New`에 합산되지 않는다.
- `oh! New`는 자기 정확한 행과, Users에 정확한 행이 없는 단순 케이스 흔들림 데이터만 사용한다.
- repair dry run은 release, rename, duplicate 처리 예정 행을 보여준다.
