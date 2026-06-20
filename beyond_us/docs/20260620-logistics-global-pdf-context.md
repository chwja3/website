# 숙소 배정 전체 PDF 게시 준비 컨텍스트

## 결정

- 사용자가 나중에 제공할 PDF는 Supabase Storage public bucket `beyond-us-photos` 아래 `logistics/lodging_assignment.pdf`로 올리는 것을 기준으로 한다.
- 모든 유저가 같은 PDF를 보므로 이름 매칭, 닉네임 매칭, 개인별 row 조회는 필수 경로가 아니다.
- PDF가 아직 업로드되지 않은 동안 기존 개인 배정 정보를 fallback으로 유지해 운영 중 빈 화면을 피한다.

## 2026-06-20 이미지 게시 추가

- 사용자가 PDF 대신 숙소 배정 안내 JPG 3장을 제공했다.
- 세 이미지는 모든 유저가 같은 내용을 보는 고정 안내이므로 Supabase 조회 없이 앱 정적 자산으로 포함한다.
- 기존 Supabase PDF 경로와 개인 배정 fallback은 남겨두고, 앱 화면에서는 정적 이미지 묶음을 우선 보여준다.
