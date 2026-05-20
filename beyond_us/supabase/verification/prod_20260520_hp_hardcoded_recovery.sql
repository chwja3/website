-- ?? GAS ???? H&P ????? Supabase H&P ?? ???? ??? ????.
begin;

alter table public.hold_pray_entries
  add column if not exists owner_name_input text;

comment on column public.hold_pray_entries.owner_name_input is '???? ??? ??? ?? ??? ??. ???? ? ???? ????? ?? ????.';

create or replace function public.bu_hp_answer_key(p_text text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(btrim(coalesce(p_text, '')), '[[:space:]]+', '', 'g'));
$$;

create temp table tmp_legacy_hold_pray_entries on commit drop as
select
  legacy_no::integer,
  nullif(btrim(owner_name), '') as owner_name,
  nullif(btrim(parish), '') as parish,
  btrim(content) as content,
  coalesce(anonymous, false) as anonymous,
  nullif(btrim(nickname), '') as nickname
from jsonb_to_recordset($legacy_hp$
[
  {
    "legacy_no": 1,
    "owner_name": "권혜민",
    "parish": "1청",
    "content": "저의 달란트를 이용해서 섬길 수 있는, 저의 마음을 움직이는 저의 강도 만난 자를 찾을 수 있게 해주세요.",
    "anonymous": false,
    "nickname": "hedy"
  },
  {
    "legacy_no": 2,
    "owner_name": "김도원",
    "parish": "1청",
    "content": "학업이 잘 풀리게 해주세요.",
    "anonymous": false,
    "nickname": "do1bii"
  },
  {
    "legacy_no": 3,
    "owner_name": "김이수",
    "parish": "1청",
    "content": "고립되지 않게 도와주십시오. 모든 상황 속에서 오래참음을 지켜낼 수 있기를 기도합니다. :)",
    "anonymous": false,
    "nickname": "oosimik"
  },
  {
    "legacy_no": 4,
    "owner_name": "김주와",
    "parish": "1청",
    "content": "교회보다 세상의 일과 삶이 우선시되지 않도록, 바쁜 일주일을 보내도 교회에 나올 수 있는 체력을 유지할 수 있도록.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 5,
    "owner_name": "박교은",
    "parish": "1청",
    "content": "정신과 육체의 건강을 위해. 하나님이 주신 사명과 길, 삶의 목적을 깨닫고 발견할 수 있도록(진정으로 좋아하는 것이 무엇인지). 사랑으로 주변 사람들을 대할 수 있도록. 흔들리지 않는 마음 주시도록. 하나님을 삶의 중심에 두고 항상 감사하는 마음으로 살 수 있도록.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 6,
    "owner_name": "성예림",
    "parish": "1청",
    "content": "수련회의 모든 과정에서 하나님의 사랑과 은혜를 느낄 수 있도록.",
    "anonymous": false,
    "nickname": "yesyeslim"
  },
  {
    "legacy_no": 7,
    "owner_name": "손희성",
    "parish": "1청",
    "content": "마음의 중심이 하나님께 있을 수 있도록.",
    "anonymous": false,
    "nickname": "hs"
  },
  {
    "legacy_no": 8,
    "owner_name": "이기중",
    "parish": "1청",
    "content": "우리 가족이 하나님의 축복 아래 있게 해주세요.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 9,
    "owner_name": "장현준",
    "parish": "1청",
    "content": "주님의 자녀로서 주님이 주신 길 안에서 부끄럼 없이 당당히 살아갈 수 있도록 기도해주세요.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 10,
    "owner_name": "전지호",
    "parish": "1청",
    "content": "건강할 수 있도록 해주세요.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 11,
    "owner_name": "조인택",
    "parish": "1청",
    "content": "남은 2026년도 잘 보내게 해주세요.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 12,
    "owner_name": "조현민",
    "parish": "1청",
    "content": "졸업작품 준비 잘해서 잘 졸업할 수 있도록. 내 기도에 대한 응답을 들을 수 있도록 하나님과 가까워지고 싶음.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 13,
    "owner_name": "최지호",
    "parish": "1청",
    "content": "좋을 때도 나쁠 때도 하나님께 의지할 수 있도록. 좋은 일에도 나쁜 일에도 감사하며 예비하신 것들을 고대할 수 있도록.",
    "anonymous": false,
    "nickname": "지호초이"
  },
  {
    "legacy_no": 14,
    "owner_name": "유광훈",
    "parish": "1청(사역자)",
    "content": "수련회가 참석한 청년 모두에게 하나님을 만나는 시간 되기를. 다치고 아픈 사람 없게 해주세요. 저도 은혜받는 수련회되게 해주세요.",
    "anonymous": false,
    "nickname": "나는전도사다"
  },
  {
    "legacy_no": 15,
    "owner_name": null,
    "parish": "2청",
    "content": "남자친구에게 하나님의 믿음이 생길 수 있게 도와주세요.",
    "anonymous": true,
    "nickname": null
  },
  {
    "legacy_no": 16,
    "owner_name": "권영서",
    "parish": "2청",
    "content": "땅에 떨어지지 않는 온전한 믿음, 소망, 사랑이 나와 우리공동체 안에 충만할 수 있길.",
    "anonymous": false,
    "nickname": "수소는엣취"
  },
  {
    "legacy_no": 17,
    "owner_name": "금강현",
    "parish": "2청",
    "content": "1. 사랑하는 형제자매들이 수련회에서 큰은혜를 받아 개개인이 세상의 큰 나무가 되길 원합니다. 2. 교회에 넘치는 성령과 사랑이 세상의 낮은곳으로 흘러가 주님의 큰일에 쓰이는 도구가 되길 원합니다. 3. 개인적으로 준비하는 자격증시험이 주님이 준비하신 길에 부합하길 원합니다.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 18,
    "owner_name": "김응현",
    "parish": "2청",
    "content": "30대가 되기 전 인생의 방향을 잡게 해주세요~!",
    "anonymous": false,
    "nickname": "김응현"
  },
  {
    "legacy_no": 19,
    "owner_name": "김정아",
    "parish": "2청",
    "content": "하나님의 인도하심을 기도하며 진로준비할 수 있기를, 하루하루 최선을 다하길.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 20,
    "owner_name": "김준희",
    "parish": "2청",
    "content": "올해 안으로 준비하고 있는 일들 잘 되게 해주세요. 1. 두 달 간에 수능공부 포기하고 편입영어 준비 후회없이 할 수 있게(토익) 2. 8월에 있는 누나의 경찰 시험 마지막 준비 이루어지길 바랍니다. 3. 부모님 별탈없이 건강기도 4. 2027 나의 첫 연애 기도 5. 벤치 1rm 100kg 올해 안으로 달성하기.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 21,
    "owner_name": "김지원",
    "parish": "2청",
    "content": "1. 엄마의 정신 건강의 회복 2. 가물어 메마른 땅과 같은 마음에 성령님 임하시도록 3. 매 순간 만나는 한 사람에게 사랑을 넘치게 부어줄 수 있도록",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 22,
    "owner_name": "김태훈",
    "parish": "2청",
    "content": "이 땅에서의 삶이 끝날 때까지, 끝까지 빛의 선한 길을 걸어갈 수 있도록 기도 부탁드립니다. 사랑합니다.",
    "anonymous": false,
    "nickname": "yraisemeup"
  },
  {
    "legacy_no": 23,
    "owner_name": "김하은",
    "parish": "2청",
    "content": "경찰 시험, 건강 회복(발목, 허리), 인류애, 동생의 진로.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 24,
    "owner_name": "김해솔",
    "parish": "2청",
    "content": "1. 할머니가 많이 아픈 가운데 고통없이 편안히 주님의 품에 안기길. 2. 좋은 직장으로 이끌어주시길. 3. 좋은 인연을 맺어주시길,",
    "anonymous": false,
    "nickname": "해솔"
  },
  {
    "legacy_no": 25,
    "owner_name": "김현",
    "parish": "2청",
    "content": "모든 사람들이 행복이라는 단어를 통해 주님 앞으로 나아갈 수 있도록 기도 드립니다.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 26,
    "owner_name": "문지수",
    "parish": "2청",
    "content": "예수님의 일하심을 더욱 기대하기. 더 큰 믿음 갖기.",
    "anonymous": false,
    "nickname": "moonearth0"
  },
  {
    "legacy_no": 27,
    "owner_name": "박세은",
    "parish": "2청",
    "content": "매 순간 하나님을 잊지 않고 하나님의 뜻을 구하며, 하나님 앞에서 부끄럽지 않은 자녀로 살아가게 해주세요.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 28,
    "owner_name": "서가영",
    "parish": "2청",
    "content": "처음 QT 시작했을 때처럼 열심히 QT 하게 해주시고 수련회 때처럼 기도도 열심히 하게 해주시고 저를 만난 사람들, 제가 다가간 사람들이 예수를 알고, 믿고, 의지하게 해주세요.",
    "anonymous": false,
    "nickname": "고옹2청고옹"
  },
  {
    "legacy_no": 29,
    "owner_name": "서다빈",
    "parish": "2청",
    "content": "주변의 소중한 사람들이 주님을 믿게 될 수 있도록 그 과정에서 쓰임 받을 수 있는 내 자신이 될 수 있기를",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 30,
    "owner_name": "서채운",
    "parish": "2청",
    "content": "버티는 힘과 붙드는 손길 주시도록",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 31,
    "owner_name": "석상은",
    "parish": "2청",
    "content": "저와 가족들의 마음속에 평안을 주세요.",
    "anonymous": false,
    "nickname": "석상"
  },
  {
    "legacy_no": 32,
    "owner_name": "여인규",
    "parish": "2청",
    "content": "하나님과 동행하는 삶이 되기를.",
    "anonymous": false,
    "nickname": "여인규"
  },
  {
    "legacy_no": 33,
    "owner_name": "유하영",
    "parish": "2청",
    "content": "1. 항상 어떠한 상황에서도 우선순위를 주님께 둘 것을 지킬 것! 2. 주변에 믿지 않는 영혼들을 전도할 수 있도록 믿음으로 기도하며 나아갈 것.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 34,
    "owner_name": "유하은",
    "parish": "2청",
    "content": "1. 맡겨진 공동체를 위한 중보자로 세워지기를. 가정, 교회(유치부, 청년, 루티드), 직장, 원주, 동역자들. 2. 일상의 모든 순간에서 예배함을 배워가길. 자고 일어나는 것, 먹고 마시는 것, 일하는 것, 관계 맺는 것 모두 주님의 영광을 위하여!",
    "anonymous": false,
    "nickname": "ㅇㅎㅇ"
  },
  {
    "legacy_no": 35,
    "owner_name": "이강산",
    "parish": "2청",
    "content": "세계 평화'",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 36,
    "owner_name": "이주광",
    "parish": "2청",
    "content": "세상 일에 대한 염려를 놓을 수 있기를. 하나님 나라를 위한 기도와 소망으로 가득찬 나날을 보낼 수 있기를 기도합니다.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 37,
    "owner_name": "이현기",
    "parish": "2청",
    "content": "1. 하루 빨리 취업이 되길! 2. 동생이 여름부터 유학을 가는데 가서도 믿음 생활 잘 유지하길! 3. 이번 수련회를 통하여서 하나님의 더 크신 뜻을 알아가길!",
    "anonymous": false,
    "nickname": "햇님달님"
  },
  {
    "legacy_no": 38,
    "owner_name": "임다혜",
    "parish": "2청",
    "content": "1.친동생(임서준) 하나님 믿고 예수님 영접하길. 2.남편(서현덕,3청)과 서로 사랑하고 존중하며 오직 하나님만 섬기는 가정 세워나가길. 3. 졸업준비(6월 디펜스, 학위논문) 성실하게 잘 해내길 4. 졸업 이후 취업. 이끄시고 보내주시는 곳으로 가서 그 곳에서 예배할 수 있길. 5. 수련회 통해 하나님과 더 깊은 교제, 할 수 있길.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 39,
    "owner_name": "임서경",
    "parish": "2청",
    "content": "하나님의 예비하심을 믿고 살아갈 수 있도록 해주세요!",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 40,
    "owner_name": "장한나",
    "parish": "2청",
    "content": "하나님의 사랑으로 가득 채워지는 수련회가 되길 기도합니다.",
    "anonymous": false,
    "nickname": "장한나"
  },
  {
    "legacy_no": 41,
    "owner_name": "정대호",
    "parish": "2청",
    "content": "나의 힘으로 하려고 하기보다 하나님께 맡겨드릴 수 있게 + 할머니, 할아버지 영혼 구원.",
    "anonymous": false,
    "nickname": "콘푸로스트1"
  },
  {
    "legacy_no": 42,
    "owner_name": "조학준",
    "parish": "2청",
    "content": "새로운 환경에 적응하고 있는 가운데, 걱정되고 불안한 일들이 많지만 나를 '사랑'하시는 주님의 함께하심을 믿고 잘 적응해가길 바랍니다.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 43,
    "owner_name": "지윤성",
    "parish": "2청",
    "content": "1. 세상의 신(돈, 사람들의 인정)이 아니라 하나님만 온전히 사랑할 수 있길 2. 사람을 만나고 대할 때에 필요한 지혜와 사랑의 마음을 주시기를. 3. 수면시간이 부족한데, 건강과 체력을 위하여.",
    "anonymous": false,
    "nickname": "공도리곰도리"
  },
  {
    "legacy_no": 44,
    "owner_name": "최가은",
    "parish": "2청",
    "content": "하나님 성품을 더 닮아가고 싶어요. 제 안에 주님의 사랑이 더 가득해지도록 도와주세요.",
    "anonymous": false,
    "nickname": "벳딸랑구"
  },
  {
    "legacy_no": 45,
    "owner_name": "최보슬",
    "parish": "2청",
    "content": "1. 매 순간 하나님이 우선이길 2. 삶의 예배가 회복되길",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 46,
    "owner_name": "한정인",
    "parish": "2청",
    "content": "하나님을 믿지 않는 사랑하는 사람들이 예수님의 사랑을 알아봐주길.",
    "anonymous": false,
    "nickname": "한정인"
  },
  {
    "legacy_no": 47,
    "owner_name": "홍수연",
    "parish": "2청",
    "content": "속해있는 공동체가 사랑으로 넘치도록",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 48,
    "owner_name": "임동표",
    "parish": "2청(사역자)",
    "content": "수련회를 기도하며 준비하고 기쁘게 청년들을 섬길 수 있도록. 한 영혼도 놓치지 않고 끝까지 사랑으로 붙들 수 있도록 기도해주세요.",
    "anonymous": false,
    "nickname": "나는목사다"
  },
  {
    "legacy_no": 49,
    "owner_name": "곽지섭",
    "parish": "3청",
    "content": "대학원 학위과정 중에 하나님의 계획과 인도하심을 경험할 수 있도록.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 50,
    "owner_name": "김승현",
    "parish": "3청",
    "content": "주님, 장인어른을 교회로 오게 하시니 감사드립니다. 아내의 순산도 믿습니다. 10분컷 순산.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 51,
    "owner_name": "김아현",
    "parish": "3청",
    "content": "불안해하거나 조급해하지 않길. 주변을 돌아보고 더 사랑할 수 있길. 계속 진행 중이지만 잘 해결되길. 진심으로 주님께 맡길 수 있길.",
    "anonymous": false,
    "nickname": "애용"
  },
  {
    "legacy_no": 52,
    "owner_name": "김영진",
    "parish": "3청",
    "content": "염려, 불안, 걱정이 아닌 하나님의 사랑으로 세상이 줄 수 없는 평안 가운데 살아갈 수 있도록. 우리 가정이 하나님의 사랑으로 충만하여 그 사랑을 주위로 흘려보낼 수 있도록.",
    "anonymous": false,
    "nickname": "초코맛꼬북칩"
  },
  {
    "legacy_no": 53,
    "owner_name": "김은정",
    "parish": "3청",
    "content": "믿음의 가정. 나만을 위함이 아닌 주변을 위한 믿음이 되길.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 54,
    "owner_name": "김지훈",
    "parish": "3청",
    "content": "성령 충만.",
    "anonymous": false,
    "nickname": "김지훈D"
  },
  {
    "legacy_no": 55,
    "owner_name": "김효정",
    "parish": "3청(2청?)",
    "content": "1. 가족의 건강 지켜주시길 2. 동생의 편입 준비 함께해주시길 3. 법인 지원 고민에 답을 주셨으면 4. 일을 하면서 신앙과 타협해야 하는 경우가 있는데, 그러한 상황을 현명하게 헤쳐나갈 수 있길. 5. 사랑하는 친구들이 주님을 만날 수 있길.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 56,
    "owner_name": "박민혁",
    "parish": "3청",
    "content": "1. 웃는 삶 살기 2. 건강하기 3. 쿵후 잘하기 이 모든 것을 주님 안에서 이룰 수 있기를 기도합니다.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 57,
    "owner_name": "서현덕",
    "parish": "3청",
    "content": "제 시선이 항상 주님을 향하고, 성령님과 동행하며, 삶이 예배가 되게 하소서. 저희 가족이 주님을 경배하게 하시고, 하나님께서 기뻐하시는 공동체가 되게 하소서. 아직 주위에 믿지 않는 지체들이 많습니다. 하나님의 계획대로 그들이 교회로 올 수 있기를 간절히 기도합니다.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 58,
    "owner_name": "안성재",
    "parish": "3청",
    "content": "하나님께서 허락하신 가정과 교회와 직장에서 주님 다시 오실 길을 예비하는 예배자로 서게 하시고, 깨끗하고 순전한 마음으로 맡겨진 자리마다 충성할 수 있도록 기도해 주세요. 감사합니다.",
    "anonymous": false,
    "nickname": "카니보어시즌2"
  },
  {
    "legacy_no": 59,
    "owner_name": "양찬미",
    "parish": "3청",
    "content": "주의 권능의 날에 주의 백성이 거룩한 옷을 입고 즐거이 헌신하니 새벽이슬 같은 주의 청년들이 주께 나오는도다(시 110:3) 큰은혜 아름다운 청년들을 주님의 이름으로 축복합니다.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 60,
    "owner_name": "영빈",
    "parish": "3청",
    "content": "무릎 회복",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 61,
    "owner_name": "윤시환",
    "parish": "3청",
    "content": "제 삶의 계획을 가지고 계신 주님과 더욱 가까워질 수 있기를 기도합니다.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 62,
    "owner_name": "윤영록",
    "parish": "3청",
    "content": "가족과 가까운 친구들이 예수님을 아직 모릅니다. 하나님께서 콜링하실 때 응답하기를... 내게 맡겨진 영혼들을 더욱 힘써 섬길 수 있기를~.",
    "anonymous": false,
    "nickname": "영화로운 사슴"
  },
  {
    "legacy_no": 63,
    "owner_name": "이원철",
    "parish": "3청",
    "content": "선교가게 해주세요ㅠㅠ",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 64,
    "owner_name": "이은서",
    "parish": "3청",
    "content": "그냥 살 수 있기를.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 65,
    "owner_name": "이지은",
    "parish": "3청",
    "content": "가족의 평안. 큰오빠의 건강 회복. 졸업 연구와 체력. 믿음의 가정을 이룰 배우자.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 66,
    "owner_name": "이찬영",
    "parish": "3청",
    "content": "하나님이 원하시는 삶이 무엇인지 알도록. 기쁘고 평안.",
    "anonymous": false,
    "nickname": "고양이"
  },
  {
    "legacy_no": 67,
    "owner_name": "이평화",
    "parish": "3청",
    "content": "미래에 대한 염려가 아닌 현재에 최선을 다하고 집중할 수 있기를, 먼저 그의 나라와 그의 의를 구하게 하소서.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 68,
    "owner_name": "전도현",
    "parish": "3청",
    "content": "스스로 흔들리지 않고 항상 하나님 우선으로 중심을 잡고 살 수 있도록.",
    "anonymous": false,
    "nickname": "SingSangSong"
  },
  {
    "legacy_no": 69,
    "owner_name": "정혜진",
    "parish": "3청",
    "content": "내 신앙에 흔들림 없게 해주시고 내 신앙으로 인해 힘든 것이 아니라 위로를 받을 수 있도록 해주세요.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 70,
    "owner_name": "조연주",
    "parish": "3청",
    "content": "중심이 하나님이 되어 살아갈 수 있도록 해주세요. 사랑을 베풀 수 있도록 사랑으로 가득찬 마음을 주세요. 내가 가고자 하는 방향이 아닌 주님의 방향대로 잘 이끌어 주세요.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 71,
    "owner_name": "주찬형",
    "parish": "3청",
    "content": "1. 십자가 보혈의 은혜에 감사하며, 삶의 현장에서 예수님의 제자로 복음을 전하게 하소서 2. 합창단 정단원 합격과 국립합창단 청년단원 생활의 유종의 미를 거두게 하소서.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 72,
    "owner_name": "천신원",
    "parish": "3청",
    "content": "1. 일상에서 하나님의 사랑을 실천하고 주님과 항상 동행할 수 있도록 도와주세요. 2. 좋은 가정을 꾸릴 수 있도록 도와주세요.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 73,
    "owner_name": "최한나",
    "parish": "3청",
    "content": "함께 하나님의 일꾼으로 쓰임 받으며 믿음의 가정을 함께 세워나갈 배우자를 위해 기도합니다.",
    "anonymous": false,
    "nickname": "한나둘셋넷"
  },
  {
    "legacy_no": 74,
    "owner_name": "황주원",
    "parish": "3청",
    "content": "1. 힘들 때일 수록 더욱 하나님과 가까이 하는 삶이 되기를. 2. 유아부 봉사를 좀 더 믿음으로 실천하기를 3. 언니의 가정이 다시 하나님을 섬기고 가까운 교회에서 신앙생활 하기를 4. 육신의 건강... (나와 가족, 친구... 주변인들 모두...)",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 75,
    "owner_name": "J",
    "parish": "4청",
    "content": "주님의 사랑과 시선으로 공동체를 바라보고 섬길 수 있게 해주세요 거룩하고 정결하게 살아가게 하시고 주님의 영광을 위해 온전히 쓰임 받는 삶을 살게 해주세요",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 76,
    "owner_name": "404팀",
    "parish": "4청",
    "content": "하나님이 나를 사랑하신다는 사실을 늘 기억하고 스스로를 사랑하길, 무엇을 하더라도 나의 생각과 판단이 아닌 하나님을 먼저 떠올릴 수 있기를, 논문 심사를 준비하는 과정에서 지혜를 주시고 마음에 평안함을 주시길, 우리 강아지가 조금만 덜 아프고 건강하게 말년을 보내게 도와주세요, 직장 문제...아시죠 하나님이 방식대로 잘 해결되게 해주세요.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 77,
    "owner_name": "김광희",
    "parish": "4청",
    "content": "AGC 청년 수련회 함께하는 청년들이 은혜와 감사가 가득하도록. 나의 시선이 주님께, 나의 것을 내려놓고 말씀 속 주님을 바라보는 예배자로 지혜와 은혜 더해주소서. 다른 것 근심, 염려 속지 않고 주님의 일하심을 믿고 행함이 있는 믿음 속에 살아가도록.",
    "anonymous": false,
    "nickname": "광광"
  },
  {
    "legacy_no": 78,
    "owner_name": "김동욱",
    "parish": "4청",
    "content": "1. 좋은 배우자, 믿음의 배우자 만나도록 2. 믿음이 성장하고 복음 전파에 힘쓰도록 3. 하나님의 자녀로 그 신분에 걸맞게 살아가고, 하나님 뜻이 나의 뜻이 되는 삶이 되기를.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 79,
    "owner_name": "김민희",
    "parish": "4청",
    "content": "이직한 직장에 잘 적응할 수 있기를! 성가대 여호수아를 기쁘게 잘 섬기게 해주세요. 사람과의 관계에서 상처받지 않고 항상 감사하며 겸손하게 섬기게! 기도 드립니다.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 80,
    "owner_name": "김진웅",
    "parish": "4청",
    "content": "1. 하나님과 동행하는 내가 될 수 있도록 2. 새로 시작하는 일들 잘 해낼 수 있도록 3. 몸도 마음도 건강한 내가 될 수 있도록 4. 나와 타인 모두 용납하고 사랑할 수 있도록",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 81,
    "owner_name": "문진우",
    "parish": "4청",
    "content": "1. 비전을 보여 주십시오 2. 염려하는 부분이 있는데 하나님 뜻대로 될 수 있게 3. 눈(시력) 회복",
    "anonymous": false,
    "nickname": "문진우"
  },
  {
    "legacy_no": 82,
    "owner_name": "박성온",
    "parish": "4청",
    "content": "수련회를 기대하는 마음으로 준비, 하나님께서 주시는 지혜를 간구하며, 겸손히 준비할 수 있도록!",
    "anonymous": false,
    "nickname": "on"
  },
  {
    "legacy_no": 83,
    "owner_name": "박현우",
    "parish": "4청",
    "content": "1. 가정의 화평과 발전, 새로운 생활을 위해 2. 맡은 학생들 심신이 건강하게 올해 보내고, 발전해가는 한해 되기를 3. 남동생이 이뤄갈 새 가정에도 하나님의 복이 있기를 4. 부모님 건강하게 신앙생활 잘 이어가시기를",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 84,
    "owner_name": "서지원",
    "parish": "4청",
    "content": "1. 미국생활 잘 적응하고 안전하게 다녀오기 2. 모든 연구 결과를 통해 하나님 기쁨 되길! 3. 미국에서도 신앙생활 잘하기! 4. 배우자기도",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 85,
    "owner_name": "유하진",
    "parish": "4청",
    "content": "하나님께서 제게 주신 기업을 열심히 일구어서 하나님께 영광 돌릴 수 있도록 해주세요! 하루하루 성실하게 최선을 다해 살아갈 수 있도록 건강 허락해주세요. 좋은 믿음의 배우자를 허락해주세요. -사랑하는 하진-",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 86,
    "owner_name": "유한나",
    "parish": "4청",
    "content": "1. 부모님 건강 2. 개인의 발전 3. 주변 비기독교인 지인들의 삶속에 주님 들어가셔서 만나주시길 4. 꾸준한 신앙생활",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 87,
    "owner_name": "유형준",
    "parish": "4청",
    "content": "가족 모두 건강하도록. 솜이(강아지)가 건강하기를 기도해주세요.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 88,
    "owner_name": "이가희",
    "parish": "4청",
    "content": "바쁜 5월 주님 주시는 지혜와 체력으로 잘 감당하기를. 나의 필요를 아시는 주님을 믿고 염려하지 않고 더욱 기도하는 예배자 되기를.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 89,
    "owner_name": "이성영",
    "parish": "4청",
    "content": "하나님과 더 가까워지고 우리 팀(셀)이 더 신앙의 성숙이 되었으면 좋겠습니다.",
    "anonymous": false,
    "nickname": "이썽"
  },
  {
    "legacy_no": 90,
    "owner_name": "이성호",
    "parish": "4청",
    "content": "누나의 건강과 하는 일들이 잘 풀리고 행복만 가득하기를",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 91,
    "owner_name": "이세희",
    "parish": "4청",
    "content": "마음의 기쁨과 평안함 주시기를 원합니다. 작은 것에 감사하는 자 되기를 원합니다. 늘 주님과 동행할 수 있기를 원하고 주님의 동행하심을 느끼는 자 되기를 원합니다. 하나님의 축복하심이 넘치길 소망합니다. 가정과 주변 사람들의 건강 지켜주시고 주님 안에서 모두 하나 되기를 소원합니다.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 92,
    "owner_name": "임하련",
    "parish": "4청",
    "content": "강건하고 평안하고 형통하고 맡은 바를 잘하고 가족이 모두 강건하기를.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 93,
    "owner_name": "전승훈",
    "parish": "4청",
    "content": "가족의 건강. 2세 만들기. 대학원 무사졸업. 여호수아 찬양대의 번영.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 94,
    "owner_name": "정다운",
    "parish": "4청",
    "content": "올해 성경 1독할 수 있게. 하나님과 더 가까워지고 잠깐 불타는 신앙이 아닌 평생 이어질 수 있도록. 믿음의 결실을 함께 나눌 배우자를 만날 수 있게 해주세요. 새벽기도 드리는 청년이 100명이 될 수 있게 부흥하길!!",
    "anonymous": false,
    "nickname": "댜니"
  },
  {
    "legacy_no": 95,
    "owner_name": "천혜영",
    "parish": "4청",
    "content": "우리 가정에 뜻하신 일을 알게 하소서. 슬픔에 잠기지 않고 천국 소망 바라보며 날마다 감사하고 기뻐하는 삶이 되게 하소서. 나의 삶의 중심이 예배가 되게 하소서. 우리 팀원들의 삶속에 주의 인도하심을 통해 평안과 기쁨이 넘치게 하소서.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 96,
    "owner_name": "최지호",
    "parish": "4청",
    "content": "지성이(친동생)과 처남이 교회에 등록하고 하나님을 만나도록 기도해주세요.",
    "anonymous": false,
    "nickname": "지호초이"
  },
  {
    "legacy_no": 97,
    "owner_name": "허경웅",
    "parish": "4청",
    "content": "1. 글쓰는 것을 좋아합니다. 문학공모전 등에서 수상 또는 책을 발간하는 기회가 오길. 2. 영어 등 외국어 공부 중입니다.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 98,
    "owner_name": "허완",
    "parish": "4청",
    "content": "1. 연애하게 해주세요 2. 학업 무사히 마치게 해주세요 3. 건강하고 지치지 않게 운동,컨디션 관리 잘하기 4. 꾸준히 신앙생활 잘 하기, 나태해지지 않기.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 99,
    "owner_name": "이정실",
    "parish": "목양3교구",
    "content": "우리 교회 모든 성도님들과 주위 이웃들이 아프지 않고 건강하기를 기도합니다! 청년들이 희망 잃지 않고 행복하기를!",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 100,
    "owner_name": "최혜선",
    "parish": "목양3교구",
    "content": "1. 김경호집사(남편)가 예배를 잘 드렸으면 좋겠습니다(소년부 교사 후, 대예배 안드림). 2. 김이삭(아이)가 밥을 스스로 잘 먹고 즐거워했으면 좋겠습니다.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 101,
    "owner_name": null,
    "parish": "*미기입",
    "content": "하나님을 삶에 우선순위로 둘 수 있도록. 진로를 잘 인도해 주시기를. 예쁜 가정도 이룰 수 있도록.",
    "anonymous": true,
    "nickname": null
  },
  {
    "legacy_no": 102,
    "owner_name": null,
    "parish": "*미기입",
    "content": "지치지 않고 주어진 것들을 감당할 힘과 지혜를 주시길, 앞으로 나아갈 용기를 불어넣어 주시길.",
    "anonymous": true,
    "nickname": null
  },
  {
    "legacy_no": 103,
    "owner_name": null,
    "parish": "*미기입",
    "content": "서울 생활 잘 적응하고 믿음 생활 잘 하도록 도와주세요.",
    "anonymous": true,
    "nickname": null
  },
  {
    "legacy_no": 104,
    "owner_name": null,
    "parish": "*미기입",
    "content": "새로운 분야를 공부할 때 지혜를 주시고 주님의 영광을 빛낼 일이 되길",
    "anonymous": true,
    "nickname": null
  },
  {
    "legacy_no": 105,
    "owner_name": null,
    "parish": "*미기입",
    "content": "항상 건강하기 졸업 잘할 수 있도록 열심히 하기",
    "anonymous": true,
    "nickname": null
  },
  {
    "legacy_no": 106,
    "owner_name": "LLIKE",
    "parish": "*미기입",
    "content": "Hope, I can always predict three steps ahead and make the right choice everytime.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 107,
    "owner_name": "김노현",
    "parish": "*미기입",
    "content": "몇 년 만에 교회를 다시 등록하게 되었습니다. 믿음 회복, 신앙생활 적응 잘할 수 있도록 기도합니다.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 108,
    "owner_name": "김예지",
    "parish": "*미기입",
    "content": "가족들의 건강회복",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 109,
    "owner_name": "김준범",
    "parish": "*미기입",
    "content": "업무가 상당히 바쁜 와중에 지혜롭게 해결해나갈 수 있게 인도하여 주시길. 고난의 순간을 주님이 예비하신 길로 보게 하시고, 믿고 나아가길.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 110,
    "owner_name": "김지수",
    "parish": "*미기입",
    "content": "원하는 목표를 이루게 되길. 하나님을 더 바라보게 되길. 기도를 더 많이하고 들어주시길.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 111,
    "owner_name": "유진키티",
    "parish": "*미기입",
    "content": "지금부터 1년 반 이내로 하고싶어 한 일(취업) 달성 주변에 좋은 사람들만 있길, 가족과 나의 건강",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 112,
    "owner_name": "윤갑식",
    "parish": "*미기입",
    "content": "하나님께서 기뻐하시는 청년들 믿음을 더하시고 항상 동행해주셔서 하나님의 귀한 일꾼들 되게 하소서.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 113,
    "owner_name": "이다현",
    "parish": "*미기입",
    "content": "교생실습기간 체력적으로 너무 지치지 않도록.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 114,
    "owner_name": "정하은",
    "parish": "*미기입",
    "content": "원하는 회사에 취업할 수 있도록 지혜와 끈기를 주세요.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 115,
    "owner_name": "천은경",
    "parish": "*미기입",
    "content": "하나님 나라를 소망할 수 있기를. 사랑할 수 있는 마음을 주시기를.",
    "anonymous": false,
    "nickname": null
  },
  {
    "legacy_no": 116,
    "owner_name": "최승원",
    "parish": "*미기입",
    "content": "주님, 인도해주신 사명에 따라 결식아동을 돕기 위해 시작한 저의 활동이 현실적인 그리고 금전적인 문제로 더 이상 이어나아가기 힘들어졌습니다. 부족하고 인도해주신 사명을 끝까지 완수하지 못했다는 죄책감과 좌절이 저를 묶어놓고 있습니다. 죄송하다고 말씀 드리고 싶었어요. 더 잘하고 싶었습니다. 그래도 저를 위로해주심에 정말 감사드립니다.",
    "anonymous": false,
    "nickname": null
  }
]
$legacy_hp$::jsonb) as x(
  legacy_no integer,
  owner_name text,
  parish text,
  content text,
  anonymous boolean,
  nickname text
);

alter table tmp_legacy_hold_pray_entries
  add primary key (legacy_no);

create temp table tmp_legacy_hp_content_dupes on commit drop as
select public.bu_hp_answer_key(content) as content_key, count(*)::integer as legacy_count, array_agg(legacy_no order by legacy_no) as legacy_rows
from tmp_legacy_hold_pray_entries
group by public.bu_hp_answer_key(content)
having count(*) > 1;

create temp table tmp_legacy_hp_existing_match on commit drop as
select
  l.legacy_no,
  h.id as entry_id,
  count(*) over (partition by l.legacy_no)::integer as existing_count
from tmp_legacy_hold_pray_entries l
join public.hold_pray_entries h
  on public.bu_hp_answer_key(h.content) = public.bu_hp_answer_key(l.content);

create temp table tmp_legacy_hp_profile_match on commit drop as
with nickname_match as (
  select
    l.legacy_no,
    p.id as profile_id,
    p.login_id::text as login_id,
    p.name,
    p.parish
  from tmp_legacy_hold_pray_entries l
  join public.profiles p
    on l.nickname is not null
   and p.account_status = 'active'
   and p.login_id::text = l.nickname
),
name_candidates as (
  select
    l.legacy_no,
    p.id as profile_id,
    p.login_id::text as login_id,
    p.name,
    p.parish
  from tmp_legacy_hold_pray_entries l
  join public.profiles p
    on l.owner_name is not null
   and p.account_status = 'active'
   and public.bu_hp_answer_key(p.name) = public.bu_hp_answer_key(l.owner_name)
),
name_counts as (
  select
    l.legacy_no,
    count(nc.profile_id)::integer as candidate_count,
    coalesce(jsonb_agg(jsonb_build_object(
      'userId', nc.login_id,
      'name', nc.name,
      'parish', nc.parish
    ) order by
      coalesce(array_position(array['1?','2?','3?','4?','VIP','????','????'], nc.parish), 99),
      nc.name,
      nc.login_id
    ) filter (where nc.profile_id is not null), '[]'::jsonb) as candidates
  from tmp_legacy_hold_pray_entries l
  left join name_candidates nc on nc.legacy_no = l.legacy_no
  group by l.legacy_no
),
name_single as (
  select nc.*
  from name_candidates nc
  join name_counts nct on nct.legacy_no = nc.legacy_no and nct.candidate_count = 1
)
select
  l.*,
  coalesce(nm.profile_id, ns.profile_id) as matched_profile_id,
  coalesce(nm.login_id, ns.login_id) as matched_login_id,
  coalesce(nm.name, ns.name) as matched_name,
  coalesce(nm.parish, ns.parish) as matched_parish,
  case
    when nm.profile_id is not null then 'nickname'
    when ns.profile_id is not null then 'name'
    when l.owner_name is null then 'anonymous_or_blank'
    when nct.candidate_count > 1 then 'ambiguous_name'
    else 'not_found'
  end as match_state,
  coalesce(nct.candidate_count, 0) as name_candidate_count,
  coalesce(nct.candidates, '[]'::jsonb) as name_candidates
from tmp_legacy_hold_pray_entries l
left join nickname_match nm on nm.legacy_no = l.legacy_no
left join name_single ns on ns.legacy_no = l.legacy_no
left join name_counts nct on nct.legacy_no = l.legacy_no;

create temp table tmp_legacy_hp_updated on commit drop as
with targets as (
  select
    m.legacy_no,
    em.entry_id,
    m.owner_name,
    m.anonymous,
    m.matched_profile_id,
    m.match_state
  from tmp_legacy_hp_profile_match m
  join tmp_legacy_hp_existing_match em on em.legacy_no = m.legacy_no
),
updated as (
  update public.hold_pray_entries h
  set profile_id = coalesce(t.matched_profile_id, h.profile_id),
      owner_name_input = coalesce(t.owner_name, h.owner_name_input),
      anonymous = t.anonymous,
      visible = true
  from targets t
  where h.id = t.entry_id
  returning t.legacy_no, h.id as entry_id, t.match_state, t.matched_profile_id
)
select * from updated;

create temp table tmp_legacy_hp_inserted on commit drop as
with missing as (
  select m.*
  from tmp_legacy_hp_profile_match m
  where not exists (
    select 1
    from tmp_legacy_hp_existing_match em
    where em.legacy_no = m.legacy_no
  )
),
inserted as (
  insert into public.hold_pray_entries (
    profile_id,
    week_key,
    content,
    anonymous,
    visible,
    owner_name_input
  )
  select
    matched_profile_id,
    null,
    content,
    anonymous,
    true,
    owner_name
  from missing
  returning id as entry_id, content
)
select
  m.legacy_no,
  i.entry_id,
  m.match_state,
  m.matched_profile_id
from missing m
join inserted i
  on public.bu_hp_answer_key(i.content) = public.bu_hp_answer_key(m.content);

do $$
begin
  if to_regprocedure('public.bu_recalculate_hold_pray_guesses(text)') is not null then
    perform public.bu_recalculate_hold_pray_guesses(null);
  end if;
end $$;

notify pgrst, 'reload schema';

select jsonb_pretty(jsonb_build_object(
  'ok', true,
  'source', 'gas_hardcoded_hold_pray_entries',
  'legacyRows', (select count(*) from tmp_legacy_hold_pray_entries),
  'duplicateContentKeys', coalesce((select jsonb_agg(jsonb_build_object('contentKey', content_key, 'legacyRows', legacy_rows) order by content_key) from tmp_legacy_hp_content_dupes), '[]'::jsonb),
  'existingContentMatches', (select count(distinct legacy_no) from tmp_legacy_hp_existing_match),
  'existingDuplicateMatches', coalesce((
    select jsonb_agg(jsonb_build_object('legacyNo', legacy_no, 'existingCount', existing_count) order by legacy_no)
    from (
      select distinct legacy_no, existing_count
      from tmp_legacy_hp_existing_match
      where existing_count > 1
    ) x
  ), '[]'::jsonb),
  'updatedRows', (select count(*) from tmp_legacy_hp_updated),
  'insertedRows', (select count(*) from tmp_legacy_hp_inserted),
  'matchedByNickname', (select count(*) from tmp_legacy_hp_profile_match where match_state = 'nickname'),
  'matchedByName', (select count(*) from tmp_legacy_hp_profile_match where match_state = 'name'),
  'anonymousOrBlankRows', (select count(*) from tmp_legacy_hp_profile_match where match_state = 'anonymous_or_blank'),
  'unmatchedNamedRows', coalesce((
    select jsonb_agg(jsonb_build_object(
      'legacyNo', legacy_no,
      'ownerName', owner_name,
      'parish', parish,
      'nickname', nickname,
      'contentPreview', left(content, 60)
    ) order by legacy_no)
    from tmp_legacy_hp_profile_match
    where match_state = 'not_found'
  ), '[]'::jsonb),
  'ambiguousNameRows', coalesce((
    select jsonb_agg(jsonb_build_object(
      'legacyNo', legacy_no,
      'ownerName', owner_name,
      'parish', parish,
      'nickname', nickname,
      'candidates', name_candidates,
      'contentPreview', left(content, 60)
    ) order by legacy_no)
    from tmp_legacy_hp_profile_match
    where match_state = 'ambiguous_name'
  ), '[]'::jsonb)
)) as hp_hardcoded_recovery_result;

commit;
