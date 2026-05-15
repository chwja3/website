# Backup Modern Schema Context

## 결정

백업은 원본 스프레드시트를 직접 바꾸지 않는다. Drive 사본을 만든 뒤, 그 사본에만 최신 운영 탭 구조를 적용한다.

## 현재 운영 구조

현재 기준 데이터의 중심은 `Events`다. `config`, `raw_checkins`, `CardDraws`, `BonusDraws`는 legacy 시트로 남기되 백업 사본에서도 숨김 처리한다.

## 주의점

백업 정규화는 탭 구조와 헤더를 현재 형식으로 맞추는 기능이다. 원본에 없는 과거 데이터를 새 Events 데이터로 새로 변환하는 마이그레이션은 아니다.
