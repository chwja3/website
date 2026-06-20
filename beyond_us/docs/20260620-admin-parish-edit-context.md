# 앱 가입자 교구 수정 컨텍스트

## 결정

- 교구 수정은 `profiles.parish`만 변경한다.
- 추첨권 제외 정책은 이미 별도 체크박스로 관리하므로 교구 변경 시 자동으로 바꾸지 않는다.
- 기존 목록 정렬은 교구와 이름순이라 저장 후 목록을 다시 불러와 정렬과 통계가 자연스럽게 맞게 한다.
- 운영 로그 추적을 위해 교구 변경 시 `admin.profile.parish_updated` 이벤트를 남긴다.
- SQL 마이그레이션 파일은 `beyond_us/supabase/migrations/20260620000300_admin_profile_parish_update.sql`이다.
