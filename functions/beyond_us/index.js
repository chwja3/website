// /beyond_us/ 요청 시 app.html 본문을 ASSETS에서 직접 가져와 반환 (CF .html 정규화 우회)
export async function onRequestGet(context) {
  const url = new URL(context.request.url);
  url.pathname = '/beyond_us/app.html';
  const res = await context.env.ASSETS.fetch(url);
  return new Response(res.body, {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=0, must-revalidate',
    },
  });
}
