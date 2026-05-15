# 카드팩 Collection 반영 속도 개선 계획

## 목표

카드팩을 개봉한 뒤 Collection 반영과 카드 클릭 가능 상태까지의 체감 대기 시간을 줄인다.

## 범위

1. 카드팩 종료 후 이미 서버 응답에 포함된 Collection/Ticket 결과를 먼저 화면에 반영한다.
2. 카드팩 종료 직후 `userStatus`를 중복으로 새로고침하는 흐름을 줄인다.
3. 카드 뒷면 클릭 가능 전환 딜레이를 최소화한다.
4. Collection 이미지에 lazy loading과 async decoding 힌트를 추가한다.
5. 앱 코드에서 참조되지 않는 이미지 파일을 `images/unused` 폴더로 분리한다.

## 제외

- 미사용 이미지의 최종 삭제는 사용자가 직접 진행한다.
- WebP 변환은 로컬 변환 도구 사용 가능 여부를 먼저 확인한다.
- GAS 데이터 구조와 카드 지급 정책은 변경하지 않는다.

## 검증 기준

- 카드팩 개봉 후 Collection 탭 전환이 즉시 보인다.
- 카드 뒷면 등장 후 클릭 가능 상태로 전환되는 지연이 줄어든다.
- Collection 이미지 렌더링이 기존 기능을 깨지 않는다.
- `APP_VERSION`, `version.txt`, `app.html` 캐시 버전이 동기화된다.
- `node --check beyond_us/app.js`와 `git diff --check`가 통과한다.
