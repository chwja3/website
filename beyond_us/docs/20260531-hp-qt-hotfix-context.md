# 2026-05-31 H&P/Q.T. 긴급 보정 컨텍스트

- 성온 사용자 쪽에서 `해솔` 정답이 맞지 않는 제보가 있었다.
- 기존 H&P 비교는 `bu_hp_answer_key(guess) = bu_hp_answer_key(answer_name)` 완전 일치라서, 저장된 이름이 `김해솔`이면 `해솔`은 오답으로 남는다.
- Q.T. 2026-05-31 이미지는 로컬 `beyond_us/QT/260531.png`와 PROD Supabase Storage 모두 존재했다.
- 일부 사용자만 "준비중"을 보는 상황은 상대 경로 해석, Storage 일시 실패, 오래된 앱 캐시가 겹친 경우로 보고 fallback 후보를 늘린다.
