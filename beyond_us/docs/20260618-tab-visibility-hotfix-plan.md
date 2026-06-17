# 2026-06-18 탭 표시 누락 핫픽스 계획

## 목표

main 환경에서 일부 사용자에게 `목사님께 무물`과 `별빛 우편함` 탭이 보이지 않는 문제를 줄인다.

## 접근

1. Supabase `bu_tab_settings_json()`이 `counseling`, `visibleRadio`, `visible_radio` 값을 항상 내려주도록 보강한다.
2. 사용자 앱은 top-level boolean뿐 아니라 `tabSettings.items` 배열의 `key`와 `apiKey`도 함께 읽어 탭 표시 여부를 판단한다.
3. `app.js` 버전과 service worker cache 이름을 올려 오래된 앱 파일을 들고 있는 기기가 새 코드를 받게 한다.

## 검증

- `node --check beyond_us/app.js`.
- 충돌 마커 검색.
- `git diff --check`.
