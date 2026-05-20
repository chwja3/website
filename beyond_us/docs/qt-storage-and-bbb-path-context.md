# Q.T. Storage 전환과 BBB 사진 경로 정리 컨텍스트

## 2026-05-21 요청

사용자가 Q.T. 날짜별 PNG를 repo 안에서 직접 제공하는 것보다 Supabase Storage의 `QT` 폴더에 두고 앱에서 Storage 이미지를 보여주는 편이 안정적이지 않겠냐고 제안했다. 또한 Storage에서 BBB Mission 1, 2, 3 사진이 바로 유저 닉네임 폴더로 생기는 현재 구조를 `BBB_missions` 폴더 하위의 유저별 폴더로 정리하길 원했다.

## 결정

- Q.T. 이미지는 기존 bucket `beyond-us-photos` 아래 `QT/` prefix에 둔다.
- 별도 bucket을 만들지 않는 이유는 이미 앱과 admin이 `beyond-us-photos` public URL 변환 로직을 공유하고 있고, Storage 정책도 해당 bucket 기준으로 잡혀 있기 때문이다.
- 앱은 Storage URL을 우선 사용한다. 단, DEV와 업로드 전 검증을 위해 로컬 `QT/` 이미지를 fallback으로 남긴다.
- Q.T. 이미지 업로드는 코드에서 자동 수행하지 않고, 로컬 업로드 스크립트를 제공한다. 이 스크립트는 DEV와 PROD 각각의 Supabase URL과 service role key를 환경변수로 받아 실행한다.
- BBB/천로역정 사진은 새 업로드부터 `BBB_missions/{닉네임}/{missionType}/...`에 저장한다.
- 기존 사진 경로는 DB에 남아 있으므로 마이그레이션하지 않아도 계속 표시된다.

## 구현

- 앱 Q.T. 이미지는 `beyond-us-photos/QT/YYMMDD.png` public URL을 먼저 로드한다.
- Storage 이미지 로딩이 실패하면 로컬 `QT/YYMMDD.png`로 한 번 fallback한다.
- 새 BBB/천로역정 사진 업로드 path는 `BBB_missions/{닉네임}/{missionType}/{timestamp}_{random}.{ext}`로 바뀌었다.
- 기존 path 정규화가 한글 닉네임을 전부 제거하던 문제를 줄이기 위해, `/`, URL 예약문자, 제어문자만 `_`로 바꾸고 한글은 유지한다.
- `beyond_us/tools/upload_qt_storage.mjs`를 추가했다.

## 2026-05-21 Q.T. 로딩 멈춤 수정

- 숨겨진 이미지에 `loading="lazy"` 상태로 `src`를 넣으면 브라우저가 실제 요청을 미뤄 `onload`와 `onerror`가 모두 실행되지 않을 수 있었다.
- Q.T. 이미지는 이제 DOM 이미지에 바로 `src`를 넣지 않고, `new Image()`로 Storage URL과 local fallback URL을 먼저 검증한다.
- 성공한 URL만 화면 이미지에 넣고, 둘 다 실패하면 준비되지 않았다는 메시지를 보여준다.
- 프론트 버전은 `20260521c`로 동기화했다.

## Q.T. 업로드 절차

DEV 또는 PROD Supabase 프로젝트별로 아래 환경변수를 설정한 뒤 실행한다.

```powershell
$env:BEYOND_US_SUPABASE_URL="https://프로젝트-ref.supabase.co"
$env:BEYOND_US_SUPABASE_SERVICE_ROLE_KEY="service role key"
node beyond_us/tools/upload_qt_storage.mjs --apply
```

먼저 목록만 확인하려면 `--apply` 없이 실행한다.
