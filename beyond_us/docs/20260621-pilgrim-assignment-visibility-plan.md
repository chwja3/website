# 2026-06-21 천로역정 랜덤 2스팟 표시 보강 계획

## 목표

천로역정 탭을 여는 모든 활성 유저가 `pilgrim_assignments`가 없더라도 서버 조회 시 랜덤 장소 2군데를 즉시 배정받고, 앱에서 붉은 원 2개를 볼 수 있게 한다.

## 성공 기준

1. `bu_photo_payload()`가 `pilgrim_assignments`를 단순 조회하지 않고 `bu_ensure_pilgrim_assignment()`로 배정을 보장한다.
2. 기존 배정이 있는 유저는 기존 장소를 유지한다.
3. 기존 배정이 없는 활성 유저는 SQL 실행 시점 또는 첫 조회 시 랜덤 2스팟을 받는다.
4. 앱의 `m3AssignedSpots`는 정상적으로 2개 배열로 내려갈 수 있다.
5. `pilgrim` 탭과 `bbb_settings.m3`가 모두 open 상태가 되어 앱이 실제 천로역정 화면을 렌더링한다.
6. 천로역정 탭은 B.B.B. 매칭 상태가 아니라 전용 `get_pilgrim_status` 응답으로 붉은 원을 렌더링한다.
