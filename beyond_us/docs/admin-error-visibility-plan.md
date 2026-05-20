# Admin 서버 오류 메시지 표시 계획

## 목표

관리자 화면에서 “서버 연결 오류”만 보이고 실제 Supabase RPC 오류가 숨겨지는 문제를 줄인다. 특히 H&P 유저 현황은 필요한 helper 함수와 초성 필드가 누락되어도 다시 보강될 수 있도록 SQL을 추가한다.

## 범위

1. `admin_hold_pray_status` RPC가 의존하는 H&P helper, 초성 helper, `profiles.name_initials` 필드를 보강한다.
2. 관리자 화면의 서버 연결 실패 catch에서 `adminErrorMessage(e)`를 함께 보여준다.
3. 기존 사용자 앱에는 내부 DB 오류를 과도하게 노출하지 않고, 이번 변경은 관리자 화면 중심으로 적용한다.

## 검증

1. SQL 파일 문법과 변경 범위를 리뷰한다.
2. `admin.html` 스크립트 파싱 검증을 실행한다.
3. `git diff --check`와 staged diff check를 실행한다.
