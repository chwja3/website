const CACHE = 'beyondus-20260514p';
const ASSETS = [
  './',
  './index.html',
  './app.html',
  './app.css',
  './app.js',
  './manifest.json',
  './images/pabicon.png',
  './images/pabicon_180.png',
  './images/pabicon_192.png',
  './images/pabicon_512.png',
  './images/pabicon_maskable_192.png',
  './images/pabicon_maskable_512.png',
  './images/hc_illust1.png',
  './images/hc_logo_png2.png',
  './images/BEYONDUS2.png',
  './images/hc_illust4.png',
  './images/hc_logo_png1.png',
  './images/앤카드뒷면최종.png',
  './images/앤카드팩디자인배경제거.png',
  './images/앤뒷모습.png',
  './images/sheep.png',
  './images/앤카드사랑최최종.png',
  './images/앤카드희락최최종.png',
  './images/앤카드화평최최종.png',
  './images/앤카드오래참음최최종.png',
  './images/앤카드자비최최종.png',
  './images/앤카드양선최최종.png',
  './images/앤카드충성최최종.png',
  './images/앤카드온유최최종.png',
  './images/앤카드절제최최종.png',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c =>
      Promise.all(ASSETS.map(a => c.add(a).catch(() => {})))
    ).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  // 진입점 HTML은 항상 네트워크 우선 → 캐시 갱신 보장
  if (url.pathname.endsWith('/') || url.pathname.endsWith('index.html') || url.pathname.endsWith('app.html')) {
    e.respondWith(
      fetch(e.request).then(res => {
        const clone = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, clone));
        return res;
      }).catch(() => caches.match(e.request))
    );
    return;
  }
  e.respondWith(
    caches.match(e.request).then(r => r || fetch(e.request))
  );
});
