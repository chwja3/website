-- 숙소배정안내 PDF에서 추출한 숙소 배정표를 Supabase 배정표에 반영한다.
begin;

alter table public.retreat_logistics_assignments
add column if not exists source_batch text not null default 'manual';

alter table public.retreat_logistics_assignments
add column if not exists match_status text not null default 'manual';

alter table public.retreat_logistics_assignments
add column if not exists match_detail text not null default '';

alter table public.retreat_logistics_assignments
add column if not exists candidate_profiles jsonb not null default '[]'::jsonb;

create index if not exists retreat_logistics_assignments_source_batch_idx
on public.retreat_logistics_assignments (source_batch, sort_order);

create or replace function public.bu_logistics_parish_key(p_value text)
returns text
language sql
immutable
as $$
  select case
    when regexp_replace(upper(coalesce(p_value, '')), '\s+', '', 'g') like '%VIP%' then 'VIP'
    when regexp_replace(coalesce(p_value, ''), '\s+', '', 'g') like '%교회학교%' then '교회학교'
    when regexp_replace(coalesce(p_value, ''), '\s+', '', 'g') like '%목양%' then '목양교구'
    when regexp_replace(coalesce(p_value, ''), '\s+', '', 'g') ~ '1(교구|청|청년)' then '1청'
    when regexp_replace(coalesce(p_value, ''), '\s+', '', 'g') ~ '2(교구|청|청년)' then '2청'
    when regexp_replace(coalesce(p_value, ''), '\s+', '', 'g') ~ '3(교구|청|청년)' then '3청'
    when regexp_replace(coalesce(p_value, ''), '\s+', '', 'g') ~ '4(교구|청|청년)' then '4청'
    else trim(coalesce(p_value, ''))
  end;
$$;

create or replace function public.get_my_logistics_assignment(
  p_login_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_assignment public.retreat_logistics_assignments%rowtype;
begin
  if v_auth_uid is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'unauthorized');
  end if;

  select *
  into v_profile
  from public.profiles
  where auth_user_id = v_auth_uid
    and account_status = 'active'
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('ok', false, 'source', 'supabase', 'error', 'user_not_found');
  end if;

  select a.*
  into v_assignment
  from public.retreat_logistics_assignments a
  where a.profile_id = v_profile.id
     or (
       a.profile_id is null
       and a.login_id is not null
       and lower(a.login_id) = lower(v_profile.login_id::text)
     )
     or (
       a.profile_id is null
       and coalesce(a.login_id, '') = ''
       and public.bu_logistics_normalize(a.name) = public.bu_logistics_normalize(v_profile.name)
       and (
         public.bu_logistics_parish_key(a.parish) = public.bu_logistics_parish_key(v_profile.parish)
         or coalesce(a.parish, '') = ''
       )
     )
  order by
    case
      when a.profile_id = v_profile.id then 0
      when a.login_id is not null and lower(a.login_id) = lower(v_profile.login_id::text) then 1
      else 2
    end,
    a.sort_order,
    a.updated_at desc
  limit 1;

  if v_assignment.id is null then
    return jsonb_build_object(
      'ok', true,
      'source', 'supabase',
      'profile', jsonb_build_object(
        'nickname', v_profile.login_id,
        'name', v_profile.name,
        'parish', v_profile.parish
      ),
      'assignment', null
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', 'supabase',
    'profile', jsonb_build_object(
      'nickname', v_profile.login_id,
      'name', v_profile.name,
      'parish', v_profile.parish
    ),
    'assignment', public.bu_logistics_assignment_json(v_assignment)
  );
end;
$$;

delete from public.retreat_logistics_assignments
where source_batch = 'lodging_20260620';

with imported(sort_order, name, parish_raw, lodging_building, lodging_room, is_room_leader) as (
  values
    (1, 'Cheng jia shan', '2교구', '하우스', '416', false),
    (2, '고서윤', '2교구', '하우스', '402', false),
    (3, '공다영', '3교구', '하우스', '325', true),
    (4, '곽지섭', '3교구', '하우스', '204', true),
    (5, '권수민', '1교구', '하우스', '322', true),
    (6, '권영빈', '3교구', '빌리지', '303/203', false),
    (7, '권영서', '2교구', '빌리지', '205', false),
    (8, '권혜민', '1교구', '빌리지', '105', false),
    (9, '김경채', '1교구', '하우스', '318', false),
    (10, '김광희', '4교구', '빌리지', '303/203', true),
    (11, '김규리', '1교구', '하우스', '406', false),
    (12, '김다정', '2교구', '하우스', '324', true),
    (13, '김도원', '1교구', '빌리지', '303/201', false),
    (14, '김동규', '1교구', '하우스', '306', false),
    (15, '김동욱', '4교구', '하우스', '418', false),
    (16, '김미경', '3교구', '하우스', '325', false),
    (17, '김민경', '4교구', '하우스', '212', false),
    (18, '김민석', '3교구', '하우스', '206', false),
    (19, '김민설', '4교구', '하우스', '412', false),
    (20, '김민희', '4교구', '하우스', '321', true),
    (21, '김병진', '4교구', '하우스', '310', false),
    (22, '김보희', '3교구', '하우스', '211', false),
    (23, '김빛나래', '4교구', '하우스', '209', true),
    (24, '김빛아름', '4교구', '하우스', '321', false),
    (25, '김서라', '4교구', '하우스', '405', true),
    (26, '김성애', '4교구', '빌리지', '103', true),
    (27, '김성은', '3교구', '하우스', '206', false),
    (28, '김소영', '2교구', '빌리지', '104', false),
    (29, '김시진', '3교구', '하우스', '404', false),
    (30, '김영은', '1교구', '하우스', '322', false),
    (31, '김영진', '3교구', '하우스', '404', true),
    (32, '김예닮', '3교구', '하우스', '320', false),
    (33, '김예담', '1교구', '빌리지', '105', true),
    (34, '김예서', '1교구', '하우스', '413', false),
    (35, '김용한', '4교구', '하우스', '309', false),
    (36, '김윤지', '1교구', '하우스', '318', true),
    (37, '김은서', '4교구', '하우스', '323', false),
    (38, '김은수', '2교구', '하우스', '407', true),
    (39, '김은정', '3교구', '빌리지', '104', false),
    (40, '김응현', '2교구', '하우스', '313', false),
    (41, '김이수', '1교구', '빌리지', '106', false),
    (42, '김재원', '1교구', '하우스', '308', false),
    (43, '김정숙', '4교구', '하우스', '319', false),
    (44, '김주리', '4교구', '빌리지', '206', false),
    (45, '김주와', '1교구', '빌리지', '203', false),
    (46, '김준희', '2교구', '하우스', '304', true),
    (47, '김지민', '1교구', '하우스', '307', true),
    (48, '김지원', '2교구', '빌리지', '107', true),
    (49, '김지유', '1교구', '하우스', '414', false),
    (50, '김지훈', '3교구', '하우스', '418', false),
    (51, '김진웅', '4교구', '하우스', '303', true),
    (52, '김태현', '1교구', '빌리지', '303/207', false),
    (53, '김태훈', '2교구', '하우스', '203', false),
    (54, '김해솔', '2교구', '빌리지', '205', true),
    (55, '김현', '2교구', '하우스', '306', true),
    (56, '김현진', '3교구', '하우스', '211', false),
    (57, '김형태', '3교구', '하우스', '302', false),
    (58, '김혜원', '3교구', '하우스', '406', true),
    (59, '김희근', '2교구', '하우스', '206', true),
    (60, '김희창', '4교구', '하우스', '302', true),
    (61, '나성진', '4교구', '하우스', '416', true),
    (62, '노희예', '3교구', '하우스', '320', true),
    (63, '마문도', '1교구', '하우스', '420', false),
    (64, '문지수', '2교구', '빌리지', '106', true),
    (65, '문진우', '4교구', '빌리지', '303/207', true),
    (66, '민혜진', '3교구', '빌리지', '101', false),
    (67, '박교은', '1교구', '하우스', '413', true),
    (68, '박민혁', '3교구', '하우스', '308', true),
    (69, '박성온', '4교구', '하우스', '412', false),
    (70, '박성호', '1교구', '빌리지', '204', false),
    (71, '박세은', '2교구', '하우스', '410', true),
    (72, '박소영', '1교구', '하우스', '410', false),
    (73, '박신혜', '4교구', '하우스', '328', false),
    (74, '박예은', '2교구', '하우스', '327', true),
    (75, '박원진', '4교구', '하우스', '323', true),
    (76, '박유나', '2교구', '하우스', '327', false),
    (77, '박은별', '3교구', '하우스', '417', false),
    (78, '박은혜', '4교구', '하우스', '328', true),
    (79, '박재균', '1교구', '하우스', '207', false),
    (80, '박주명', '3교구', '빌리지', '204', false),
    (81, '박진용', '3교구', '하우스', '419', false),
    (82, '배진형', '4교구', '빌리지', '201', true),
    (83, '백온유', '2교구', '하우스', '321', true),
    (84, '백지원', '3교구', '빌리지', '101', false),
    (85, '서가영', '2교구', '하우스', '409', false),
    (86, '서규원', '2교구', '하우스', '204', false),
    (87, '서다예', '3교구', '빌리지', '205', false),
    (88, '서유진', '1교구', '빌리지', '107', false),
    (89, '서찬영', '1교구', '하우스', '208', false),
    (90, '서채운', '2교구', '하우스', '407', false),
    (91, '서현덕', '3교구', '하우스', '419', true),
    (92, '석상은', '2교구', '하우스', '210', false),
    (93, '석재남', '1교구', '하우스', '208', false),
    (94, '설예랑', '4교구', '하우스', '212', true),
    (95, '성예림', '1교구', '빌리지', '105', false),
    (96, '소수엽', '3교구', '하우스', '302', false),
    (97, '손민경', '4교구', '하우스', '211', false),
    (98, '손승현', '1교구', '빌리지', '201', false),
    (99, '손정범', '2교구', '하우스', '207', true),
    (100, '손정인', '2교구', '빌리지', '104', false),
    (101, '손희성', '1교구', '하우스', '414', false),
    (102, '송예린', '1교구', '하우스', '408', true),
    (103, '신라엘', '2교구', '하우스', '208', true),
    (104, '신보라', '1교구', '하우스', '414', true),
    (105, '신소희', '4교구', '하우스', '211', true),
    (106, '신영호', '3교구', '하우스', '312', true),
    (107, '신혜지', '3교구', '빌리지', '103', false),
    (108, '안성재', '3교구', '빌리지', '204', false),
    (109, '안이삭', '3교구', '하우스', '312', false),
    (110, '안지인', '4교구', '하우스', '317', false),
    (111, '안진홍', '3교구', '빌리지', '201', false),
    (112, '애니', '1교구', '하우스', '210', false),
    (113, '양다니엘', '3교구', '하우스', '204', false),
    (114, '양예지', '3교구', '하우스', '319', true),
    (115, '여인규', '2교구', '빌리지', '303/201', false),
    (116, '여창민', '4교구', '하우스', '311', true),
    (117, '염수진', '4교구', '하우스', '403', true),
    (118, '오윤택', '2교구', '빌리지', '204', true),
    (119, '위유림', '2교구', '빌리지', '104', true),
    (120, '유영수', '1교구', '빌리지', '203', false),
    (121, '유지인', '1교구', '하우스', '413', false),
    (122, '유하람', '4교구', '하우스', '309', true),
    (123, '유하영', '2교구', '하우스', '415', false),
    (124, '유하영', '3교구', '빌리지', '102', false),
    (125, '유하은', '2교구', '빌리지', '102', false),
    (126, '유하진', '4교구', '빌리지', '102', false),
    (127, '유형준', '4교구', '하우스', '308', true),
    (128, '윤별', '4교구', '하우스', '405', false),
    (129, '윤시환', '3교구', '하우스', '302', true),
    (130, '윤영록', '3교구', '빌리지', '303/201', true),
    (131, '윤지강', '1교구', '하우스', '305', false),
    (132, '이가희', '4교구', '하우스', '209', false),
    (133, '이건희', '1교구', '하우스', '203', false),
    (134, '이경룡', '3교구', '하우스', '420', true),
    (135, '이경은', '1교구', '하우스', '416', false),
    (136, '이돈영', '2교구', '빌리지', '205', false),
    (137, '이민지', '2교구', '하우스', '417', false),
    (138, '이상윤', '3교구', '하우스', '316', true),
    (139, '이상은', '1교구', '하우스', '211', false),
    (140, '이서정', '2교구', '하우스', '324', false),
    (141, '이성영', '4교구', '빌리지', '206', true),
    (142, '이성호', '4교구', '하우스', '307', true),
    (143, '이세희', '4교구', '하우스', '211', false),
    (144, '이예은', '3교구', '하우스', '326', true),
    (145, '이예인', '2교구', '하우스', '327', false),
    (146, '이원철', '3교구', '하우스', '303', false),
    (147, '이재선', '4교구', '하우스', '317', true),
    (148, '이제형', '1교구', '빌리지', '203', false),
    (149, '이주광', '2교구', '하우스', '315', true),
    (150, '이지우', '3교구', '하우스', '212', false),
    (151, '이진성', '4교구', '하우스', '307', false),
    (152, '이찬영', '3교구', '하우스', '202', false),
    (153, '이평화', '3교구', '하우스', '315', false),
    (154, '이현기', '2교구', '빌리지', '303/203', false),
    (155, '이희찬', '3교구', '하우스', '208', false),
    (156, '임다혜', '2교구', '빌리지', '102', true),
    (157, '임재민', '1교구', '하우스', '419', false),
    (158, '임지훈', '3교구', '하우스', '210', false),
    (159, '장진아', '2교구', '하우스', '416', true),
    (160, '장한나', '2교구', '하우스', '415', true),
    (161, '장현준', '1교구', '하우스', '202', false),
    (162, '전도현', '3교구', '빌리지', '303/201', false),
    (163, '전수호', '1교구', '하우스', '205', false),
    (164, '전승민', '1교구', '빌리지', '105', false),
    (165, '전승훈', '4교구', '하우스', '308', false),
    (166, '전준규', '3교구', '하우스', '205', true),
    (167, '전준우', '3교구', '하우스', '305', true),
    (168, '전준재', '3교구', '빌리지', '303', false),
    (169, '정다운', '4교구', '빌리지', '206', false),
    (170, '정대현', '1교구', '하우스', '204', false),
    (171, '정대호', '2교구', '빌리지', '303/203', false),
    (172, '정명화', '4교구', '하우스', '314', true),
    (173, '정보빈', '4교구', '하우스', '209', false),
    (174, '정승호', '4교구', '하우스', '310', true),
    (175, '정에스더', '4교구', '빌리지', '103', false),
    (176, '정요안', '4교구', '하우스', '311', false),
    (177, '정준무', '3교구', '하우스', '307', false),
    (178, '정하경', '2교구', '하우스', '212', false),
    (179, '정혜진', '3교구', '빌리지', '107', false),
    (180, '조연주', '3교구', '하우스', '326', false),
    (181, '조예서', '1교구', '하우스', '408', false),
    (182, '조은산', '3교구', '빌리지', '103', false),
    (183, '조인택', '1교구', '하우스', '203', false),
    (184, '조진형', '1교구', '하우스', '207', false),
    (185, '조학준', '2교구', '하우스', '313', true),
    (186, '조현규', '3교구', '하우스', '206', false),
    (187, '조현진', '1교구', '하우스', '207', false),
    (188, '주건호', '1교구', '하우스', '205', false),
    (189, '주대현', '2교구', '하우스', '420', false),
    (190, '주세현', '1교구', '하우스', '304', false),
    (191, '주진호', '1교구', '하우스', '205', false),
    (192, '지윤성', '2교구', '하우스', '203', true),
    (193, '지윤호', '2교구', '하우스', '202', true),
    (194, '진형철', '3교구', '빌리지', '201', false),
    (195, '천신원', '3교구', '빌리지', '101', true),
    (196, '천은경', '3교구', '하우스', '417', true),
    (197, '천혜영', '4교구', '하우스', '209', false),
    (198, '최가은', '2교구', '빌리지', '106', false),
    (199, '최계은', '4교구', '하우스', '212', false),
    (200, '최미나', '2교구', '하우스', '409', true),
    (201, '최승원', '4교구', '하우스', '314', false),
    (202, '최시온', '2교구', '하우스', '415', false),
    (203, '최원경', '4교구', '하우스', '402', true),
    (204, '최지호', '4교구', '하우스', '418', true),
    (205, '최한나', '3교구', '하우스', '412', true),
    (206, '최현아', '2교구', '하우스', '321', false),
    (207, '하나은', '3교구', '빌리지', '101', false),
    (208, '하선엽', '3교구', '하우스', '316', false),
    (209, '한별', '2교구', '빌리지', '106', false),
    (210, '한은지', '4교구', '하우스', '403', false),
    (211, '한정인', '2교구', '하우스', '210', true),
    (212, '허경웅', '4교구', '하우스', '311', false),
    (213, '허세빈', '2교구', '하우스', '416', false),
    (214, '허완', '4교구', '하우스', '310', false),
    (215, '허하은', '2교구', '빌리지', '107', false),
    (216, '황영조', '3교구', '하우스', '202', false),
    (217, '황은택', '2교구', '빌리지', '203', true)
),
prepared as (
  select
    sort_order,
    name,
    public.bu_logistics_parish_key(parish_raw) as parish,
    lodging_building,
    lodging_room,
    case when is_room_leader then '방장' else '' end as lodging_note,
    is_room_leader
  from imported
),
candidate_rows as (
  select
    p0.sort_order,
    p.id as profile_id,
    p.login_id::text as login_id,
    p.name as profile_name,
    p.parish as profile_parish,
    p.created_at
  from prepared p0
  left join public.profiles p
    on p.account_status = 'active'
   and public.bu_logistics_normalize(p.name) = public.bu_logistics_normalize(p0.name)
   and public.bu_logistics_parish_key(p.parish) = p0.parish
),
candidate_summary as (
  select
    sort_order,
    count(profile_id) as candidate_count,
    (array_agg(profile_id order by created_at) filter (where profile_id is not null))[1] as matched_profile_id,
    (array_agg(login_id order by created_at) filter (where profile_id is not null))[1] as matched_login_id,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'profileId', profile_id,
          'nickname', login_id,
          'name', profile_name,
          'parish', profile_parish
        )
        order by created_at
      ) filter (where profile_id is not null),
      '[]'::jsonb
    ) as candidate_profiles,
    coalesce(string_agg(login_id, ', ' order by created_at) filter (where profile_id is not null), '') as candidate_logins
  from candidate_rows
  group by sort_order
)
insert into public.retreat_logistics_assignments (
  source_batch,
  profile_id,
  login_id,
  name,
  parish,
  group_name,
  lodging_building,
  lodging_room,
  lodging_group,
  lodging_note,
  vehicle_group,
  vehicle_route,
  vehicle_no,
  vehicle_departure,
  vehicle_seat,
  vehicle_note,
  raw_note,
  sort_order,
  match_status,
  match_detail,
  candidate_profiles
)
select
  'lodging_20260620',
  case when cs.candidate_count = 1 then cs.matched_profile_id else null end,
  case when cs.candidate_count = 1 then cs.matched_login_id else null end,
  p.name,
  p.parish,
  '',
  p.lodging_building,
  p.lodging_room,
  '',
  p.lodging_note,
  '',
  '',
  '',
  '',
  '',
  '',
  case
    when cs.candidate_count = 0 then '앱 가입자 매칭 없음'
    when cs.candidate_count > 1 then '이름 중복 확인 필요: ' || cs.candidate_logins
    else ''
  end,
  p.sort_order,
  case
    when cs.candidate_count = 1 then 'matched'
    when cs.candidate_count = 0 then 'nickname_missing'
    else 'duplicate_needs_check'
  end,
  case
    when cs.candidate_count = 1 then cs.matched_login_id
    when cs.candidate_count = 0 then 'no active profile matched by name and parish'
    else cs.candidate_logins
  end,
  cs.candidate_profiles
from prepared p
join candidate_summary cs on cs.sort_order = p.sort_order
order by p.sort_order;

notify pgrst, 'reload schema';

commit;
