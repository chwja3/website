# BBB 사진 없는 수동 승인 컨텍스트

- Mission 1, Mission 2 사진 업로드가 실패하면 `mission_photo_submissions` row가 없어 기존 승인 버튼이 뜰 대상이 없었다.
- 운영에 필요한 것은 사진 저장 여부가 아니라 Mission 1, Mission 2 성공 처리와 그에 따른 카드팩 보상 지급이다.
- 사진 없는 승인은 `mission_photo_submissions.storage_path`에 `admin_manual://...` 내부 marker를 넣어 기록한다.
- `bu_photo_payload()`는 `admin_manual://...` marker를 사용자 앱의 사진 URL로 내려보내지 않는다.
- 사용자 앱도 방어적으로 `admin_manual://...` 값을 빈 문자열로 처리한다.
- 보상 지급은 기존 `bu_issue_special_pack_for_photo()`를 그대로 사용한다. 이 함수 쪽의 중복 지급 방지 흐름을 재사용하기 위해 별도 보상 로직을 만들지 않았다.
- 천로역정 Mission 3는 여전히 사진 제출 또는 인증 기록이 있어야 승인된다. 이번 변경은 BBB Mission 1, Mission 2에만 적용한다.
