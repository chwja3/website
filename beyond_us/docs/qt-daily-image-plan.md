# Q.T. 날짜별 이미지 게시 계획

## 목표

`beyond_us/QT` 폴더에 올린 날짜별 PNG 파일을 Q.T. 말씀 묵상 탭에서 오늘 날짜 기준으로 자동 표시한다.

## 설계

- 파일명은 `YYMMDD.png` 규칙을 사용한다.
- 앱은 한국 시간 기준 오늘 날짜를 계산해 Supabase Storage `QT/YYMMDD.png`를 이미지로 표시한다.
- 이미지가 없거나 로딩에 실패하면 빈 화면이 아니라 오늘 날짜 안내와 준비되지 않았다는 메시지를 보여준다.
- Q.T. 본문은 정적 이미지로만 표시하고, 제출이나 메모 저장은 이번 범위에 포함하지 않는다.
- 폴더 목록은 브라우저에서 읽을 수 없으므로 별도 manifest 없이 날짜 기반 경로 계산으로 처리한다.
- Storage 이미지가 아직 업로드되지 않은 환경에서는 로컬 `QT/` 파일을 fallback으로 사용한다.

## 검증

- `node --check beyond_us/app.js`.
- `git diff --check`.
- `APP_VERSION`, `version.txt`, `app.html`의 `app.js` 버전 파라미터 동기화 확인.
