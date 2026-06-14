# 2026-06-14 탭 숨김과 등록 실패 보강 컨텍스트

## 현재 확인한 사실

- 앱 드로어의 광범위수사는 `data-section="investigation"`으로 존재하고, `tabSettings.investigation`이 true일 때만 보인다.
- 기존 광범위수사 초기 마이그레이션은 `tab_settings`에 `enabled=true`, `status=open`으로 넣고 있어서 새 환경이나 SQL 재실행 시 다시 노출될 수 있다.
- 햄버거 메뉴의 닫힘 날짜 배지는 `COMING_SOON_DATES`에서 읽는데, 현재 광범위수사 key가 빠져 있다.
- 앱의 목사님께 무물 등록 호출은 `create_counseling_entry(p_login_id, p_content, p_public_visible)`이다.
- 앱의 별빛 우편함 등록 호출은 `create_visible_radio_story(p_login_id, p_category_key, p_target_text, p_content, p_is_anonymous)`이다.

## 결정

- 광범위수사는 지금 설명을 다시 손볼 예정이므로 숨김 상태를 DB 기본값으로 잡는다.
- 별빛 우편함과 무물은 최신 함수가 이미 있어도 운영 DB에서 일부 SQL이 빠졌을 때를 대비해 hotfix SQL에서 함수 시그니처를 다시 정의한다.

## 구현 메모

- 앱의 햄버거 날짜 배지 매핑에 `investigation: '6/20'`을 추가했다.
- `20260614000300_hide_investigation_submission_hotfix.sql`은 광범위수사를 숨김으로 바꾸고, 무물/별빛 우편함 사용자 등록 RPC를 현재 앱 호출 인자명에 맞게 다시 정의한다.
