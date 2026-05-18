# Supabase Admin 전환 체크리스트

- [x] admin에서 호출 중인 action 목록을 확인한다.
- [x] Supabase `admin_dispatch`가 지원하는 action 목록을 확인한다.
- [x] 공지 이미지가 GAS로 빠지는 원인을 확인한다.
- [x] Supabase 공지 읽기 RPC `get_notices()`를 추가한다.
- [x] admin 공지 이미지 업로드를 Supabase Storage로 전환한다.
- [x] admin 공지 등록, 수정, 삭제를 Supabase 직접 호출로 고정한다.
- [x] 사용자 앱 공지 읽기에 Supabase read 경로를 추가한다.
- [x] 프론트 캐시 버전을 동기화한다.
- [x] admin 로그인 폼에 관리자 ID 입력을 추가하고 비워두면 공용 `admin` 계정을 쓰도록 한다.
- [x] admin 로그인을 Supabase Auth password grant로 전환한다.
- [x] Supabase admin RPC 권한 확인 후에만 admin 화면에 진입한다.
- [ ] DEV Supabase SQL Editor에서 `20260518000700_notice_read_rpc.sql`을 실행한다.
- [ ] admin에서 이미지 포함 공지를 등록하고 `notices`, Storage를 확인한다.
- [ ] 사용자 앱 `?supabaseData=1` 상태에서 새 공지가 보이는지 확인한다.
- [ ] 공용 `admin` ID와 관리자 전용 비밀번호로 로그인되는지 확인한다.
- [ ] 일반 유저 계정으로 admin 로그인이 거부되는지 확인한다.
- [ ] `adminResetPassword`, `adminCreateCardEvent`, `adminRebuildEventDerivedViews` 등 남은 action을 순차 전환한다.
