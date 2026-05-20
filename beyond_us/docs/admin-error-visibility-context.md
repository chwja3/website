# Admin 서버 오류 메시지 표시 컨텍스트

## 결정

- “서버 연결 오류”만 보이는 문제는 관리자 운영 중 원인 파악을 늦춘다. 관리자 화면에서는 Supabase/PostgREST의 실제 `error`, `message`, `code`, `details`, `hint`, HTTP status를 함께 보여준다.
- 사용자 앱에는 내부 오류 원문을 전부 노출하지 않는다. 이번 변경은 admin 화면 중심으로 제한한다.
- H&P 유저 현황은 `admin_hold_pray_status` RPC를 사용한다. 이 RPC는 `bu_hold_pray_cards_for_profile`, `bu_korean_initials`, `profiles.name_initials`에 의존하므로, 일부 프로젝트에 누락되어도 최신 SQL 한 번으로 보강되도록 한다.

## 이유

H&P 기도 매칭 저장 오류처럼 DB 함수 누락, schema cache, 권한 문제는 화면에서 실제 오류가 보여야 바로 해결할 수 있다. 운영자는 admin 페이지를 통해 상태를 점검하므로, admin 쪽에는 디버깅 가능한 오류 메시지를 남기는 편이 안전하다.
