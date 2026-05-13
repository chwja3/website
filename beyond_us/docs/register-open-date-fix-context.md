# 신규 가입 후 티저 진입 수정 컨텍스트

## 2026-05-13 판단

- 티저 화면은 `showComingSoon()`이 호출될 때만 보인다.
- 로그인 성공 경로는 서버 응답의 `appOpenDate`를 저장하고 그 값으로 `shouldEnterApp()`을 판단한다.
- 반면 신규 가입 성공 경로는 `registerUser()` 응답에 `appOpenDate`가 없어서 localStorage의 기존 값을 읽고 있었다.
- 새 사용자는 localStorage에 `beyondus_app_open_date`가 없을 수 있으므로 `shouldEnterApp(false, '')`가 되어 티저 화면으로 잘못 이동할 수 있다.

## 수정 방향

- 회원가입 응답을 로그인 응답과 비슷하게 맞춘다.
- 신규 가입 직후 앱 진입 판단은 방금 받은 서버 `appOpenDate`를 사용한다.

## 구현 메모

- `registerUser()`는 이제 `parish`, `isStaff`, `isDev`, `appOpenDate`, `sessionToken`을 반환한다.
- 프론트는 회원가입 성공 직후 `data.appOpenDate`를 `localStorage`에 저장하고, `shouldEnterApp(isStaff, appOpenDate)`로 진입 화면을 결정한다.
- 배포 캐시 갱신을 위해 프론트 버전은 `20260513r`로 올렸다.
