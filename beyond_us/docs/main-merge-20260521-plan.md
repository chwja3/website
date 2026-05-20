# 2026-05-21 main 반영 계획

## 목표

DEV에 추가된 Q.T. 날짜별 이미지 표시, Q.T. Storage 우선 로딩, BBB 사진 Storage 경로 정리, 천로역정 2스팟 조회 보강을 main에 반영한다.

## 범위

- Q.T. 말씀 묵상 탭은 Supabase Storage `beyond-us-photos/QT/YYMMDD.png`를 우선 로드한다.
- Q.T. Storage 파일이 없으면 로컬 `QT/YYMMDD.png`로 fallback한다.
- 새 BBB/천로역정 사진은 `BBB_missions/{닉네임}/{missionType}/...` 경로로 업로드한다.
- 천로역정 상태 조회 시 유저별 2스팟 배정이 없으면 자동 생성한다.
- 관리자 `BBB/천로역정` 탭 RPC를 복구하고 schema cache reload를 요청한다.

## main 적용 전 수동 작업

- PROD Supabase Storage bucket `beyond-us-photos` 아래 `QT` 폴더에 날짜별 PNG를 업로드한다.
- PROD Supabase SQL Editor에서 통합 SQL `prod_20260521_pilgrim_qt_combined.sql`을 실행한다.

## 검증

- `node --check beyond_us/app.js`.
- `node --check beyond_us/tools/upload_qt_storage.mjs`.
- `git diff --check`.
- `APP_VERSION`, `version.txt`, `app.html` 버전 문자열 동기화 확인.
