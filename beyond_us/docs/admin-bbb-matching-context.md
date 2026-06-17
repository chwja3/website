# Admin BBB Matching Context Notes

## 2026-06-16

- `bbb_assignments` 테이블은 이미 `profile_id`, `care_buddy_id`, `secret_buddy_id`, `group_id`, `tier`를 가지고 있다.
- `admin_bbb_pilgrim_status`는 이미 `bbb_assignments`를 읽어서 운영 현황에 케어버디와 시크릿버디를 표시한다.
- 기존 admin `B.B.B. 미션` 탭의 `runBBBMatching()`은 랜덤 매칭 중지 안내만 보여주고 실제 저장 기능이 없다.
- 일관성을 위해 관리자가 직접 `secret_buddy_id`를 따로 고르는 방식은 피한다. 한 사람의 케어버디를 저장하면 상대방의 시크릿버디가 자동으로 맞춰지게 한다.
- `admin_get_bbb_matching_matrix()`는 active 유저를 조별로 정렬해 반환한다. 조가 없으면 `조 미배정` 그룹에 둔다.
- `admin_set_bbb_care_buddy()`는 한 유저의 케어버디를 저장하며, 기존 연결과 중복 연결을 자동으로 해제해서 `care_buddy_id`와 `secret_buddy_id`가 서로 어긋나지 않게 한다.
- admin UI는 `B.B.B. 미션` 탭의 매칭 카드에서 조 필터, 검색, 유저별 저장 버튼을 제공한다. 저장 후에는 `BBB/천로역정` 운영 현황도 같이 새로고침한다.

## 2026-06-17

- 케어버디와 시크릿버디는 운영자와 유저 화면에서 닉네임보다 실제 이름 기준으로 다룬다.
- 시크릿버디 정답 판정은 `profiles.name`만 인정한다. `login_id`나 `display_name`은 더 이상 정답으로 인정하지 않는다.
- admin 매칭 UI의 후보 표시와 검색도 이름, 교구, 조 중심으로 맞춘다. 내부 저장 키는 계속 `profile_id`를 사용한다.
