# Q.T. Storage 전환과 BBB 사진 경로 정리 계획

## 목표

Q.T. 날짜별 이미지는 Supabase Storage의 `QT/` 폴더를 기준으로 제공하고, BBB/천로역정 인증 사진은 `BBB_missions/` 하위에 유저별로 정리한다.

## 설계

- Storage bucket은 기존 public bucket `beyond-us-photos`를 사용한다.
- Q.T. 이미지는 `beyond-us-photos/QT/YYMMDD.png`에 업로드한다.
- 앱은 Q.T. 이미지를 Supabase Storage public URL에서 먼저 로드한다.
- Storage에 아직 파일이 없을 때는 DEV 확인과 복구를 위해 로컬 `QT/YYMMDD.png`를 fallback으로 둔다.
- 새 BBB/천로역정 업로드 경로는 `BBB_missions/{닉네임}/{missionType}/{timestamp}_{random}.{ext}`로 둔다.
- 기존에 DB에 저장된 옛 사진 경로는 그대로 public URL 변환이 되므로 읽기 호환성을 유지한다.

## 검증

- `node --check beyond_us/app.js`.
- `node --check beyond_us/tools/upload_qt_storage.mjs`.
- `git diff --check`.
- 오늘 날짜 Q.T. Storage URL 계산 확인.
- BBB 업로드 경로 prefix 계산 확인.
