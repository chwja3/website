-- 어드민 탭 활성화 패널에 노출되는 tab_settings.label 갱신
-- counseling: "익명 고민상담" → "목사님께 무물"
-- visible_radio: "보이는 라디오" → "별빛 우편함"
begin;

update public.tab_settings
set label = '목사님께 무물', updated_at = now()
where tab_key = 'counseling';

update public.tab_settings
set label = '별빛 우편함', updated_at = now()
where tab_key = 'visible_radio';

commit;
