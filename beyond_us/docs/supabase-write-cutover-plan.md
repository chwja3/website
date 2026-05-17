# Supabase 쓰기 전환 Plan

## 목표

DEV 사용자 앱의 남은 주요 쓰기 경로를 Supabase RPC 우선, GAS fallback 구조로 옮긴다.

## 범위

- Supabase 테이블만으로 상태가 닫히는 사용자 앱 쓰기를 우선 전환한다.
- 카드팩 개봉, 교환, 개발자 문의, BBB 메시지, 시크릿버디 추측을 한 묶음으로 처리한다.
- 각 쓰기와 맞물리는 읽기 경로도 함께 Supabase 우선으로 전환한다.

## 제외

- BBB, 천로역정 사진 업로드와 삭제는 Storage bucket 정책이 확정된 뒤 전환한다.
- H&P는 `getHoldPray` 읽기 설계와 카드 선택 규칙을 먼저 Supabase로 고정한 뒤 전환한다.
- admin 쓰기는 admin Auth와 role 기반 권한 RPC가 준비된 뒤 전환한다.
