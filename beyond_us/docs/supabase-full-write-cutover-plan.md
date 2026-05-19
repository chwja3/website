# Supabase 전체 쓰기 전환 Plan

## 목표

남은 사용자 앱 사진 업로드, H&P, admin 운영 쓰기를 Supabase 우선 경로로 전환한다.

## 접근

- 사용자 앱은 기존처럼 `?supabaseData=1`에서 Supabase를 먼저 호출하고 실패 시 GAS로 fallback한다.
- 사진은 Supabase Storage에 저장하고 DB에는 storage path만 남긴다.
- H&P는 Supabase `hold_pray_entries`, `hold_pray_guesses`, `hold_pray_hints`를 기준으로 읽고 쓴다.
- admin은 Supabase Auth 토큰의 `profiles.role`이 `admin` 또는 `dev`일 때만 Supabase RPC를 사용하고, 토큰이 없거나 권한이 없으면 GAS fallback을 유지한다.

## 주의

이번 전환은 DEV 검증 전 단계라 GAS fallback을 제거하지 않는다. PROD에서 fallback 제거는 모든 사용자 흐름 확인 후 별도 작업으로 한다.
