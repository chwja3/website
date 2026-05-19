-- Supabase 테이블과 주요 컬럼 설명을 등록하는 마이그레이션
begin;

comment on type public.profile_role is '앱 사용자 권한 구분. 일반 사용자, 조장, 관리자, 개발자 계정을 나눈다.';
comment on type public.account_status is '계정 사용 상태. 비활성, 삭제, 차단 상태는 로그인과 집계에서 제외하는 기준으로 사용한다.';
comment on type public.attendance_status is '수련회 참석 상태. 전체 참석, 부분 참석, 불참, 미확정 상태를 구분한다.';
comment on type public.group_role is '수련회 조 안에서의 역할. 조원, 조장, 부조장을 구분한다.';
comment on type public.tab_status is '사용자 앱 탭의 운영 상태. 열림과 닫힘을 구분하고 화면 표시 색상에 사용한다.';
comment on type public.event_source is '이벤트 생성 출처. 사용자 앱, 관리자, 서버 자동 처리, 마이그레이션, 개발 환경을 구분한다.';
comment on type public.approval_status is '사진 인증 등 운영진 검수 대상의 승인 상태.';
comment on type public.card_grade is '카드 등급. 일반, 레어, 히든 카드를 구분한다.';
comment on type public.trade_status is '카드 교환 요청의 진행 상태.';

comment on function public.set_updated_at() is '행 수정 시 updated_at을 현재 시각으로 갱신하는 공통 trigger 함수.';

comment on table public.profiles is '앱 가입자 기본 정보와 운영 상태를 저장하는 사용자 중심 테이블.';
comment on column public.profiles.id is '내부에서 사용하는 사용자 UUID. 화면 표시용 아이디와 분리한다.';
comment on column public.profiles.auth_user_id is 'Supabase Auth 사용자와 연결되는 ID.';
comment on column public.profiles.participant_no is '001부터 부여하는 참가자 고유 번호.';
comment on column public.profiles.participant_code is '참가자 번호를 3자리 문자열로 표시한 값.';
comment on column public.profiles.login_id is '사용자가 로그인할 때 입력하는 아이디. citext로 저장해 중복 정책을 명확히 관리한다.';
comment on column public.profiles.display_name is '앱 화면에 표시할 별명 또는 닉네임.';
comment on column public.profiles.name is '운영진이 확인하는 실제 이름.';
comment on column public.profiles.parish is '교구, VIP, 교회학교, 목양교구 등 소속 분류.';
comment on column public.profiles.role is '일반 사용자, 조장, 관리자, 개발자 권한.';
comment on column public.profiles.account_status is '활성, 비활성, 삭제, 차단 등 계정 상태.';
comment on column public.profiles.raffle_excluded is '추첨권 발급 제외 여부. 제외 시 기존 추첨권 회수와 향후 발급 차단에 사용한다.';
comment on column public.profiles.legacy_sheet_user_id is 'Google Sheet에서 사용하던 기존 사용자 식별자.';

comment on table public.profile_private_notes is '관리자가 사용자별로 남기는 비공개 운영 메모.';
comment on column public.profile_private_notes.profile_id is '메모 대상 사용자.';
comment on column public.profile_private_notes.created_by is '메모를 작성한 관리자.';

comment on table public.retreat_attendance is '수련회 참석 여부와 부분 참여 tier를 관리하는 테이블.';
comment on column public.retreat_attendance.profile_id is '참석 정보를 연결할 사용자.';
comment on column public.retreat_attendance.participation_tier is '부분 참여자의 참여 시간대 또는 운영 tier.';
comment on column public.retreat_attendance.attended is '실제 참석 체크 여부.';

comment on table public.groups is '수련회 조 정보를 저장하는 테이블.';
comment on column public.groups.group_no is '운영진이 사용하는 조 번호.';
comment on column public.groups.tier is '부분 참여 시간대 등을 고려한 조 편성 tier.';

comment on table public.group_members is '사용자와 수련회 조를 연결하고 조장, 부조장 여부를 저장한다.';
comment on column public.group_members.group_id is '배정된 조.';
comment on column public.group_members.profile_id is '조에 속한 사용자.';
comment on column public.group_members.group_role is '조 안에서의 역할.';

comment on table public.app_settings is '앱 전체 설정값을 key-value 형태로 저장하는 테이블.';
comment on column public.app_settings.key is '설정 키.';
comment on column public.app_settings.value_json is '설정값. 숫자, 문자열, 객체를 jsonb로 저장한다.';
comment on column public.app_settings.value_type is '설정값 해석을 돕는 타입 힌트.';

comment on table public.tab_settings is '사용자 앱 탭의 노출 여부, 상태 색상, 정렬 순서를 관리한다.';
comment on column public.tab_settings.tab_key is '탭을 식별하는 영문 key.';
comment on column public.tab_settings.label is '사용자와 관리자 화면에 표시할 탭 이름.';
comment on column public.tab_settings.enabled is '탭을 사용자 앱에 노출할지 여부.';
comment on column public.tab_settings.status is '탭이 실제 참여 가능한 상태인지 표시하는 운영 상태.';

comment on table public.mission_weeks is '사전미션 주차 설정과 카드팩 지급 기준을 저장한다.';
comment on column public.mission_weeks.week_key is 'w1, w2 같은 주차 key.';
comment on column public.mission_weeks.draw_threshold is '해당 주차에서 카드팩을 지급하는 누적 점수 기준.';

comment on table public.mission_items is '주차별 사전미션 항목 정의.';
comment on column public.mission_items.week_key is '소속 주차.';
comment on column public.mission_items.item_no is '주차 안에서의 항목 번호.';
comment on column public.mission_items.score_weight is '항목 완료 시 누적되는 점수.';

comment on table public.cards is '앱에서 수집하는 카드 정의와 이미지 경로.';
comment on column public.cards.id is '카드 번호. 일반 카드는 1부터 9, 레어 카드는 10번을 기본으로 둔다.';
comment on column public.cards.grade is '카드 등급.';
comment on column public.cards.image_path is '프론트에서 사용할 카드 이미지 경로.';

comment on table public.events is '보상, 카드팩, 미션 제출, 추첨권 변화 등 변경 이력을 남기는 원장 테이블.';
comment on column public.events.profile_id is '이벤트 대상 사용자.';
comment on column public.events.event_type is 'mission.submitted, card.drawn, raffle.issued 같은 이벤트 이름.';
comment on column public.events.ref_type is '이벤트가 참조하는 대상 종류.';
comment on column public.events.ref_id is '이벤트가 참조하는 외부 또는 내부 ID.';
comment on column public.events.amount is '증감 수량이 있는 이벤트의 수량.';
comment on column public.events.payload is '이벤트별 추가 세부 정보.';
comment on column public.events.source is '이벤트 생성 출처.';
comment on column public.events.request_id is '중복 요청 방지를 위한 클라이언트 또는 서버 request id.';

comment on table public.user_inventory is '사용자별 일반 카드팩과 현장미션 카드팩 보유 수량을 빠르게 읽기 위한 현재 상태 테이블.';
comment on column public.user_inventory.normal_pack_remaining is '사용 가능한 일반 카드팩 수.';
comment on column public.user_inventory.special_pack_remaining is '사용 가능한 현장미션 카드팩 수.';

comment on table public.user_cards is '사용자별 카드 보유 수량을 저장하는 현재 상태 테이블.';
comment on column public.user_cards.profile_id is '카드 보유자.';
comment on column public.user_cards.card_id is '보유 카드.';
comment on column public.user_cards.quantity is '현재 보유 수량.';

comment on table public.user_summary is '대시보드와 앱 첫 화면에서 빠르게 읽기 위한 사용자별 집계 테이블.';
comment on column public.user_summary.mission_count is '사용자의 사전미션 제출 또는 참여 집계.';
comment on column public.user_summary.total_cards is '현재 보유 카드 총 수량.';
comment on column public.user_summary.raffle_ticket_count is '현재 활성 추첨권 수.';
comment on column public.user_summary.payload is '화면 최적화를 위한 확장 집계 데이터.';

comment on table public.mission_submissions is '사용자가 제출한 사전미션 원본 기록.';
comment on column public.mission_submissions.date_key is '미션 수행 날짜.';
comment on column public.mission_submissions.items_json is '제출한 미션 항목 텍스트 목록.';
comment on column public.mission_submissions.indices_json is '제출한 미션 항목 번호 목록.';

comment on table public.mission_progress is '사용자와 주차별 사전미션 누적 상태.';
comment on column public.mission_progress.total_score is '해당 주차 누적 점수.';
comment on column public.mission_progress.date_keys is '참여한 날짜 목록.';
comment on column public.mission_progress.slot_counts is '항목별 제출 횟수 집계.';

comment on table public.raffle_conditions is '추첨권 자동 발급 조건 정의.';
comment on column public.raffle_conditions.condition_key is 'app_signup, card_3, card_5, card_10 같은 조건 key.';
comment on column public.raffle_conditions.enabled is '해당 조건으로 추첨권을 발급할지 여부.';

comment on table public.raffle_tickets is '추첨권 번호별 활성 상태와 현재 소유자를 저장한다.';
comment on column public.raffle_tickets.ticket_no is '재활용 가능한 추첨권 번호.';
comment on column public.raffle_tickets.active is '현재 누군가에게 발급되어 있으면 true.';
comment on column public.raffle_tickets.profile_id is '현재 추첨권 소유자. 회수되면 비운다.';
comment on column public.raffle_tickets.condition_key is '추첨권이 발급된 조건.';
comment on column public.raffle_tickets.revoked_reason is '회수 사유.';

comment on table public.hold_pray_entries is 'Hold & Pray에 올라온 기도 제목 또는 묵상 카드.';
comment on column public.hold_pray_entries.profile_id is '작성자. 익명이어도 내부 연결은 유지할 수 있다.';
comment on column public.hold_pray_entries.anonymous is '사용자 화면에서 작성자를 숨길지 여부.';
comment on column public.hold_pray_entries.visible is '사용자 화면 노출 여부.';

comment on table public.hold_pray_guesses is 'Hold & Pray 카드의 작성자를 맞히는 사용자 응답.';
comment on column public.hold_pray_guesses.card_index is '주차 안에서 표시되는 카드 위치.';
comment on column public.hold_pray_guesses.correct is '정답 여부.';

comment on table public.hold_pray_hints is 'Hold & Pray 작성자 힌트.';
comment on column public.hold_pray_hints.hint_text is '사용자에게 보여줄 힌트 문구.';

comment on table public.bbb_assignments is 'B.B.B 미션을 위한 케어버디와 시크릿버디 매칭 정보.';
comment on column public.bbb_assignments.care_buddy_id is '내가 돌볼 케어버디.';
comment on column public.bbb_assignments.secret_buddy_id is '나를 돌보는 시크릿버디 또는 공개 전 대상.';
comment on column public.bbb_assignments.secret_revealed is '시크릿버디 공개 여부.';

comment on table public.bbb_messages is 'B.B.B 대상자에게 보내는 메시지 기록.';
comment on column public.bbb_messages.from_profile_id is '메시지 발신자.';
comment on column public.bbb_messages.to_profile_id is '메시지 수신자.';
comment on column public.bbb_messages.read_at is '수신자가 읽은 시각.';

comment on table public.pilgrim_spots is '천로역정 지도 위 인증 스팟 좌표.';
comment on column public.pilgrim_spots.spot_index is '0부터 6까지의 스팟 번호.';
comment on column public.pilgrim_spots.top_percent is '지도 이미지 기준 세로 위치 퍼센트.';
comment on column public.pilgrim_spots.left_percent is '지도 이미지 기준 가로 위치 퍼센트.';

comment on table public.pilgrim_assignments is '사용자별 천로역정 랜덤 미션 스팟 2개와 완료 보상 상태.';
comment on column public.pilgrim_assignments.spot_indices is '사용자에게 배정된 스팟 번호 2개.';
comment on column public.pilgrim_assignments.reward_event_id is '두 스팟 완료 후 지급된 레어 카드 이벤트.';

comment on table public.mission_photo_submissions is 'BBB와 천로역정 등 사진 인증이 필요한 현장미션 제출물.';
comment on column public.mission_photo_submissions.mission_key is 'bbb_m1, bbb_m2, pilgrim 같은 미션 key.';
comment on column public.mission_photo_submissions.storage_path is 'Supabase Storage에 저장된 사진 경로.';
comment on column public.mission_photo_submissions.approval_status is '운영진 검수 상태.';
comment on column public.mission_photo_submissions.reward_event_id is '승인 후 지급된 카드팩 또는 카드 보상 이벤트.';

comment on table public.trades is '사용자 간 카드 교환 요청.';
comment on column public.trades.requester_id is '교환을 요청한 사용자.';
comment on column public.trades.target_id is '교환 요청을 받은 사용자.';
comment on column public.trades.status is '교환 요청 상태.';

comment on table public.trade_prayers is '교환 과정에서 서로를 위해 기도한 기록.';
comment on column public.trade_prayers.trade_id is '연결된 교환 요청.';
comment on column public.trade_prayers.profile_id is '기도 완료를 기록한 사용자.';

comment on table public.physical_card_receipts is '실물 카드 수령 여부와 수령 수량.';
comment on column public.physical_card_receipts.received_qty is '운영진이 확인한 실물 카드 수령 수량.';
comment on column public.physical_card_receipts.updated_by is '수령 상태를 수정한 관리자.';

comment on table public.notices is '사용자 앱 공지사항.';
comment on column public.notices.visible is '사용자에게 공지를 노출할지 여부.';

comment on table public.notice_reads is '사용자별 공지 읽음 상태.';
comment on column public.notice_reads.notice_id is '읽은 공지.';
comment on column public.notice_reads.profile_id is '읽은 사용자.';

comment on table public.inquiries is '사용자의 개발자 문의와 관리자 답변.';
comment on column public.inquiries.profile_id is '문의 작성자.';
comment on column public.inquiries.reply is '관리자 또는 개발자 답변.';
comment on column public.inquiries.status is 'open, closed 등 문의 처리 상태.';

comment on table public.qt_contents is '날짜별 Q.T. 말씀 묵상 본문과 질문.';
comment on column public.qt_contents.content_date is '묵상 본문이 표시될 날짜.';
comment on column public.qt_contents.questions is '묵상 질문 목록.';
comment on column public.qt_contents.storage_path is '원본 PDF 페이지나 이미지가 있을 때 연결하는 Storage 경로.';
comment on column public.qt_contents.visible is '사용자 앱에 공개할지 여부.';

commit;
