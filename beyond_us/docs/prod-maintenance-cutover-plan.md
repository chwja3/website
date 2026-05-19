# PROD 점검 전환 계획

main/Supabase 전환 작업 동안 일반 계정의 앱과 admin 접근을 막고, 개발자 계정 `SingSangSong`, `카니보어시즌2`만 통과시킨다.

목표.

1. 프로덕션 사용자 앱에서 개발자 외 계정은 점검 안내 화면만 보게 한다.
2. admin도 개발자 외 계정은 점검 안내 후 패널 진입을 막는다.
3. 안내 문구는 `서버 이전 작업 중입니다. 더욱 빨라지고 쾌적해진 beyond us를 기대해주세요!`와 `20:00~21:00`을 표시한다.
4. 캐시 버전을 갱신하고 main 반영 가능한 상태로 커밋한다.

성공 기준.

- `SingSangSong`, `카니보어시즌2`는 앱과 admin 진입 가능.
- 다른 계정은 앱/admin에서 점검 안내만 보임.
- `APP_VERSION`, `app.html` query, `sw.js` cache, `version.txt`가 같은 버전.
