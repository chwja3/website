# 사진첩 업로드 400 오류 수정 컨텍스트

## 결정

- 사진첩에서 선택한 사진은 기기와 브라우저에 따라 파일 메타데이터가 다양하므로, Storage 경로 안정성을 우선한다.
- 기존 `BBB_missions/{닉네임}/{missionType}/...` 경로는 한글, 공백, 특수문자, 이모지가 섞일 수 있어 `BBB_missions/user_{hash}/{missionType}/...` 형태로 바꾼다.
- 표시와 승인 로직은 DB의 `mission_photo_submissions.storage_path`를 기준으로 동작하므로, Storage 폴더명이 닉네임이 아니어도 사용자 기능에는 영향이 없다.
