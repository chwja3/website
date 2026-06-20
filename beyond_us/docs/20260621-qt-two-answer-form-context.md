# QT 답변 2개 폼 변경 컨텍스트

- 기존 QT 폼은 2026년 6월 20일과 21일에만 답변 3개와 기도제목을 표시했다.
- 운영 요청에 따라 답변 3을 제거하고, 사용자는 답변 1, 답변 2, 기도제목만 작성한다.
- 기존 Supabase 함수 `submit_qt_reflection_v2(text, date, text, text, text, text)`는 이미 PROD에 있을 수 있으므로 시그니처는 유지한다.
- 새 프론트는 `p_answer3_text`를 빈 문자열로 보내고, 새 SQL은 `answer3_text`를 빈 값으로 저장한다.
