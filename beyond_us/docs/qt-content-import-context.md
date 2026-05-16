# Q.T. 본문 게시 데이터화 컨텍스트

## 결정

- 앱 또는 GAS가 46MB 원본 PDF를 매번 읽는 구조는 피한다.
- 원본 PDF는 보관용으로 두고, 앱에서는 날짜별로 정리된 `QTContents` 데이터를 읽는 구조를 목표로 한다.
- 날짜별 자동 추출은 PDF 텍스트 품질에 따라 달라지므로, 먼저 페이지별 텍스트 추출 가능 여부를 확인한다.
- 확인 결과 PDF는 75쪽이며 텍스트 추출이 가능하다.
- 날짜 인덱스는 2026-05-01부터 2026-06-30까지 61개가 모두 잡혔다.
- 산출물은 `beyond_us/data/qt/extracted`와 `beyond_us/data/qt/pages`에 만들었다.
- `QTContents` 시트 초안은 `beyond_us/data/qt/extracted/qt-contents-sheet-draft.csv`로 생성했다.
- 페이지별 PDF는 총 약 72MB라 Git에 넣지 않고 로컬 검수용 산출물로 둔다.
- 날짜별 제목 추정은 PDF의 2단 레이아웃 때문에 일부 지저분하므로 `QTContents` 시트 반영 전 CSV 검수가 필요하다.
