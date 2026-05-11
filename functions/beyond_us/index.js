// /beyond_us/ 요청 시 app.htmldata 본문을 ASSETS에서 가져와 HTML로 반환
// (CF Pages가 .html 정규화로 350KB 디렉토리 인덱스 서빙에 500 내는 문제 우회)
export async function onRequestGet(context) {
  const url = new URL(context.request.url);
  url.pathname = '/beyond_us/app.htmldata';
  const res = await context.env.ASSETS.fetch(url);
  return new Response(res.body, {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=0, must-revalidate',
    },
  });
}
