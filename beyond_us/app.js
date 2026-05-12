    const DEV_HOSTS = new Set(['dev.website-78h.pages.dev']);
    function isDevEnvironment() {
      const host = location.hostname;
      return location.protocol === 'file:' ||
        host === 'localhost' ||
        host === '127.0.0.1' ||
        DEV_HOSTS.has(host);
    }
    const IS_DEV_ENV = isDevEnvironment();

    const API_BASE = IS_DEV_ENV
      ? 'https://script.google.com/macros/s/AKfycbx4C7oSZv7KLsDJeduJ51Hh3DMFXjibECfwUQsqGdoPOiMebKvqNGypcI0YRapxMJ_cQQ/exec' // DEV GAS
      : 'https://script.google.com/macros/s/AKfycbxwpRSDeXLxaLzvmfJj7zSSTmG0qPykJw_eu-NjtKpLEpgIDyHU3Po3qG5Hl-lg6iTtJg/exec'; // PROD GAS

    const AUTHLESS_ACTIONS = new Set(['login', 'register', 'resetPassword', 'adminLogin']);
    function getSessionToken() {
      return localStorage.getItem('beyondus_session_token') || '';
    }
    function withSession(body) {
      const payload = Object.assign({}, body);
      if (!payload.adminPw && !AUTHLESS_ACTIONS.has(payload.action) && !payload.sessionToken) {
        const token = getSessionToken();
        if (token) payload.sessionToken = token;
      }
      return payload;
    }
    function sessionParam() {
      const token = getSessionToken();
      return token ? `&sessionToken=${encodeURIComponent(token)}` : '';
    }
    function post(body) {
      return fetch(API_BASE, {
        method: 'POST',
        headers: { 'Content-Type': 'text/plain;charset=utf-8' },
        body: JSON.stringify(withSession(body))
      }).then(r => r.json());
    }

    /* ── 버전 체크 (PWA 캐시 강제 갱신) ──
       자동 reload 대신 배너로 알림. 사용자가 직접 새로고침 → SW/캐시 전부 클리어 후 reload.
       자동 reload는 SW가 옛 app.js를 cache-first로 서빙할 때 무한 reload 루프를 만들 수 있어서 제거. */
    const APP_VERSION = '20260512v';
    const MAINTENANCE_MODE = false;
    if (MAINTENANCE_MODE && !IS_DEV_ENV) {
      if ('serviceWorker' in navigator) navigator.serviceWorker.register('./sw.js').catch(() => {});
      document.addEventListener('DOMContentLoaded', () => {
        document.body.innerHTML = `
          <main style="min-height:100vh;display:flex;align-items:center;justify-content:center;padding:28px;background:#faf6ef;color:#2c2417;font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;text-align:center;">
            <section style="max-width:420px;">
              <img src="images/hc_logo_png2.png" alt="Beyond Us" style="width:128px;height:auto;margin-bottom:28px;" />
              <h1 style="font-size:24px;line-height:1.35;margin:0 0 12px;font-weight:850;">잠시 점검 중입니다.</h1>
              <p style="font-size:15px;line-height:1.8;margin:0;color:#6f6254;">더 안정적인 운영을 위해 서버와 데이터를 정리하고 있어요.<br>작업이 끝나면 다시 열어둘게요.</p>
            </section>
          </main>`;
      });
      throw new Error('maintenance_mode');
    }
    (function checkVersion() {
      fetch('./version.txt?_=' + Date.now(), { cache: 'no-store' })
        .then(r => r.text())
        .then(remote => {
          const remoteVer = remote.trim();
          if (remoteVer && remoteVer !== APP_VERSION) {
            console.warn('[DIAG] new version detected. local=', APP_VERSION, 'remote=', remoteVer);
            showUpdateBanner();
          }
        })
        .catch(() => {});
    })();

    function showUpdateBanner() {
      if (document.getElementById('updateBanner')) return; // 중복 방지
      const mount = () => {
        if (!document.body) { setTimeout(mount, 50); return; }
        const banner = document.createElement('div');
        banner.id = 'updateBanner';
        banner.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:99999;background:#7b4fa6;color:#fff;padding:10px 16px;display:flex;align-items:center;justify-content:space-between;gap:12px;font-size:13px;box-shadow:0 2px 8px rgba(0,0,0,0.25);font-family:inherit;';
        banner.innerHTML =
          '<span>새 버전이 있어요. 새로고침해주세요.</span>' +
          '<button id="updateBannerBtn" style="background:#fff;color:#000;border:none;padding:6px 14px;border-radius:6px;font-weight:600;cursor:pointer;font-size:13px;">새로고침</button>';
        document.body.appendChild(banner);
        document.getElementById('updateBannerBtn').onclick = async () => {
          const btn = document.getElementById('updateBannerBtn');
          if (btn) { btn.textContent = '...'; btn.disabled = true; }
          try {
            if ('serviceWorker' in navigator) {
              const regs = await navigator.serviceWorker.getRegistrations();
              await Promise.all(regs.map(r => r.unregister()));
            }
            if ('caches' in window) {
              const keys = await caches.keys();
              await Promise.all(keys.map(k => caches.delete(k)));
            }
          } catch(e) {
            console.warn('[DIAG] SW/cache cleanup error', e);
          }
          location.reload();
        };
      };
      mount();
    }

    /* ── 성령의 열매 카드 데이터 ── */
    const SPIRIT_CARDS = [
      { id:1, name:'사랑',    g1:'#ff758c', g2:'#c0392b', img:'images/앤카드사랑최최종.png' },
      { id:2, name:'희락',    g1:'#f7971e', g2:'#c0850a', img:'images/앤카드희락최최종.png' },
      { id:3, name:'화평',    g1:'#185a9d', g2:'#43cea2', img:'images/앤카드화평최최종.png' },
      { id:4, name:'오래참음', g1:'#8b6914', g2:'#c8a96e', img:'images/앤카드오래참음최최종.png' },
      { id:5, name:'자비',    g1:'#2d6a4f', g2:'#52b788', img:'images/앤카드자비최최종.png' },
      { id:6, name:'양선',    g1:'#11998e', g2:'#38ef7d', img:'images/앤카드양선최최종.png' },
      { id:7, name:'충성',    g1:'#b5451b', g2:'#e8a87c', img:'images/앤카드충성최최종.png' },
      { id:8, name:'온유',    g1:'#7b4fa6', g2:'#c084fc', img:'images/앤카드온유최최종.png' },
      { id:9, name:'절제',    g1:'#1a3a5c', g2:'#2e86c1', img:'images/앤카드절제최최종.png' },
    ];
    const HIDDEN_CARD = { id:10, name:'히든', g1:'#1a1a2e', g2:'#3a3060', img:'images/히든.png' };

    /* ── 카드 이미지 프리로드 ── */
    function preloadCardImages() {
      SPIRIT_CARDS.concat([HIDDEN_CARD]).forEach(function(c) {
        if (c.img) { var i = new Image(); i.src = c.img; }
      });
    }
    (window.requestIdleCallback || function(cb) { setTimeout(cb, 1200); })(preloadCardImages);

    /* ── 카드 뽑기 사운드 ── */
    const SFX_FILES = {
      bgm:          'music/카드 Main BGM.mp3',
      packClick:    'music/포장지 클릭.mp3',
      packOpen:     'music/포장지 개봉.mp3',
      cardAppear:   'music/카드 등장.mp3',
      tapToFlip:    'music/tap to flip.mp3',
      mouseClick:   'music/마우스 클릭.mp3',
      cardSpin:     'music/카드회전.mp3',
      cardSparkle:  'music/카드 깜빡.mp3',
      revealNormal: 'music/일반 카드 공개.mp3',
      revealHidden: 'music/히든 카드 공개.mp3',
    };
    const SFX_VOLUME = {
      bgm: 0.32, packClick: 0.7, packOpen: 0.75, cardAppear: 0.7,
      tapToFlip: 0.6, mouseClick: 0.55, cardSpin: 0.7, cardSparkle: 0.75,
      revealNormal: 0.85, revealHidden: 0.95,
    };
    let _sfxMuted = localStorage.getItem('beyondus_sfx_muted') === '1';
    let _bgmAudio = null;
    let _bgmFadeTimer = null;
    let _activeSfx = []; // 일회성 효과음 트래킹 (정지용)
    const _sfxPreload = {};

    // 첫 사용자 인터랙션 시 프리로드
    function preloadSfx() {
      Object.keys(SFX_FILES).forEach(function(k) {
        if (_sfxPreload[k]) return;
        var a = new Audio(SFX_FILES[k]);
        a.preload = 'auto';
        _sfxPreload[k] = a;
      });
    }

    function playSfx(key) {
      if (_sfxMuted) return null;
      if (!drawOverlayActive) return null;
      var src = SFX_FILES[key];
      if (!src) return null;
      var a = _sfxPreload[key] ? _sfxPreload[key].cloneNode(true) : new Audio(src);
      a.volume = SFX_VOLUME[key] != null ? SFX_VOLUME[key] : 0.7;
      a.play().catch(function(){});
      _activeSfx.push(a);
      a.addEventListener('ended', function() {
        var idx = _activeSfx.indexOf(a);
        if (idx >= 0) _activeSfx.splice(idx, 1);
      });
      return a;
    }

    function startBgm() {
      if (_sfxMuted) return;
      if (_bgmFadeTimer) { clearInterval(_bgmFadeTimer); _bgmFadeTimer = null; }
      if (_bgmAudio) { _bgmAudio.currentTime = 0; _bgmAudio.play().catch(function(){}); return; }
      _bgmAudio = new Audio(SFX_FILES.bgm);
      _bgmAudio.loop = true;
      _bgmAudio.volume = SFX_VOLUME.bgm;
      _bgmAudio.play().catch(function(){});
    }

    function stopBgm() {
      if (!_bgmAudio) return;
      var a = _bgmAudio;
      if (_bgmFadeTimer) { clearInterval(_bgmFadeTimer); _bgmFadeTimer = null; }
      try {
        a.pause();
        a.currentTime = 0;
        a.volume = SFX_VOLUME.bgm;
      } catch(e) {}
      _bgmAudio = null;
    }

    function stopAllSfx() {
      _activeSfx.forEach(function(a) { try { a.pause(); a.currentTime = 0; } catch(e){} });
      _activeSfx = [];
    }

    function toggleSfxMute() {
      _sfxMuted = !_sfxMuted;
      localStorage.setItem('beyondus_sfx_muted', _sfxMuted ? '1' : '0');
      updateMuteBtnUI();
      if (_sfxMuted) {
        stopBgm();
        stopAllSfx();
      } else {
        // 뽑기 오버레이 열려있으면 BGM 재개
        var ov = document.getElementById('drawOverlay');
        if (ov && !ov.classList.contains('hidden')) startBgm();
      }
    }

    function updateMuteBtnUI() {
      var btn = document.getElementById('drawMuteBtn');
      if (!btn) return;
      btn.title = _sfxMuted ? '소리 켜기' : '음소거';
      btn.setAttribute('aria-label', _sfxMuted ? '소리 켜기' : '음소거');
      btn.innerHTML = _sfxMuted
        ? '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9v6h4l5 4V5L8 9H4z"></path><path d="M18 9l4 4"></path><path d="M22 9l-4 4"></path></svg>'
        : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9v6h4l5 4V5L8 9H4z"></path><path d="M17 9.5a4 4 0 0 1 0 5"></path><path d="M19.5 7a7.5 7.5 0 0 1 0 10"></path></svg>';
    }

    /* ── 주차 키 (ISO week) ── */
    function getWeekKey() {
      const now = new Date();
      const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const D = (m, d) => new Date(2026, m - 1, d);
      const WEEKS = [
        { key: 'w1', start: D(5,10), end: D(5,17) },
        { key: 'w2', start: D(5,18), end: D(5,24) },
        { key: 'w3', start: D(5,25), end: D(5,31) },
        { key: 'w4', start: D(6, 1), end: D(6, 7) },
        { key: 'w5', start: D(6, 8), end: D(6,14) },
        { key: 'w6', start: D(6,15), end: D(6,21) },
      ];
      for (const w of WEEKS) {
        if (today >= w.start && today <= w.end) return w.key;
      }
      return today < WEEKS[0].start ? 'w1' : 'w6';
    }

    /* ── 테스트 모드: dev URL에서만 자동 활성 ── */
    const TEST_MODE  = IS_DEV_ENV;

    /* ── DEV PWA 매니페스트 교체 ── */
    if (IS_DEV_ENV) {
      document.getElementById('pwaManifest').href = 'manifest-dev.json';
    }

    /* ── 상태 ── */
    let currentNickname = localStorage.getItem('beyondus_nickname') || null;
    let currentParish   = localStorage.getItem('beyondus_parish')   || null;
    let userStatus = null;
    let pendingCard = null;   // API에서 받아온 카드 데이터
    let lastConfigData = null; // 항목별 점수 계산용 캐시

    /* ── DOM ── */
    const weekTitleEl       = document.getElementById('weekTitle');
    const checkListEl       = document.getElementById('checkList');
    const countListEl       = document.getElementById('countList');
    const totalCountEl      = document.getElementById('totalCount');
    const submissionCountEl = document.getElementById('submissionCount');
    const statusMessageEl   = document.getElementById('statusMessage');
    const submitBtn         = document.getElementById('submitBtn');
    const refreshBtn        = document.getElementById('refreshBtn');
    const checkForm         = document.getElementById('checkForm');
    const GOAL_COUNT = 100;

    /* ════ 사용자 표시 ════ */
    function updateUserBadge() {
      const text = currentNickname
        ? `${currentNickname}${currentParish ? ' · ' + currentParish : ''}`
        : '';
      document.getElementById('topBarUser').textContent = text;
      document.getElementById('drawerUser').textContent = text ? `👤 ${text}` : '';
    }

    /* ════ 화면 전환 ════ */
    function hideSplash() {
      const splash = document.getElementById('splashScreen');
      if (splash) splash.style.display = 'none';
    }
    function shouldEnterApp(isStaff, appOpenDate) {
      if (isStaff) return true;
      if (!appOpenDate) return false;
      return new Date().toISOString().slice(0, 10) >= appOpenDate;
    }
    /* ── Coming Soon 캐러셀 ── */
    let _csIdx = 0;
    let _csTimer = null;
    const CS_TOTAL = 3;
    const CS_INTERVAL = 4000;

    function csGoTo(idx) {
      _csIdx = (idx + CS_TOTAL) % CS_TOTAL;
      document.getElementById('csBannerTrack').style.transform = `translateX(-${_csIdx * 100}%)`;
      document.querySelectorAll('.cs-dot').forEach((d, i) => d.classList.toggle('active', i === _csIdx));
    }
    function csStartAuto() {
      csStopAuto();
      _csTimer = setInterval(() => csGoTo(_csIdx + 1), CS_INTERVAL);
    }
    function csStopAuto() {
      if (_csTimer) { clearInterval(_csTimer); _csTimer = null; }
    }
    /* 스와이프/드래그 — 한 번만 등록 */
    (function csInitSwipe() {
      const wrap = document.getElementById('csBannerWrap');
      let startX = 0, dragging = false;

      function onStart(x) { startX = x; dragging = true; csStopAuto(); }
      function onEnd(x) {
        if (!dragging) return;
        dragging = false;
        const dx = x - startX;
        if (Math.abs(dx) > 40) csGoTo(_csIdx + (dx < 0 ? 1 : -1));
        csStartAuto();
      }

      /* 터치 */
      wrap.addEventListener('touchstart', e => onStart(e.touches[0].clientX), { passive: true });
      wrap.addEventListener('touchend',   e => onEnd(e.changedTouches[0].clientX), { passive: true });

      /* 마우스 드래그 */
      wrap.addEventListener('mousedown',  e => onStart(e.clientX));
      window.addEventListener('mouseup',  e => onEnd(e.clientX));
    })();

    function detectBrowser() {
      const ua = navigator.userAgent;
      const isIOS = /iphone|ipad|ipod/i.test(ua) && !window.MSStream;
      const isAndroid = /android/i.test(ua);
      const isSamsung = /samsungbrowser/i.test(ua);
      const isChrome = /chrome/i.test(ua) && !/edg/i.test(ua) && !isSamsung;
      const isSafari = /safari/i.test(ua) && !isChrome && !isSamsung;
      const os = isIOS ? 'ios' : isAndroid ? 'android' : 'other';
      const browser = isSamsung ? 'samsung' : isChrome ? 'chrome' : isSafari ? 'safari' : 'other';
      return { os, browser };
    }

    function renderInstallBanner() {
      const el = document.getElementById('csBannerInstallContent');
      if (!el) return;
      const { os, browser } = detectBrowser();
      let steps = [];
      if (os === 'ios') {
        steps = ['우측 하단 <strong>···</strong> 선택', '<strong>공유</strong> 선택', '<strong>홈 화면에 추가</strong> 선택', '우측 상단 <strong>추가</strong> 선택'];
      } else if (browser === 'samsung') {
        steps = ['우측 하단 <strong>≡</strong> 선택', '<strong>추가</strong> 선택', '<strong>홈 화면 → 추가</strong> 선택'];
      } else if (browser === 'chrome') {
        steps = ['우측 상단 <strong>⋮</strong> 선택', '<strong>홈 화면에 추가</strong> 선택', '<strong>추가</strong> 선택', '<strong>추가</strong> 선택'];
      } else {
        el.textContent = 'Safari(iOS) 또는 삼성인터넷/Chrome(Android)으로 열어주세요.';
        return;
      }
      const label = os === 'ios' ? 'iPhone (Safari)' : browser === 'samsung' ? 'Android (삼성인터넷)' : 'Android (Chrome)';
      el.innerHTML = `<span style="font-weight:700;color:var(--text);font-size:11px;">${label}</span><br><span>${steps.map((s, i) => `${i + 1}. ${s}`).join(' &nbsp;›&nbsp; ')}</span>`;
    }

    function isStandaloneApp() {
      return window.matchMedia('(display-mode: standalone)').matches
          || window.navigator.standalone === true;
    }

    function copyCurrentUrl() {
      const url = location.href;
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(url).catch(() => {});
      }
    }

    function getInstallGuideText() {
      const env = detectBrowser();
      if (env.os === 'ios') {
        if (env.browser === 'safari') {
          return 'Safari 아래 공유 버튼을 누른 뒤 "홈 화면에 추가"를 선택하고, 오른쪽 위 "추가"를 누르면 돼요.';
        }
        return 'iPhone은 Safari에서 여는 게 가장 안정적이에요. 링크를 복사한 뒤 Safari 주소창에 붙여넣고, 공유 버튼 → "홈 화면에 추가"를 눌러주세요.';
      }
      if (env.browser === 'samsung') {
        return '삼성인터넷 하단 메뉴(≡)에서 "현재 페이지 추가" 또는 "추가"를 누른 뒤 "홈 화면"을 선택해주세요.';
      }
      if (env.browser === 'chrome') {
        return 'Chrome 오른쪽 위 메뉴(⋮)에서 "앱 설치"가 보이면 누르고, 없으면 "홈 화면에 추가"를 선택해주세요.';
      }
      return '브라우저 메뉴에서 "앱 설치", "홈 화면에 추가", "현재 페이지 추가" 중 보이는 메뉴를 선택해주세요.';
    }

    function showInstallGuide(copyFirst) {
      if (copyFirst) copyCurrentUrl();
      alert(getInstallGuideText() + (copyFirst ? '\n\n링크도 복사해두었어요.' : ''));
    }

    function updateMainInstallGuide() {
      const card = document.getElementById('mainInstallGuide');
      if (!card) return;
      if (isStandaloneApp()) {
        card.classList.add('hidden');
        return;
      }
      const env = detectBrowser();
      const ua = navigator.userAgent;
      const inAppBrowser = /kakaotalk|naver|line/i.test(ua);
      const title = document.getElementById('mainInstallGuideTitle');
      const desc = document.getElementById('mainInstallGuideDesc');
      const btn = card.querySelector('.install-guide-btn');

      if (inAppBrowser) {
        title.textContent = '브라우저에서 열면 더 편해요';
        desc.textContent = '홈 화면 추가는 Safari, Chrome, 삼성인터넷에서 가장 안정적이에요.';
        btn.textContent = '링크 복사';
        btn.onclick = function() { showInstallGuide(true); };
      } else if (env.os === 'ios') {
        title.textContent = env.browser === 'safari' ? 'iPhone 홈 화면에 추가하기' : 'Safari로 열기';
        desc.textContent = env.browser === 'safari'
          ? '공유 버튼에서 추가하면 앱처럼 바로 열 수 있어요.'
          : 'iPhone은 Safari에서 홈 화면 추가가 가장 안정적이에요.';
        btn.textContent = env.browser === 'safari' ? '방법 보기' : '링크 복사';
        btn.onclick = function() { showInstallGuide(env.browser !== 'safari'); };
      } else if (env.browser === 'samsung') {
        title.textContent = '삼성인터넷 홈 화면에 추가하기';
        desc.textContent = '하단 메뉴에서 직접 추가하면 오류가 적어요.';
        btn.textContent = '방법 보기';
        btn.onclick = function() { showInstallGuide(false); };
      } else {
        title.textContent = '홈 화면에 추가하기';
        desc.textContent = '설치 버튼이 막히면 브라우저 메뉴에서 직접 추가해주세요.';
        btn.textContent = '방법 보기';
        btn.onclick = function() { showInstallGuide(false); };
      }
      card.classList.remove('hidden');
    }

    function showComingSoon() {
      hideSplash();
      document.getElementById('authScreen').classList.add('hidden');
      document.getElementById('appScreen').classList.add('hidden');
      document.getElementById('comingSoonScreen').classList.remove('hidden');
      renderInstallBanner();
      csGoTo(0);
      csStartAuto();
      loadHoldPrayPreview();
    }

    async function loadHoldPrayPreview() {
      const el      = document.getElementById('csHpContent');
      const overlay = document.getElementById('csHpOverlay');
      const loading = document.getElementById('csHpLoading');
      if (!el) return;
      try {
        const wk = getWeekKey();
        const nick = localStorage.getItem('beyondus_nickname') || '';
        const [res] = await Promise.all([
          fetch(`${API_BASE}?action=getHoldPray&weekKey=${encodeURIComponent(wk)}&nickname=${encodeURIComponent(nick)}&t=${Date.now()}`),
          document.fonts.load('1em "Nanum Pen Script"').catch(() => {})
        ]);
        const d = await res.json();
        const previewContent = d.ok && d.cards && d.cards[0] && d.cards[0].content;
        if (previewContent) {
          el.textContent = previewContent;
          if (loading) loading.style.display = 'none';
          if (overlay) overlay.style.display = '';
          fitHpText(el, overlay);
          return;
        }
      } catch(e) {
        if (el) el.textContent = '';
      } finally {
        if (loading) loading.style.display = 'none';
        if (overlay) overlay.style.display = '';
      }
    }
    function showAuth(pane) {
      hideSplash();
      csStopAuto();
      document.getElementById('comingSoonScreen').classList.add('hidden');
      document.getElementById('authScreen').classList.remove('hidden');
      document.getElementById('appScreen').classList.add('hidden');
      switchAuthPane(pane || 'register');
    }

    function scheduleTradePolling() {
      if (window._tradePollingTimer) return;
      const delay = 35000 + Math.floor(Math.random() * 25000);
      window._tradePollingTimer = setTimeout(() => {
        window._tradePollingTimer = null;
        const appVisible = !document.getElementById('appScreen').classList.contains('hidden');
        if (currentNickname && appVisible && !document.hidden) {
          loadUserStatus({ silent: true }).then(() => loadTrades()).catch(() => {});
        }
        if (currentNickname && appVisible) scheduleTradePolling();
      }, delay);
    }

    function showApp() {
      document.getElementById('comingSoonScreen').classList.add('hidden');
      document.getElementById('authScreen').classList.add('hidden');
      document.getElementById('appScreen').classList.remove('hidden');
      updateInquiryLoginUI();
      if (localStorage.getItem('beyondus_trade_dot') === '1') {
        document.getElementById('tradeMenuDot').classList.add('visible');
        document.getElementById('drawerTradeDot').style.display = 'inline-block';
      }
      // 접속자가 몰려도 같은 순간에 서버를 때리지 않도록 지터를 둔 폴링.
      scheduleTradePolling();
    }

    function syncInitialData(options) {
      const opts = options || {};
      return Promise.all([
        loadAll({ silent: opts.silent === true }),
        loadNotices().catch(() => {}),
        currentNickname ? loadUserStatus({ silent: opts.silent === true }).then(() => loadTrades()) : Promise.resolve()
      ]);
    }

    /* ════ Auth 패인 전환 ════ */
    function switchAuthPane(pane) {
      ['register', 'login', 'reset', 'findNickname'].forEach(p => {
        document.getElementById(p + 'Pane').classList.add('hidden');
      });
      document.getElementById(pane + 'Pane').classList.remove('hidden');
      ['registerStatus', 'loginStatus', 'resetStatus', 'findNicknameStatus'].forEach(id => {
        const el = document.getElementById(id);
        el.textContent = '';
        el.className = 'auth-status';
      });
      document.getElementById('resetDuplicates').style.display = 'none';
    }

    function saveAuth(nickname, sessionToken, parish) {
      const prev = localStorage.getItem('beyondus_nickname');
      if (prev && prev !== nickname) {
        localStorage.removeItem('beyondus_cache_userStatus_' + prev);
        localStorage.removeItem('beyondus_cache_config');
      }
      localStorage.setItem('beyondus_nickname', nickname);
      if (sessionToken) localStorage.setItem('beyondus_session_token', sessionToken);
      localStorage.removeItem('beyondus_password');
      localStorage.setItem('beyondus_parish',   parish);
      currentNickname = nickname;
      currentParish   = parish;
    }

    /* 자동 로그인 — 캐시 신뢰 방식 (즉시 진입, 백그라운드 검증) */
    async function autoLogin() {
      console.warn('[DIAG] autoLogin() called at', new Date().toISOString());
      const savedNickname = localStorage.getItem('beyondus_nickname');
      const savedToken    = localStorage.getItem('beyondus_session_token');
      const savedPassword = localStorage.getItem('beyondus_password'); // 구버전 캐시 1회 마이그레이션용
      const savedParish   = localStorage.getItem('beyondus_parish');

      if (!savedNickname || (!savedToken && !savedPassword)) {
        showAuth('register');
        renderDrawSection();
        return;
      }

      // 캐시 신뢰 → 즉시 앱 진입 + 스플래시 해제
      currentNickname = savedNickname;
      currentParish   = savedParish || '';
      updateUserBadge();
      showApp();
      const cachedConfig = JSON.parse(localStorage.getItem('beyondus_cache_config') || 'null');
      if (cachedConfig) { lastConfigData = cachedConfig; renderConfig(cachedConfig); renderCounts(cachedConfig); applyTabSettings(cachedConfig); }
      const cachedUS = JSON.parse(localStorage.getItem('beyondus_cache_userStatus_' + savedNickname) || 'null');
      if (cachedUS) { userStatus = cachedUS; renderDrawSection(); renderCollection(); updateScoreProgress(); }
      hideSplash();
      syncInitialData({ silent: true }).catch(() => {});

      // 백그라운드에서 서버 검증 (세션 갱신 포함)
      try {
        const res  = await fetch(API_BASE, {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain;charset=utf-8' },
          body: JSON.stringify(savedToken
            ? { action: 'login', nickname: savedNickname, sessionToken: savedToken }
            : { action: 'login', nickname: savedNickname, password: savedPassword })
        });
        const data = await res.json();
        if (!data.ok) {
          // GAS 일시 오류(ok:false+message)는 무시하고 캐시 유지
          // 명확한 인증 실패(잘못된 토큰·없는 닉네임)일 때만 로그아웃
          const isAuthFail = data.error === 'wrong_password' || data.error === 'not_found';
          if (isAuthFail) {
            console.warn('[DIAG] autoLogin auth-fail. response=', data, 'savedNickname=', savedNickname, 'hadToken=', !!savedToken);
            // 부드러운 클리어: 인증 키만 제거, 닉네임/교구/캐시는 유지
            // (다중 기기 핑퐁으로 일시적 토큰 무효화가 발생해도 사용자 데이터는 보존)
            localStorage.removeItem('beyondus_session_token');
            localStorage.removeItem('beyondus_password');
            currentNickname = null;
            currentParish   = null;
            showAuth('login');
            // 닉네임 자동 입력 — 비번만 다시 치면 됨
            const loginNickEl = document.getElementById('loginNickname');
            if (loginNickEl && savedNickname) {
              loginNickEl.value = savedNickname;
              const loginPwEl = document.getElementById('loginPassword');
              if (loginPwEl) setTimeout(() => loginPwEl.focus(), 100);
            }
          } else {
            console.warn('[DIAG] autoLogin server returned ok:false but not auth-fail. ignoring. response=', data);
          }
        } else {
          saveAuth(savedNickname, data.sessionToken || savedToken || '', data.parish || savedParish || '');
          localStorage.setItem('beyondus_is_staff',      String(data.isStaff === true));
          localStorage.setItem('beyondus_is_dev',        String(data.isDev   === true));
          localStorage.setItem('beyondus_app_open_date', data.appOpenDate || '');
        }
      } catch(e) {
        console.warn('[DIAG] autoLogin network/parse error (cache 유지)', e);
      }
    }

    // [DIAG] 페이지 unload 시점에 어떤 경로로 unload되는지 추적
    window.addEventListener('beforeunload', () => {
      console.warn('[DIAG] beforeunload fired. section=', _currentSection, 'time=', new Date().toISOString());
    });

    /* 회원가입 */
    document.getElementById('registerBtn').addEventListener('click', async () => {
      const name     = document.getElementById('regName').value.trim();
      const parish   = document.getElementById('regParish').value;
      const nickname = document.getElementById('regNickname').value.trim();
      const password = document.getElementById('regPassword').value;
      const statusEl = document.getElementById('registerStatus');

      if (!name || !parish || !nickname || !password) {
        statusEl.textContent = '모든 항목을 입력해주세요.'; return;
      }
      if (nickname.length < 2) { statusEl.textContent = '닉네임은 2자 이상이어야 해요.'; return; }
      if (password.length < 4) { statusEl.textContent = '비밀번호는 4자 이상이어야 해요.'; return; }

      const btn = document.getElementById('registerBtn');
      btn.disabled = true;
      const dotsTimerReg = animDots(statusEl, '가입 중');

      try {
        const res = await fetch(API_BASE, {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain;charset=utf-8' },
          body: JSON.stringify({ action: 'register', name, parish, nickname, password })
        });
        const data = await res.json();
        if (data.ok) {
          stopAnimDots(dotsTimerReg, statusEl, '');
          saveAuth(nickname, data.sessionToken || '', parish);
          localStorage.setItem('beyondus_is_staff', 'false');
          localStorage.setItem('beyondus_is_dev',   'false');
          const aod = localStorage.getItem('beyondus_app_open_date') || '';
          updateUserBadge();
          if (shouldEnterApp(false, aod)) {
            showApp(); syncInitialData().catch(() => {});
          } else {
            showComingSoon();
          }
        } else if (data.error === 'duplicate') {
          stopAnimDots(dotsTimerReg, statusEl, '이미 사용 중인 닉네임이에요. 다른 닉네임을 써주세요.');
        } else {
          stopAnimDots(dotsTimerReg, statusEl, '오류가 발생했어요. 다시 시도해주세요.');
        }
      } catch(e) {
        stopAnimDots(dotsTimerReg, statusEl, '연결에 실패했어요. 잠시 후 다시 시도해주세요.');
      } finally {
        btn.disabled = false;
      }
    });

    /* 로그인 */
    document.getElementById('loginBtn').addEventListener('click', async () => {
      const nickname = document.getElementById('loginNickname').value.trim();
      const password = document.getElementById('loginPassword').value;
      const statusEl = document.getElementById('loginStatus');

      if (!nickname || !password) { statusEl.textContent = '닉네임과 비밀번호를 입력해주세요.'; return; }

      const btn = document.getElementById('loginBtn');
      btn.disabled = true;
      const dotsTimerLogin = animDots(statusEl, '로그인 중');

      try {
        const res = await fetch(API_BASE, {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain;charset=utf-8' },
          body: JSON.stringify({ action: 'login', nickname, password })
        });
        const data = await res.json();
        if (data.ok) {
          stopAnimDots(dotsTimerLogin, statusEl, '');
          saveAuth(nickname, data.sessionToken || '', data.parish || '');
          localStorage.setItem('beyondus_is_staff',      String(data.isStaff === true));
          localStorage.setItem('beyondus_is_dev',        String(data.isDev   === true));
          localStorage.setItem('beyondus_app_open_date', data.appOpenDate || '');
          updateUserBadge();
          if (shouldEnterApp(data.isStaff, data.appOpenDate)) {
            showApp();
            syncInitialData().catch(() => {});
          } else {
            showComingSoon();
          }
        } else if (data.error === 'not_found') {
          stopAnimDots(dotsTimerLogin, statusEl, '닉네임을 찾을 수 없어요.');
        } else if (data.error === 'wrong_password') {
          stopAnimDots(dotsTimerLogin, statusEl, '비밀번호가 틀렸어요.');
        } else {
          stopAnimDots(dotsTimerLogin, statusEl, '오류가 발생했어요.');
        }
      } catch(e) {
        stopAnimDots(dotsTimerLogin, statusEl, '연결에 실패했어요. 잠시 후 다시 시도해주세요.');
      } finally {
        btn.disabled = false;
      }
    });

    /* 비밀번호 재설정 */
    async function doResetPassword(nickname) {
      const name        = document.getElementById('resetName').value.trim();
      const parish      = document.getElementById('resetParish').value;
      const newPassword = document.getElementById('resetPassword').value;
      const statusEl    = document.getElementById('resetStatus');
      const btn         = document.getElementById('resetBtn');

      btn.disabled = true;
      statusEl.className = 'auth-status';
      const dotsTimerReset = animDots(statusEl, '확인 중');

      try {
        const res = await fetch(API_BASE, {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain;charset=utf-8' },
          body: JSON.stringify({ action: 'resetPassword', nickname, name, parish, newPassword })
        });
        const data = await res.json();
        if (data.ok) {
          stopAnimDots(dotsTimerReset, statusEl, '비밀번호가 변경됐어요! 로그인해주세요.');
          statusEl.className = 'auth-status success';
          document.getElementById('resetDuplicates').style.display = 'none';
          setTimeout(() => switchAuthPane('login'), 1500);
        } else if (data.duplicates) {
          stopAnimDots(dotsTimerReset, statusEl, '');
          const dupWrap = document.getElementById('resetDuplicates');
          const dupList = document.getElementById('resetDuplicateList');
          dupList.innerHTML = data.duplicates.map(n =>
            `<button class="btn btn-secondary" style="flex:none;font-size:13px;padding:6px 14px;" onclick="doResetPassword('${escHtml(n)}')">${escHtml(n)}</button>`
          ).join('');
          dupWrap.style.display = 'block';
        } else if (data.error === 'not_found') {
          stopAnimDots(dotsTimerReset, statusEl, '입력한 정보와 일치하는 계정이 없어요.');
        } else {
          stopAnimDots(dotsTimerReset, statusEl, '오류가 발생했어요.');
        }
      } catch(e) {
        stopAnimDots(dotsTimerReset, statusEl, '연결에 실패했어요.');
      } finally {
        btn.disabled = false;
      }
    }

    document.getElementById('resetBtn').addEventListener('click', () => {
      const name        = document.getElementById('resetName').value.trim();
      const parish      = document.getElementById('resetParish').value;
      const newPassword = document.getElementById('resetPassword').value;
      const statusEl    = document.getElementById('resetStatus');

      document.getElementById('resetDuplicates').style.display = 'none';
      statusEl.className = 'auth-status';

      if (!name || !parish || !newPassword) {
        statusEl.textContent = '모든 항목을 입력해주세요.'; return;
      }
      if (newPassword.length < 4) { statusEl.textContent = '비밀번호는 4자 이상이어야 해요.'; return; }

      doResetPassword('');
    });

    /* 닉네임 찾기 */
    document.getElementById('findNicknameBtn').addEventListener('click', async () => {
      const name     = document.getElementById('findName').value.trim();
      const parish   = document.getElementById('findParish').value;
      const statusEl = document.getElementById('findNicknameStatus');

      if (!name || !parish) { statusEl.textContent = '이름과 소속을 모두 입력해주세요.'; return; }

      const btn = document.getElementById('findNicknameBtn');
      btn.disabled = true;
      statusEl.className = 'auth-status';
      const dotsTimerFind = animDots(statusEl, '찾는 중');

      try {
        const res = await fetch(`${API_BASE}?action=findNickname&name=${encodeURIComponent(name)}&parish=${encodeURIComponent(parish)}&t=${Date.now()}`, { cache: 'no-store' });
        const data = await res.json();
        if (data.ok && data.nicknames && data.nicknames.length) {
          stopAnimDots(dotsTimerFind, statusEl, '');
          statusEl.className = 'auth-status success';
          statusEl.innerHTML = `찾았어요! 닉네임: <strong>${data.nicknames.map(n => escHtml(n)).join(', ')}</strong>`;
        } else {
          stopAnimDots(dotsTimerFind, statusEl, '일치하는 계정을 찾지 못했어요. 이름·소속을 다시 확인해주세요.');
        }
      } catch(e) {
        stopAnimDots(dotsTimerFind, statusEl, '연결에 실패했어요.');
      } finally {
        btn.disabled = false;
      }
    });

    /* Enter 키 처리 */
    [['regPassword', 'registerBtn'], ['loginPassword', 'loginBtn'], ['resetPassword', 'resetBtn']].forEach(([inputId, btnId]) => {
      document.getElementById(inputId).addEventListener('keydown', e => {
        if (e.key === 'Enter') document.getElementById(btnId).click();
      });
    });

    /* ════ 카드 상세 오버레이 ════ */
    function openCardDetail(cardId, cnt) {
      const card = cardId === 10 ? HIDDEN_CARD : SPIRIT_CARDS.find(c => c.id === cardId);
      if (!card) return;
      // 새 카드 dot 제거
      Object.keys(localStorage).filter(k => k.startsWith('beyondus_new_card_') && localStorage.getItem(k) === String(cardId)).forEach(k => localStorage.removeItem(k));
      const remaining = Object.keys(localStorage).filter(k => k.startsWith('beyondus_new_card_')).length;
      const nb = document.getElementById('collNewCardBadge');
      if (nb) nb.style.display = remaining > 0 ? 'inline-block' : 'none';
      // 교환현황 탭·햄버거 badge 즉시 갱신
      const badge   = document.getElementById('collTradeBadge');
      const menuDot = document.getElementById('tradeMenuDot');
      const dot     = document.getElementById('drawerTradeDot');
      if (badge) badge.style.display = remaining > 0 ? 'inline-block' : 'none';
      const noTradeAlerts = remaining === 0 && !document.querySelector('.pray-btn');
      if (noTradeAlerts && menuDot) menuDot.classList.remove('visible');
      if (noTradeAlerts && dot) dot.style.display = 'none';
      localStorage.setItem('beyondus_trade_dot', remaining > 0 ? '1' : '0');
      renderCollection();
      if (_cachedTrades) renderTrades(_cachedTrades);

      const wrap = document.getElementById('cardDetailWrap');
      const cntEl = document.getElementById('cardDetailCnt');
      wrap.style.cssText = 'display:flex; flex-direction:column; align-items:center; gap:0;';

      if (cnt <= 1) {
        // 단일 카드
        wrap.innerHTML = `<div style="width:240px; max-width:80vw;"><img src="${card.img}" style="width:100%; height:auto; display:block; object-fit:contain; border-radius:16px; box-shadow:0 6px 28px rgba(0,0,0,0.55);"></div>`;
        cntEl.textContent = '';
      } else if (cnt === 2) {
        // 2장 — 양쪽으로 살짝 부채꼴
        wrap.innerHTML = `
          <div style="position:relative; width:270px; height:255px; max-width:88vw;">
            <div style="position:absolute; left:18px; top:0; width:145px; z-index:1; transform:rotate(-9deg); transform-origin:bottom center; filter:drop-shadow(0 4px 14px rgba(0,0,0,0.45));">
              <img src="${card.img}" style="width:100%; height:auto; display:block; border-radius:14px;">
            </div>
            <div style="position:absolute; right:18px; top:0; width:145px; z-index:2; transform:rotate(9deg); transform-origin:bottom center; filter:drop-shadow(0 6px 20px rgba(0,0,0,0.6));">
              <img src="${card.img}" style="width:100%; height:auto; display:block; border-radius:14px;">
            </div>
          </div>`;
        cntEl.textContent = '2장 보유';
      } else {
        // 3장 이상 — 3장 부채꼴 + 뱃지
        const badge = cnt > 3
          ? `<div style="position:absolute; top:-6px; right:-6px; background:#e8854a; color:#fff; font-size:11px; font-weight:700; border-radius:999px; padding:2px 8px; z-index:10; box-shadow:0 2px 6px rgba(0,0,0,0.4);">×${cnt}</div>`
          : '';
        wrap.innerHTML = `
          <div style="position:relative; width:280px; height:265px; max-width:90vw;">
            <div style="position:absolute; left:4px; top:22px; width:128px; z-index:1; transform:rotate(-15deg); transform-origin:bottom center; filter:drop-shadow(0 4px 12px rgba(0,0,0,0.4));">
              <img src="${card.img}" style="width:100%; height:auto; display:block; border-radius:13px;">
            </div>
            <div style="position:absolute; left:50%; top:0; width:145px; z-index:3; transform:translateX(-50%); filter:drop-shadow(0 8px 24px rgba(0,0,0,0.65));">
              ${badge}
              <img src="${card.img}" style="width:100%; height:auto; display:block; border-radius:14px;">
            </div>
            <div style="position:absolute; right:4px; top:22px; width:128px; z-index:2; transform:rotate(15deg); transform-origin:bottom center; filter:drop-shadow(0 4px 12px rgba(0,0,0,0.4));">
              <img src="${card.img}" style="width:100%; height:auto; display:block; border-radius:13px;">
            </div>
          </div>`;
        cntEl.textContent = `${cnt}장 보유`;
      }

      const actionsEl = document.getElementById('cardDetailActions');
      if (actionsEl) {
        actionsEl.innerHTML = `<button onclick="closeCardDetail();openTradeModal(${cardId})" style="background:rgba(255,246,239,0.15);border:1px solid rgba(255,246,239,0.35);color:rgba(255,246,239,0.9);font-size:13px;font-weight:600;padding:8px 24px;border-radius:999px;cursor:pointer;">교환 신청하기</button>`;
      }
      document.getElementById('cardDetailOverlay').classList.remove('hidden');
    }
    function closeCardDetail() {
      document.getElementById('cardDetailOverlay').classList.add('hidden');
    }

    /* ════ 카드 HTML 생성 ════ */
    function makeCardHTML(card) {
      return `
        <div class="spirit-card" style="background:transparent; border:none; box-shadow:none;">
          <div class="draw-card-clip">
            <img src="${card.img}" alt="">
          </div>
        </div>`;
    }

    function updateTicketBadge(status) {
      const ticketBadge = document.getElementById('ticketBadge');
      if (!ticketBadge) return;
      const pending = status && !status.error ? Math.max(0, Number(status.pendingDraws) || 0) : 0;
      ticketBadge.textContent = `🎫 ${pending}`;
    }

    /* ════ 뽑기 섹션 렌더 ════ */
    function renderDrawSection() {
      const el = document.getElementById('drawSectionBody');
      const testBadge = TEST_MODE
        ? `<div style="display:inline-block;margin-bottom:10px;padding:4px 10px;background:#fef08a;color:#854d0e;font-size:11px;font-weight:800;border-radius:999px;">🧪 테스트 모드</div><br>`
        : '';
      updateTicketBadge(userStatus);

      if (!currentNickname) {
        el.innerHTML = `${testBadge}<button class="btn btn-secondary" style="width:100%;" id="setNicknameBtn">로그인하고 참여하기</button>`;
        document.getElementById('setNicknameBtn').onclick = () => showAuth('login');
        return;
      }
      if (!userStatus) {
        el.innerHTML = `<p class="card-sub" style="margin:0;">불러오는 중...</p>`;
        return;
      }
      if (userStatus.error) {
        el.innerHTML = `<p class="card-sub" style="margin:0;">서버 업데이트 후 이용 가능합니다.</p>`;
        return;
      }

      // 테스트 모드: 제출/중복 제한 무시하고 항상 뽑기 가능
      if (TEST_MODE) {
        el.innerHTML = `
          ${testBadge}
          <p style="font-size:13px;color:var(--sub);margin-bottom:12px;">횟수 제한 없이 뽑을 수 있어요 ✨</p>
          <button class="btn btn-primary" style="width:100%;" id="openDrawBtn">카드 뽑기</button>`;
        document.getElementById('openDrawBtn').onclick = openDrawOverlay;
        return;
      }

      // 서비스 모드: 정책 적용
      const pending = userStatus.pendingDraws || 0;

      if (pending > 0 || IS_DEV_ENV) {
        el.innerHTML = `<button class="btn btn-primary" style="width:100%;" id="openDrawBtn">카드 뽑기${IS_DEV_ENV && pending === 0 ? ' (DEV)' : ''}</button>`;
        document.getElementById('openDrawBtn').onclick = openDrawOverlay;
        return;
      }
      el.innerHTML = `<button class="btn btn-primary" style="width:100%;" disabled>카드 뽑기</button>`;
    }

    /* ════ 컬렉션 렌더 ════ */
    function renderCollection() {
      const grid = document.getElementById('collectionGrid');
      const sub  = document.getElementById('collectionSub');
      if (!currentNickname || !userStatus || userStatus.error) return;

      const counts = {};
      (userStatus.collection || []).forEach(c => { counts[c.id] = (counts[c.id] || 0) + 1; });

      const newCardIds = new Set();
      Object.keys(localStorage).filter(k => k.startsWith('beyondus_new_card_')).forEach(k => newCardIds.add(Number(localStorage.getItem(k))));
      newCardIds.forEach(id => {
        if (!(counts[id] > 0)) {
          Object.keys(localStorage).filter(k => k.startsWith('beyondus_new_card_') && localStorage.getItem(k) === String(id)).forEach(k => localStorage.removeItem(k));
          newCardIds.delete(id);
        }
      });

      const spiritUnique = SPIRIT_CARDS.filter(c => counts[c.id] > 0).length;
      const hiddenCnt    = counts[10] || 0;
      const totalUnique  = spiritUnique + (hiddenCnt > 0 ? 1 : 0);
      sub.textContent = `${currentNickname}님의 컬렉션 · ${totalUnique}/10종 보유`;
      document.getElementById('collSubNormal').style.display = '';

      grid.innerHTML = SPIRIT_CARDS.map(card => {
        const cnt = counts[card.id] || 0;
        const locked = cnt === 0;
        const isNew = !locked && newCardIds.has(card.id);
        const gStyle = locked ? '' : `background:linear-gradient(135deg,${card.g1},${card.g2})`;
        const ghosts = !locked && cnt >= 2
          ? (cnt >= 3
              ? `<div class="mini-card-ghost mini-card-ghost-2" style="${gStyle}"></div>
                 <div class="mini-card-ghost mini-card-ghost-1" style="${gStyle}"></div>`
              : `<div class="mini-card-ghost mini-card-ghost-1" style="${gStyle}"></div>`)
          : '';
        const unlockedContent = `<img src="${card.img}" style="width:100%;height:100%;object-fit:contain;display:block;">`;
        return `
          <div class="mini-card-wrap" style="${!locked ? 'cursor:pointer;' : ''}">
            ${ghosts}
            <div class="mini-card ${locked ? 'mini-card-locked' : 'mini-card-img'}" ${!locked ? `onclick="openCardDetail(${card.id},${cnt})"` : ''}>
              ${locked
                ? `<img src="images/앤수배.png" class="mini-card-silhouette" alt="">`
                : unlockedContent
              }
            </div>
            ${cnt > 1 ? `<div class="mini-card-badge">×${cnt}</div>` : ''}
            ${isNew ? `<div style="position:absolute;top:2px;right:2px;width:9px;height:9px;background:#e05a5a;border-radius:50%;z-index:5;border:1.5px solid var(--card);pointer-events:none;"></div>` : ''}
          </div>`;
      }).join('');

      renderHiddenSection(hiddenCnt);
    }

    function renderHiddenSection(hiddenCnt) {
      const slot = document.getElementById('hiddenCardSlot');
      if (!slot) return;

      const got = hiddenCnt > 0;
      const cardInner = got
        ? `<div class="mini-card mini-card-img" onclick="openCardDetail(10,${hiddenCnt})"><img src="images/히든.png" style="width:100%;height:100%;object-fit:contain;display:block;"></div>`
        : `<div class="mini-card mini-card-locked mini-card-rare-locked"><img src="images/앤수배.png" class="mini-card-silhouette" alt=""></div>`;

      slot.innerHTML = `
        <p class="coll-subtitle">레어카드</p>
        <div class="collection-grid">
          <div class="mini-card-wrap" style="${got ? 'cursor:pointer;' : ''}">
            ${cardInner}
          </div>
        </div>`;
    }

    /* ════ 교환 시스템 ════ */
    let _tradeTargetNickname = '';
    let _tradeTargetColl = {};
    let _tradeMyCardId = null;
    let _tradeTheirCardId = null;
    let _tradeStep = 1;
    let _cachedTrades = null;
    let _lastTradeCollectionRenderSig = '';

    function switchCollTab(tab) {
      const isGrid = tab === 'grid';
      document.getElementById('collPanelGrid').style.display   = isGrid ? '' : 'none';
      document.getElementById('collPanelTrades').style.display = isGrid ? 'none' : '';
      document.getElementById('collTabGrid').classList.toggle('active', isGrid);
      document.getElementById('collTabTrades').classList.toggle('active', !isGrid);
      if (!isGrid) loadTrades();
    }

    function openTradeModal(preCardId) {
      // 중복 카드(2장 이상) 없으면 진입 차단
      const counts = {};
      (userStatus?.collection || []).forEach(c => { counts[c.id] = (counts[c.id] || 0) + 1; });
      const hasDuplicate = Object.values(counts).some(n => n >= 2);
      if (!hasDuplicate) {
        alert('교환하려면 같은 카드를 2장 이상 보유해야 해요.\n중복 카드가 생기면 다시 시도해주세요!');
        return;
      }
      _tradeTargetNickname = ''; _tradeTargetColl = {};
      // preCardId가 1장짜리면 무시 (step2에서 다시 선택)
      _tradeMyCardId = (preCardId && (counts[preCardId] || 0) >= 2) ? preCardId : null;
      _tradeTheirCardId = null;
      _tradeStep = 1;
      document.getElementById('tradeTargetInput').value = '';
      document.getElementById('tradeSearchResult').innerHTML = '';
      document.getElementById('tradeOverlay').style.display = 'block';
      document.body.style.overflow = 'hidden';
      _tradeShowStep(1);
    }

    function closeTradeModal() {
      document.getElementById('tradeOverlay').style.display = 'none';
      document.body.style.overflow = '';
    }

    function _tradeShowStep(n) {
      _tradeStep = n;
      [1,2,3,4].forEach(i => {
        document.getElementById('tradeStep' + i).style.display = i === n ? '' : 'none';
      });
      const labels = ['상대방 검색', '내 카드 선택', '상대 카드 선택', '확인'];
      document.getElementById('tradeStepIndicator').textContent = `Step ${n}/4 — ${labels[n-1]}`;
    }

    async function tradeSearchUser() {
      const nick = document.getElementById('tradeTargetInput').value.trim();
      const el = document.getElementById('tradeSearchResult');
      if (!nick) { el.textContent = '닉네임을 입력해주세요.'; return; }
      if (nick === currentNickname) { el.textContent = '자기 자신과는 교환할 수 없어요.'; return; }
      const dotsTimerSearch = animDots(el, '검색 중');
      try {
        const res = await fetch(`${API_BASE}?action=getPublicCollection&userId=${encodeURIComponent(nick)}&t=${Date.now()}`, { cache: 'no-store' }).then(r => r.json());
        if (!res.ok) { stopAnimDots(dotsTimerSearch, el, '찾을 수 없는 닉네임이에요.'); return; }
        const hasCards = Object.values(res.collection || {}).some(v => v >= 2);
        if (!hasCards) { stopAnimDots(dotsTimerSearch, el, `${nick}님은 교환 가능한 중복 카드가 없어요.`); return; }
        _tradeTargetNickname = nick;
        _tradeTargetColl = res.collection || {};
        stopAnimDots(dotsTimerSearch, el, '');
        el.innerHTML = `<span style="color:#4ade80;font-weight:700;">✓ ${nick}님을 찾았어요!</span>`;
        setTimeout(() => {
          if (_tradeMyCardId) _tradeShowStep(3), _renderTheirCards();
          else _tradeShowStep(2), _renderMyCards();
        }, 600);
      } catch(e) { stopAnimDots(dotsTimerSearch, el, '검색 실패. 다시 시도해주세요.'); }
    }

    function _renderMyCards() {
      const counts = {};
      (userStatus.collection || []).forEach(c => { counts[c.id] = (counts[c.id] || 0) + 1; });
      const container = document.getElementById('tradeMyCards');
      container.innerHTML = SPIRIT_CARDS.map(card => {
        const cnt = counts[card.id] || 0;
        if (cnt < 2) return ''; // 중복(2장 이상)만 교환 가능
        const sel = _tradeMyCardId === card.id ? 'outline:2.5px solid #e8854a;' : '';
        return `<div class="mini-card-wrap" style="cursor:pointer;" onclick="tradeSelectMyCard(${card.id})">
          <div class="mini-card mini-card-img" style="${sel}">
            <img src="${card.img}" style="width:100%;height:100%;object-fit:contain;display:block;">
          </div>
          <div style="font-size:10px;text-align:center;margin-top:3px;color:var(--sub);">${card.name} ×${cnt}</div>
        </div>`;
      }).join('');
      if (!container.innerHTML.trim()) container.innerHTML = '<p style="color:var(--sub);font-size:13px;">중복 보유한 카드가 없어요.<br><span style="font-size:11px;color:var(--line);">같은 카드를 2장 이상 가진 경우 교환할 수 있어요.</span></p>';
    }

    function tradeSelectMyCard(cardId) {
      _tradeMyCardId = cardId;
      _renderMyCards();
      setTimeout(() => { _tradeShowStep(3); _renderTheirCards(); }, 300);
    }

    function _renderTheirCards() {
      document.getElementById('tradeTargetName').textContent = _tradeTargetNickname;
      const myCard = SPIRIT_CARDS.find(c => c.id === _tradeMyCardId);
      if (myCard) document.getElementById('tradePreviewMine').innerHTML = `<img src="${myCard.img}" style="width:100%;height:100%;object-fit:contain;">`;
      if (_tradeTheirCardId) {
        const tc = SPIRIT_CARDS.find(c => c.id === _tradeTheirCardId);
        if (tc) document.getElementById('tradePreviewTheirs').innerHTML = `<img src="${tc.img}" style="width:100%;height:100%;object-fit:contain;">`;
      } else {
        document.getElementById('tradePreviewTheirs').innerHTML = `<span style="font-size:18px;color:var(--sub);">?</span>`;
      }
      const container = document.getElementById('tradeTheirCards');
      container.innerHTML = SPIRIT_CARDS.map(card => {
        const cnt = _tradeTargetColl[card.id] || 0;
        if (cnt < 2) return '';
        const sel = _tradeTheirCardId === card.id ? 'outline:2.5px solid #7c3aed;' : '';
        return `<div class="mini-card-wrap" style="cursor:pointer;" onclick="tradeSelectTheirCard(${card.id})">
          <div class="mini-card mini-card-img" style="${sel}">
            <img src="${card.img}" style="width:100%;height:100%;object-fit:contain;display:block;">
          </div>
          <div style="font-size:10px;text-align:center;margin-top:3px;color:var(--sub);">${card.name}</div>
        </div>`;
      }).join('');
      if (!container.innerHTML.trim()) container.innerHTML = '<p style="color:var(--sub);font-size:13px;">상대방이 교환 가능한 중복 카드가 없어요.</p>';
    }

    function tradeSelectTheirCard(cardId) {
      _tradeTheirCardId = cardId;
      const tc = SPIRIT_CARDS.find(c => c.id === cardId);
      if (tc) document.getElementById('tradePreviewTheirs').innerHTML = `<img src="${tc.img}" style="width:100%;height:100%;object-fit:contain;">`;
      _renderTheirCards();
      const myCard = SPIRIT_CARDS.find(c => c.id === _tradeMyCardId);
      const theirCard = SPIRIT_CARDS.find(c => c.id === _tradeTheirCardId);
      document.getElementById('tradeConfirmText').innerHTML =
        `내 <strong style="color:#e8854a;">${myCard.name}</strong> 카드를 주고<br>${_tradeTargetNickname}님의 <strong style="color:#a78bfa;">${theirCard.name}</strong> 카드를 받습니다.`;
      document.getElementById('tradeSubmitStatus').textContent = '';
      document.getElementById('tradeSubmitBtn').disabled = false;
      setTimeout(() => _tradeShowStep(4), 300);
    }

    function tradeGoBack() {
      if (_tradeStep === 4) { _tradeShowStep(3); _renderTheirCards(); }
      else if (_tradeStep === 3) { _tradeShowStep(2); _renderMyCards(); }
      else if (_tradeStep === 2) { _tradeShowStep(1); }
    }

    async function submitTradeRequest() {
      const btn = document.getElementById('tradeSubmitBtn');
      const statusEl = document.getElementById('tradeSubmitStatus');
      // 최종 제출 전 내 카드 중복 재검증
      const counts = {};
      (userStatus?.collection || []).forEach(c => { counts[c.id] = (counts[c.id] || 0) + 1; });
      if (!_tradeMyCardId || (counts[_tradeMyCardId] || 0) < 2) {
        statusEl.style.color = 'var(--danger)';
        statusEl.textContent = '같은 카드 2장 이상인 경우만 교환할 수 있어요.';
        return;
      }
      btn.disabled = true;
      const dotsTimerTrade = animDots(statusEl, '전송 중');
      try {
        const res = await post({
          action: 'requestTrade',
          nickname: currentNickname,
          requesterCardId: _tradeMyCardId,
          targetNickname: _tradeTargetNickname,
          targetCardId: _tradeTheirCardId
        });
        if (res.ok) {
          stopAnimDots(dotsTimerTrade, statusEl, '✓ 교환 신청이 전송됐어요!');
          statusEl.style.color = '#4ade80';
          setTimeout(() => { closeTradeModal(); loadTrades(); }, 1200);
        } else {
          stopAnimDots(dotsTimerTrade, statusEl, res.error || '오류가 발생했어요.');
          statusEl.style.color = 'var(--danger)';
          btn.disabled = false;
        }
      } catch(e) { stopAnimDots(dotsTimerTrade, statusEl, '연결 오류'); btn.disabled = false; }
    }

    let _loadTradesPromise = null;
    async function loadTrades() {
      if (!currentNickname) return;
      if (_loadTradesPromise) return _loadTradesPromise;
      _loadTradesPromise = (async () => {
      try {
        const res = await fetch(`${API_BASE}?action=getTrades&userId=${encodeURIComponent(currentNickname)}${sessionParam()}&t=${Date.now()}`, { cache: 'no-store' }).then(r => r.json());
        if (!res.ok) return;
        _cachedTrades = res;
        const all = [...(res.incoming || []), ...(res.outgoing || [])];
        const pendingIn = (res.incoming || []).filter(t => t.status === 'pending').length;
        const unprayed  = all.filter(t => {
          if (t.status !== 'accepted' || !t.otherPrayer) return false;
          const isMine = t.requester === currentNickname;
          return isMine ? !t.requesterPrayed : !t.targetPrayed;
        }).length;
        const unseenPray = all.filter(t => {
          if (t.status !== 'accepted') return false;
          const isMine = t.requester === currentNickname;
          const theirPrayed = isMine ? t.targetPrayed : t.requesterPrayed;
          return theirPrayed && !localStorage.getItem('beyondus_seen_pray_' + t.id);
        }).length;
        // 교환 완료로 새로 받은 카드 추적 (이전 목록과 비교해 진짜 신규만)
        if (!localStorage.getItem('beyondus_nc_migrated')) {
          Object.keys(localStorage).filter(k => k.startsWith('beyondus_new_card_')).forEach(k => localStorage.removeItem(k));
          localStorage.setItem('beyondus_nc_migrated', '1');
        }
        const knownRaw = localStorage.getItem('beyondus_known_accepts');
        const knownAccepts = new Set(JSON.parse(knownRaw || '[]'));
        const currentAccepts = all.filter(t => t.status === 'accepted').map(t => t.id);
        if (knownRaw !== null) {
          currentAccepts.forEach(id => {
            if (!knownAccepts.has(id)) {
              const t = all.find(tr => tr.id === id);
              if (!t) return;
              const isMine = t.requester === currentNickname;
              localStorage.setItem('beyondus_new_card_' + id, String(isMine ? t.targetCardId : t.requesterCardId));
            }
          });
          // 고아 항목 제거 (거절/취소된 교환 잔재)
          Object.keys(localStorage).filter(k => k.startsWith('beyondus_new_card_') && !currentAccepts.includes(k.replace('beyondus_new_card_', ''))).forEach(k => localStorage.removeItem(k));
        }
        localStorage.setItem('beyondus_known_accepts', JSON.stringify(currentAccepts));
        const ownedIds = new Set((userStatus?.collection || []).map(c => c.id));
        const newCardCount = Object.keys(localStorage).filter(k => k.startsWith('beyondus_new_card_')).filter(k => currentAccepts.includes(k.replace('beyondus_new_card_', ''))).filter(k => ownedIds.has(Number(localStorage.getItem(k)))).length;
        const tradeTotal = pendingIn + unprayed + unseenPray;
        const grandTotal = tradeTotal + newCardCount;
        const dot      = document.getElementById('drawerTradeDot');
        const badge    = document.getElementById('collTradeBadge');
        const menuDot  = document.getElementById('tradeMenuDot');
        localStorage.setItem('beyondus_trade_dot', grandTotal > 0 ? '1' : '0');
        const collNewBadge = document.getElementById('collNewCardBadge');
        dot.style.display   = grandTotal > 0 ? 'inline-block' : 'none';
        badge.style.display = (tradeTotal + newCardCount) > 0 ? 'inline-block' : 'none';
        collNewBadge.style.display = newCardCount > 0 ? 'inline-block' : 'none';
        if (grandTotal > 0) menuDot.classList.add('visible');
        else menuDot.classList.remove('visible');
        renderTrades(res);
        const tradeCollectionSig = [
          currentAccepts.join('|'),
          newCardCount,
          getUserStatusRenderSignature(userStatus)
        ].join('::');
        if (newCardCount > 0 && tradeCollectionSig !== _lastTradeCollectionRenderSig) {
          _lastTradeCollectionRenderSig = tradeCollectionSig;
          renderCollection();
        } else if (newCardCount === 0) {
          _lastTradeCollectionRenderSig = '';
        }
      } catch(e) {}
      finally { _loadTradesPromise = null; }
      })();
      return _loadTradesPromise;
    }

    async function markPrayed(tradeId, btn) {
      if (btn) {
        const label = document.createElement('span');
        label.className = 'prayed-label';
        label.textContent = '기도완료 ✓';
        btn.parentElement.replaceChild(label, btn);
      }
      try {
        const res = await post({ action: 'prayForTrade', tradeId, nickname: currentNickname });
        if (res.ok) loadTrades();
        else alert(res.error || res.message || '오류가 발생했어요.');
      } catch(e) { alert('연결 오류: ' + e.message); }
    }

    function renderTrades(data) {
      const el = document.getElementById('tradesList');
      if (!el) return;
      const incoming = data.incoming || [];
      const outgoing = data.outgoing || [];
      if (!incoming.length && !outgoing.length) {
        el.innerHTML = '<p class="card-sub">교환 내역이 없어요.</p>'; return;
      }
      const renderItem = (t, isMine) => {
        const myCard = isMine ? t.requesterCardName : t.targetCardName;
        const theirCard = isMine ? t.targetCardName : t.requesterCardName;
        const otherNick = isMine ? t.target : t.requester;
        const isAccepted = t.status === 'accepted';
        const isPending  = t.status === 'pending';

        if (isAccepted) {
          const myPrayed    = isMine ? t.requesterPrayed : t.targetPrayed;
          const theirPrayed = isMine ? t.targetPrayed    : t.requesterPrayed;
          const hasPrayer   = !!t.otherPrayer;
          const theirCardId = isMine ? t.targetCardId : t.requesterCardId;
          const isNewCard   = !!localStorage.getItem('beyondus_new_card_' + t.id);

          const prayBtnHtml = hasPrayer
            ? (myPrayed
                ? `<span class="prayed-label">기도완료 ✓</span>`
                : `<button class="pray-btn" onclick="markPrayed('${t.id}',this)">기도했어요!</button>`)
            : '';
          const stampSeen = localStorage.getItem('beyondus_seen_pray_' + t.id);
          const theirPrayHtml = theirPrayed
            ? `<div class="pray-stamp${stampSeen ? ' seen' : ''}">${escHtml(otherNick)}님이 나를 위해 기도했어요.</div>`
            : '';
          const prayerHtml = hasPrayer
            ? `<p style="margin:10px 0 0;font-size:12px;color:var(--sub);line-height:1.75;font-style:italic;">"${escHtml(t.otherPrayer)}"</p>${theirPrayHtml ? `<div>${theirPrayHtml}</div>` : ''}`
            : (theirPrayHtml ? `<div>${theirPrayHtml}</div>` : '');
          const newDot = isNewCard ? `<span style="display:inline-block;width:7px;height:7px;background:#e05a5a;border-radius:50%;flex-shrink:0;margin-left:4px;vertical-align:middle;"></span>` : '';

          return `<div style="border:1px solid var(--line);border-radius:14px;padding:14px 16px;margin-bottom:8px;position:relative;">
            <div style="display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:8px;">
              <div style="display:flex;align-items:baseline;gap:6px;">
                <span style="font-size:14px;font-weight:700;color:var(--text);">${escHtml(otherNick)}</span>
                <span style="font-size:12px;color:var(--sub);">과 교환 완료</span>
              </div>
              <div style="display:flex;align-items:center;gap:4px;flex-shrink:0;">${prayBtnHtml}</div>
            </div>
            <div style="display:flex;align-items:center;gap:8px;font-size:13px;">
              <span style="font-weight:600;color:var(--text);">${escHtml(myCard)}</span>
              <span style="color:var(--line);">↔</span>
              <span style="font-weight:600;color:var(--text);">${escHtml(theirCard)}${newDot}</span>
            </div>
            ${prayerHtml}
          </div>`;
        }

        const isIncomingPending = isPending && !isMine;
        const labelMap = { pending: isMine ? '대기중' : `${escHtml(otherNick)}님의 교환요청`, rejected: '거절됨', cancelled: '취소됨', '실패 (시간 초과)': '5분 초과 자동 취소' };
        const label = labelMap[t.status] || t.status;
        const labelColor = isPending ? 'var(--text)' : 'var(--sub)';
        const actions = isPending
          ? (isMine
            ? `<button onclick="doTradeCancelTrade('${t.id}')" style="font-size:11px;padding:4px 12px;border-radius:999px;border:1px solid var(--line);background:transparent;color:var(--sub);cursor:pointer;">취소</button>`
            : `<div style="display:flex;gap:6px;">
                <button onclick="doTradeAccept('${t.id}')" style="font-size:11px;padding:4px 12px;border-radius:999px;border:none;background:var(--primary);color:var(--bg);cursor:pointer;font-weight:700;">수락</button>
                <button onclick="doTradeReject('${t.id}')" style="font-size:11px;padding:4px 12px;border-radius:999px;border:1px solid var(--line);background:transparent;color:var(--sub);cursor:pointer;">거절</button>
              </div>`)
          : '';
        const remainMs = isPending ? (new Date(t.createdAt).getTime() + 5*60*1000 - Date.now()) : 0;
        const remainSec = Math.max(0, Math.floor(remainMs / 1000));
        const remainMin = Math.floor(remainSec / 60);
        const remainSecPart = remainSec % 60;
        const timerHtml = isPending && remainMs > 0
          ? `<span id="tradeTimer_${t.id}" style="font-size:11px;color:#e25;font-weight:700;">⏱ ${remainMin}분 ${String(remainSecPart).padStart(2,'0')}초 남음</span>`
          : (isPending ? `<span style="font-size:11px;color:var(--sub);">만료 처리 중...</span>` : '');
        return `<div style="background:var(--primary-soft);border:1px solid var(--line);border-radius:14px;padding:12px 16px;margin-bottom:8px;">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;">
            <div style="display:flex;align-items:center;gap:6px;">
              <span style="font-size:12px;font-weight:700;color:${labelColor};">${label}</span>
              ${isIncomingPending ? `<span style="display:inline-block;width:7px;height:7px;background:#e05a5a;border-radius:50%;flex-shrink:0;"></span>` : ''}
            </div>
            <div style="display:flex;align-items:center;gap:6px;">
              ${timerHtml}
              ${!isIncomingPending ? `<span style="font-size:11px;color:var(--sub);">${escHtml(otherNick)}</span>` : ''}
            </div>
          </div>
          <div style="font-size:13px;color:var(--text);">
            <span style="font-weight:600;">${escHtml(myCard)}</span>
            <span style="color:var(--sub);padding:0 6px;">↔</span>
            <span style="font-weight:600;">${escHtml(theirCard)}</span>
          </div>
          ${actions ? `<div style="margin-top:10px;">${actions}</div>` : ''}
        </div>`;
      };

      let html = '';
      const pendingIn = incoming.filter(t => t.status === 'pending');
      if (pendingIn.length) {
        html += `<p style="font-size:12px;font-weight:700;color:var(--sub);margin:0 0 6px;">받은 요청</p>`;
        html += pendingIn.map(t => renderItem(t, false)).join('');
      }
      const pendingOut = outgoing.filter(t => t.status === 'pending');
      if (pendingOut.length) {
        html += `<p style="font-size:12px;font-weight:700;color:var(--sub);margin:${pendingIn.length ? '12px' : '0'} 0 6px;">보낸 요청</p>`;
        html += pendingOut.map(t => renderItem(t, true)).join('');
      }
      // 수락된 교환만 히스토리에 표시 (취소/거절은 자동 숨김)
      const resolved = [...incoming, ...outgoing]
        .filter(t => t.status === 'accepted')
        .sort((a,b) => b.resolvedAt.localeCompare(a.resolvedAt))
        .slice(0, 20);
      if (resolved.length) {
        html += `<p style="font-size:12px;font-weight:700;color:var(--sub);margin:12px 0 6px;">완료된 교환</p>`;
        html += resolved.map(t => renderItem(t, t.requester === currentNickname)).join('');
      }
      el.innerHTML = html || '<p class="card-sub">교환 내역이 없어요.</p>';
      // pending 항목 1초마다 카운트다운
      clearInterval(window._tradeCountdownTimer);
      const pendingItems = [...(data.incoming || []), ...(data.outgoing || [])].filter(t => t.status === 'pending');
      if (pendingItems.length) {
        window._tradeCountdownTimer = setInterval(() => {
          pendingItems.forEach(t => {
            const el = document.getElementById('tradeTimer_' + t.id);
            if (!el) return;
            const ms = new Date(t.createdAt).getTime() + 5*60*1000 - Date.now();
            if (ms <= 0) { el.textContent = '만료 처리 중...'; el.style.color = 'var(--sub)'; return; }
            const s = Math.floor(ms/1000); el.textContent = `⏱ ${Math.floor(s/60)}분 ${String(s%60).padStart(2,'0')}초 남음`;
          });
        }, 1000);
      }
      // 교환현황 탭이 실제로 열려있을 때만 상대 기도 알림 "봤음" 처리
      const tradesVisible = document.getElementById('collPanelTrades') && document.getElementById('collPanelTrades').style.display !== 'none';
      if (tradesVisible) {
        const allT = [...(data.incoming || []), ...(data.outgoing || [])];
        allT.forEach(t => {
          if (t.status !== 'accepted') return;
          const isMine = t.requester === currentNickname;
          const theirPrayed = isMine ? t.targetPrayed : t.requesterPrayed;
          if (theirPrayed) localStorage.setItem('beyondus_seen_pray_' + t.id, '1');
        });
      }
    }

    async function doTradeAccept(tradeId) {
      if (!confirm('교환을 수락할까요?')) return;
      try {
        const res = await post({ action: 'acceptTrade', tradeId, nickname: currentNickname });
        if (res.ok) {
          // 수락한 사람은 새 카드 알림 불필요 — known에 미리 추가
          const ka = JSON.parse(localStorage.getItem('beyondus_known_accepts') || '[]');
          if (!ka.includes(tradeId)) { ka.push(tradeId); localStorage.setItem('beyondus_known_accepts', JSON.stringify(ka)); }
          alert('교환이 완료됐어요! 🎉'); Promise.all([loadUserStatus(), loadTrades()]);
        }
        else alert(res.error || '수락 실패');
      } catch(e) { alert('연결 오류'); }
    }

    async function doTradeReject(tradeId) {
      if (!confirm('교환을 거절할까요?')) return;
      try {
        const res = await post({ action: 'rejectTrade', tradeId, nickname: currentNickname });
        if (res.ok) loadTrades();
        else alert(res.error || '거절 실패');
      } catch(e) { alert('연결 오류'); }
    }

    async function doTradeCancelTrade(tradeId) {
      if (!confirm('교환 신청을 취소할까요?')) return;
      try {
        const res = await post({ action: 'cancelTrade', tradeId, nickname: currentNickname });
        if (res.ok) loadTrades();
        else alert(res.error || '취소 실패');
      } catch(e) { alert('연결 오류'); }
    }

    /* ════ userStatus API ════ */
    function getUserStatusRenderSignature(status) {
      if (!status || status.error) return 'empty';
      const counts = {};
      (status.collection || []).forEach(c => { counts[c.id] = (counts[c.id] || 0) + 1; });
      const collectionSig = SPIRIT_CARDS.concat([HIDDEN_CARD])
        .map(c => `${c.id}:${counts[c.id] || 0}`)
        .join('|');
      return [
        status.weekScore || 0,
        status.pendingDraws || 0,
        status.earnedTicketThisWeek ? 1 : 0,
        status.drawnThisWeek ? 1 : 0,
        (status.todayIndices || []).join(','),
        (status.weekDates || []).join(','),
        collectionSig
      ].join('::');
    }

    let _loadUserStatusPromise = null;
    async function loadUserStatus(options) {
      if (_loadUserStatusPromise) return _loadUserStatusPromise;
      _loadUserStatusPromise = (async () => {
      const opts = options || {};
      if (!currentNickname) { renderDrawSection(); return; }
      const prevSig = getUserStatusRenderSignature(userStatus);
      let usedCachedStatus = false;
      if (!opts.silent) {
        try {
          const cached = JSON.parse(localStorage.getItem('beyondus_cache_userStatus_' + currentNickname) || 'null');
          if (cached && cached.ok) {
            userStatus = cached;
            usedCachedStatus = true;
            renderDrawSection();
            renderCollection();
            updateScoreProgress();
            if (lastConfigData) renderConfig(lastConfigData);
          } else {
            renderDrawSection();
          }
        } catch(e) {
          renderDrawSection();
        }
      }
      try {
        const res = await fetch(
          `${API_BASE}?action=userStatus&userId=${encodeURIComponent(currentNickname)}&weekKey=${getWeekKey()}${sessionParam()}&t=${Date.now()}`,
          { cache: 'no-store' }
        );
        if (!res.ok) throw new Error();
        userStatus = await res.json();
        if (currentNickname) localStorage.setItem('beyondus_cache_userStatus_' + currentNickname, JSON.stringify(userStatus));
        // 서버 기준으로 이번 주 스탬프 동기화 (서버가 비어있으면 로컬도 지움)
        {
          const mon = new Date(); const dow = mon.getDay() || 7;
          mon.setDate(mon.getDate() - (dow - 1)); mon.setHours(0,0,0,0);
          const thisWeekKeys = Array.from({length:7}, (_,i) => {
            const d = new Date(mon); d.setDate(mon.getDate()+i);
            return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
          });
          const stored = JSON.parse(localStorage.getItem('beyondus_check_dates') || '[]');
          const other  = stored.filter(d => !thisWeekKeys.includes(d));
          const synced = [...new Set([...other, ...(userStatus.weekDates || [])])];
          localStorage.setItem('beyondus_check_dates', JSON.stringify(synced));
          renderWeekCal();
        }
      } catch(e) {
        if (!usedCachedStatus) userStatus = { error: true };
      }
      const nextSig = getUserStatusRenderSignature(userStatus);
      const changed = prevSig !== nextSig;
      if (!opts.silent || changed) {
        renderDrawSection();
        renderCollection();
        updateScoreProgress();
        if (lastConfigData) renderConfig(lastConfigData);
      }
      })().finally(() => { _loadUserStatusPromise = null; });
      return _loadUserStatusPromise;
    }

    function ensureRevealSparks() {
      var layer = document.getElementById('effectsLayer');
      if (!layer) return [];
      var sparks = layer.querySelectorAll('.spark');
      if (sparks.length) return Array.from(sparks);

      var colorClasses = ['', 'spark-pink', 'spark-cyan', 'spark-gold', 'spark-pink', 'spark-gold', ''];
      var frag = document.createDocumentFragment();
      for (var i = 0; i < 28; i++) {
        var s = document.createElement('span');
        s.className = 'spark ' + colorClasses[i % colorClasses.length];
        frag.appendChild(s);
      }
      layer.appendChild(frag);
      return Array.from(layer.querySelectorAll('.spark'));
    }

    function resetRevealSparks() {
      ensureRevealSparks().forEach(function(el) {
        gsap.set(el, { opacity: 0, x: 0, y: 0, scale: 0.2 });
      });
    }

    function burstRevealSparks(power) {
      power = power || 1;
      var sparks = ensureRevealSparks();
      var count = sparks.length;
      sparks.forEach(function(el, i) {
        var angle = (Math.PI * 2 * i) / count + (Math.random() * 0.18 - 0.09);
        var radius = (90 + Math.random() * 88) * power;
        var dx = Math.cos(angle) * radius;
        var dy = Math.sin(angle) * radius * 0.80;
        var delay = Math.random() * 0.04;

        gsap.fromTo(el,
          { x: 0, y: 0, scale: 0.12 + Math.random() * 0.24, opacity: 0 },
          {
            x: dx, y: dy,
            scale: 1.0 + Math.random() * 1.0,
            opacity: 1,
            duration: 0.15 + delay,
            ease: 'power2.out',
            delay: delay,
            onComplete: function() {
              gsap.to(el, {
                opacity: 0,
                scale: 0.18,
                duration: 0.52 + Math.random() * 0.28,
                ease: 'power2.out'
              });
            }
          }
        );

        gsap.to(el, {
          y: dy + (Math.random() * 26 - 13),
          duration: 0.72 + Math.random() * 0.28,
          ease: 'power2.out'
        });
      });
    }

    /* ════ 뽑기 오버레이 (GSAP 시네마틱) ════ */
    let drawState = 'idle';
    let drawResult = null;
    let drawIsNew = true;   // 신규(true) vs 중복(false) — GAS isNew 필드 반영
    let revealClickEnabled = false;
    let isFlipping = false;
    let loadingDotsTimer = null;
    let spinAutoRevealTimer = null; // 10초 후 자동 공개 타이머
    let drawOverlayActive = false;
    let drawScheduledTimers = [];
    let drawPreCollectionCounts = {};
    let drawRequestId = '';
    let drawServerCollection = null;
    let drawServerTickets = null;

    function scheduleDrawTimer(fn, delay) {
      var id = setTimeout(function() {
        drawScheduledTimers = drawScheduledTimers.filter(function(t) { return t !== id; });
        if (!drawOverlayActive) return;
        fn();
      }, delay);
      drawScheduledTimers.push(id);
      return id;
    }

    function clearDrawTimers() {
      drawScheduledTimers.forEach(function(id) { clearTimeout(id); });
      drawScheduledTimers = [];
      if (spinAutoRevealTimer) { clearTimeout(spinAutoRevealTimer); spinAutoRevealTimer = null; }
    }

    function getCollectionCountsFromStatus() {
      const counts = {};
      (userStatus?.collection || []).forEach(function(card) {
        if (!card || !card.id) return;
        counts[card.id] = (counts[card.id] || 0) + 1;
      });
      return counts;
    }

    function setLocalCollectionCount(card, targetCount) {
      if (!userStatus || !card) return;
      if (!userStatus.collection) userStatus.collection = [];
      const next = [];
      let current = 0;
      userStatus.collection.forEach(function(c) {
        if (c && c.id === card.id) current++;
        else next.push(c);
      });
      for (let i = 0; i < targetCount; i++) next.push(card);
      userStatus.collection = next;
    }

    function applyCollectionCountsToStatus(collectionCounts) {
      if (!userStatus || !collectionCounts) return false;
      const next = [];
      SPIRIT_CARDS.forEach(function(card) {
        const cnt = Number(collectionCounts[card.id]) || 0;
        for (let i = 0; i < cnt; i++) next.push(card);
      });
      userStatus.collection = next;
      return true;
    }

    /* 파티클 생성 (lazy) */
    const STAR_COUNT = 50;
    const EMBER_COUNT = 12;
    var _drawParticlesReady = false;
    function ensureDrawParticles() {
      if (_drawParticlesReady) return;
      var layer = document.getElementById('particleLayer');
      if (!layer) return;
      var frag = document.createDocumentFragment();
      for (var i = 0; i < STAR_COUNT; i++) {
        var s = document.createElement('span');
        s.className = 'star-ptcl';
        frag.appendChild(s);
      }
      for (var j = 0; j < EMBER_COUNT; j++) {
        var e = document.createElement('span');
        e.className = 'ember-ptcl';
        frag.appendChild(e);
      }
      layer.appendChild(frag);
      _drawParticlesReady = true;
    }

    function resetDrawParticles() {
      var layer = document.getElementById('particleLayer');
      if (!layer) return;
      ensureDrawParticles();
      var particles = layer.querySelectorAll('.star-ptcl, .ember-ptcl');
      if (!particles.length) return;
      gsap.set(particles, { opacity: 0, x: 0, y: 0, scale: 0.3 });
    }

    function twinkleGoldStars() {
      ensureDrawParticles();
      var stars = document.querySelectorAll('.star-ptcl');
      stars.forEach(function(el) {
        // 배경 전체에 랜덤 배치 (sceneWrap 영역 ± 여백)
        var x = (Math.random() - 0.5) * 500;
        var y = (Math.random() - 0.5) * 720;
        var size = 0.5 + Math.random() * 1.4;
        var delay1 = Math.random() * 1.6;
        var delay2 = delay1 + 0.55 + Math.random() * 0.5;
        var delay3 = delay2 + 0.55 + Math.random() * 0.4;
        gsap.set(el, { opacity: 0, x: x, y: y, scale: size * 0.2 });
        // 1번째 반짝
        gsap.to(el, { opacity: 0.75 + Math.random() * 0.25, scale: size, duration: 0.20 + Math.random() * 0.15, delay: delay1, ease: 'power2.out' });
        gsap.to(el, { opacity: 0, scale: size * 0.15, duration: 0.32, delay: delay1 + 0.22 + Math.random() * 0.15, ease: 'power2.in' });
        // 2번째 반짝
        gsap.to(el, { opacity: 0.6 + Math.random() * 0.35, scale: size * 0.9, duration: 0.18 + Math.random() * 0.12, delay: delay2, ease: 'power2.out' });
        gsap.to(el, { opacity: 0, scale: size * 0.1, duration: 0.38, delay: delay2 + 0.20 + Math.random() * 0.15, ease: 'power2.in' });
        // 3번째 반짝 (약하게)
        if (delay3 < 3.8) {
          gsap.to(el, { opacity: 0.4 + Math.random() * 0.3, scale: size * 0.7, duration: 0.16 + Math.random() * 0.10, delay: delay3, ease: 'power2.out' });
          gsap.to(el, { opacity: 0, scale: 0, duration: 0.45, delay: delay3 + 0.18 + Math.random() * 0.12, ease: 'power2.in' });
        }
      });
    }

    function startLoadingDots() {
      const el = document.getElementById('cardLoadingHint');
      const steps = ['두 근 두 근', '두 근 두 근 .', '두 근 두 근 . .', '두 근 두 근 . . .', '두 근 두 근 . . . !'];
      let i = 0;
      el.textContent = steps[0];
      loadingDotsTimer = setInterval(function() {
        i = (i + 1) % steps.length;
        el.textContent = steps[i];
      }, 600);
    }

    function stopLoadingDots() {
      if (loadingDotsTimer) {
        clearInterval(loadingDotsTimer);
        loadingDotsTimer = null;
      }
    }

    function animDots(el, baseText) {
      const steps = [baseText + '.', baseText + '..', baseText + '...'];
      let i = 0;
      el.textContent = steps[0];
      return setInterval(function() { i = (i + 1) % 3; el.textContent = steps[i]; }, 400);
    }
    function stopAnimDots(timerId, el, finalText) {
      clearInterval(timerId);
      if (el && finalText !== undefined) el.textContent = finalText;
    }

    var carouselCenter = 1; // 현재 가운데 팩 인덱스 (0,1,2)

    function applyCarouselPositions() {
      ['cpack0','cpack1','cpack2'].forEach(function(id, i) {
        var el = document.getElementById(id);
        if (!el) return;
        if (i === carouselCenter)            el.dataset.pos = 'center';
        else if (i === (carouselCenter+2)%3) el.dataset.pos = 'left';
        else                                 el.dataset.pos = 'right';
      });
    }

    function openDrawOverlay() {
      drawOverlayActive = true;
      drawState = 'carousel';
      drawResult = null;
      drawIsNew = true;
      revealClickEnabled = false;
      isFlipping = false;
      pendingCard = null;
      drawPreCollectionCounts = getCollectionCountsFromStatus();
      drawRequestId = 'draw_' + Date.now() + '_' + Math.random().toString(36).slice(2, 10);
      drawServerCollection = null;
      drawServerTickets = null;
      carouselCenter = 1;

      preloadSfx();
      startBgm();

      gsap.killTweensOf(document.querySelectorAll('#drawOverlay *'));
      resetRevealSparks();

      applyCarouselPositions();

      gsap.set('#carouselLayer', { opacity: 0, pointerEvents: 'none' });

      gsap.set('#packLayer', { opacity: 0, pointerEvents: 'none' });
      gsap.set('#drawPack', {
        scale: 0.55,
        opacity: 1,
        y: 0,
        rotate: 0,
        rotateX: 0,
        filter: 'drop-shadow(0 18px 34px rgba(0,0,0,0.42))'
      });
      document.getElementById('drawPack').style.clipPath = '';
      document.getElementById('packTearLight').style.width = '0%';
      gsap.set('#packHint', { opacity: 0, y: -10 });
      gsap.set('#packTopPiece', { opacity: 0, y: 0, rotate: 0, rotateZ: 0 });
      gsap.set('#packInnerGlow', { opacity: 0, scale: 0.8 });
      gsap.set('#packCardPreview', { opacity: 0, scale: 0.9, y: 18 });

      gsap.set('#cardLayer', { opacity: 0, pointerEvents: 'none' });
      gsap.set('#cardGlow', { opacity: 0, scale: 0.7 });
      gsap.set('#cardInner', {
        rotateY: 0,
        rotateX: 0,
        rotateZ: 0,
        scale: 1,
        y: 0,
        force3D: true,
        transformPerspective: 1200
      });
      gsap.set('#cardTrigger', {
        y: 0,
        rotateZ: 0,
        rotateX: 0,
        scale: 1
      });
      gsap.set('#cardFlipShine', { opacity: 0, x: '-150%' });
      gsap.set('#settleActions', { opacity: 0, display: 'none' });
      gsap.set('#flipHint', { opacity: 0, y: 6 });
      stopLoadingDots();
      gsap.set('#cardLoadingHint', { opacity: 0 });

      gsap.set('#sceneGlow', { opacity: 0, scale: 0.8 });
      gsap.set('#starBg', { opacity: 0 });
      gsap.set('#crossAfterglow', { opacity: 0, scale: 0.86, rotate: 0, xPercent: -50, yPercent: -50 });
      gsap.set('#revealCross', { opacity: 0, scale: 0.78, rotate: 0, xPercent: -50, yPercent: -50 });
      gsap.set('#flashEl', { opacity: 0 });
      gsap.set('#ringEl',  { opacity: 0, scale: 0.42 });
      gsap.set('#ringEl2', { opacity: 0, scale: 0.38 });
      gsap.set('#ringEl3', { opacity: 0, scale: 0.34 });
      gsap.set('#cardBeam',     { opacity: 0 });
      gsap.set('#cardBeamCore', { opacity: 0 });
      gsap.set('#cardBeamV',    { opacity: 0 });
      document.getElementById('cardGlow').classList.remove('glow-new', 'glow-dup');
      document.getElementById('sceneGlow').classList.remove('glow-new', 'glow-dup');
      clearDrawTimers();
      resetDrawParticles();

      document.getElementById('cardFace').innerHTML = '';
      document.getElementById('flipHint').textContent = '';
      document.getElementById('cardTrigger').classList.remove('clickable');

      document.getElementById('drawOverlay').classList.remove('hidden');

      gsap.timeline()
        .to('#starBg', { opacity: 1, duration: 0.55, ease: 'power2.out' }, 0)
        .to('#carouselLayer', {
          opacity: 1,
          duration: 0.46,
          delay: 0.08,
          onStart: function() {
            gsap.set('#carouselLayer', { pointerEvents: 'auto' });
          }
        }, 0.08);
    }

    function closeDrawOverlay() {
      drawOverlayActive = false;
      clearDrawTimers();
      stopLoadingDots();
      stopBgm();
      stopAllSfx();
      gsap.killTweensOf(document.querySelectorAll('#drawOverlay *'));
      document.getElementById('drawOverlay').classList.add('hidden');
      // glow 클래스 초기화 (다음 뽑기를 위해)
      document.getElementById('cardGlow').classList.remove('glow-new', 'glow-dup');
      document.getElementById('sceneGlow').classList.remove('glow-new', 'glow-dup');
      gsap.set('#crossAfterglow', { opacity: 0, rotate: 0 });
      gsap.set('#revealCross', { opacity: 0, rotate: 0 });
      gsap.set('#cardBeam',     { opacity: 0 });
      gsap.set('#cardBeamCore', { opacity: 0 });
      gsap.set('#cardBeamV',    { opacity: 0 });
      gsap.set('#ringEl3',   { opacity: 0 });
      resetDrawParticles();
      if (pendingCard) {
        if (userStatus) {
          userStatus.drawnThisWeek = true;
          userStatus.weekCard = pendingCard;
          if (!applyCollectionCountsToStatus(drawServerCollection)) {
            setLocalCollectionCount(pendingCard, (drawPreCollectionCounts[pendingCard.id] || 0) + 1);
          }
          userStatus.pendingDraws = drawServerTickets
            ? Number(drawServerTickets.remaining) || 0
            : Math.max(0, (userStatus.pendingDraws || 1) - 1);
        }
        renderDrawSection();
        renderCollection();
        pendingCard = null;
        switchSection('collection');
        loadUserStatus({ silent: true }).then(function() {
          renderCollection();
          renderDrawSection();
        }).catch(function() {});
      }
    }

    document.getElementById('drawCloseBtn').onclick = closeDrawOverlay;
    document.getElementById('revealDoneBtn').onclick = closeDrawOverlay;
    document.getElementById('drawMuteBtn').onclick = toggleSfxMute;
    updateMuteBtnUI();

    /* ════ 캐러셀 ════ */
    (function() {
      var trackEl  = document.getElementById('carouselTrack');
      var dragStartX = 0, dragging = false;

      function rotateCarousel(dir) {
        carouselCenter = (carouselCenter + dir + 3) % 3;
        applyCarouselPositions();
      }

      trackEl.addEventListener('pointerdown', function(e) {
        if (drawState !== 'carousel') return;
        e.preventDefault();
        dragStartX = e.clientX;
        dragging = true;
        trackEl.setPointerCapture(e.pointerId);
      });
      trackEl.addEventListener('pointermove', function(e) {
        if (!dragging) return;
      });
      trackEl.addEventListener('pointerup', function(e) {
        if (!dragging) return;
        dragging = false;
        var dx = e.clientX - dragStartX;
        if (Math.abs(dx) < 18) {
          // 탭 — 사이드팩이면 회전, 센터팩이면 선택
          var tapped = e.target.closest('.c-pack-wrap');
          var packs = [document.getElementById('cpack0'), document.getElementById('cpack1'), document.getElementById('cpack2')];
          if (tapped === packs[(carouselCenter+2)%3]) { rotateCarousel(-1); return; }
          if (tapped === packs[(carouselCenter+1)%3]) { rotateCarousel(1); return; }
          selectCenterPack();
        } else if (dx < -28) {
          rotateCarousel(1);
        } else if (dx > 28) {
          rotateCarousel(-1);
        }
      });
      trackEl.addEventListener('pointercancel', function() { dragging = false; });

      function selectCenterPack() {
        if (drawState !== 'carousel') return;
        drawState = 'pack_zoom';
        playSfx('packClick');
        gsap.set('#carouselLayer', { pointerEvents: 'none' });

        gsap.timeline({ onComplete: function() {
          drawState = 'pack_tear_slide';
          gsap.set('#packLayer', { pointerEvents: 'auto' });
          gsap.to('#packHint', { opacity: 1, duration: 0.4 });
        }})
        .to('#carouselLayer', { opacity: 0, duration: 0.28 })
        .set('#packLayer',    { opacity: 1 })
        .to('#drawPack',      { scale: 1.82, duration: 0.52, ease: 'power2.out' }, '<0.05');
      }
    })();

    /* ════ 팩 가로 찢기 ════ */
    (function() {
      var tearZone  = document.getElementById('packTearZone');
      var tearLight = document.getElementById('packTearLight');
      var active = false;

      tearZone.addEventListener('pointerdown', function(e) {
        if (drawState !== 'pack_tear_slide') return;
        e.preventDefault();
        active = true;
        tearZone.setPointerCapture(e.pointerId);
      });
      tearZone.addEventListener('pointermove', function(e) {
        if (!active) return;
        var rect = tearZone.getBoundingClientRect();
        var pct  = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
        tearLight.style.width = (pct * 100) + '%';
        if (pct >= 0.88) { active = false; completeTear(); }
      });
      tearZone.addEventListener('pointerup',     function() { active = false; });
      tearZone.addEventListener('pointercancel', function() { active = false; });

      function completeTear() {
        if (drawState !== 'pack_tear_slide') return;
        drawState = 'tearing_pack';
        playSfx('packOpen');
        gsap.set('#packLayer', { pointerEvents: 'none' });

        // GAS 프로젝트의 SPREADSHEET_ID Property가 가리키는 시트에 기록
        var cardPromise = fetch(API_BASE, {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain;charset=utf-8' },
          body: JSON.stringify(withSession({ action: 'drawCard', userId: currentNickname, weekKey: getWeekKey(), testMode: TEST_MODE, requestId: drawRequestId }))
        })
        .then(function(r) { return r.json(); })
        .catch(function() { return null; });
        cardPromise.then(function(result) {
          if (result && !result.error && result.card) {
            pendingCard = SPIRIT_CARDS.find(function(c) { return c.id === result.card.id; }) || result.card;
            drawIsNew = (result.isNew !== false); // false 명시 시만 중복, undefined/true → 신규
            drawServerCollection = result.collection || null;
            drawServerTickets = result.tickets || null;
          } else {
            pendingCard = null;
            drawResult = null;
            drawState = 'draw_failed';
            alert((result && (result.error || result.message)) || '카드 뽑기 저장에 실패했어요. 뽑기권은 사용되지 않았으니 다시 시도해주세요.');
            closeDrawOverlay();
            loadUserStatus().catch(() => {});
            return;
          }
          drawResult = pendingCard;
          document.getElementById('cardFace').innerHTML = makeCardHTML(drawResult);
          enableRevealClick();
        });

        var packRect = document.getElementById('drawPack').getBoundingClientRect();
        var wrapRect = document.getElementById('sceneWrap').getBoundingClientRect();
        var topPiece = document.getElementById('packTopPiece');

        topPiece.style.width = packRect.width + 'px';
        topPiece.style.height = Math.max(62, packRect.height * 0.10) + 'px';
        topPiece.style.left = (packRect.left - wrapRect.left) + 'px';
        topPiece.style.top = (packRect.top - wrapRect.top) + 'px';

        gsap.set('#packTopPiece', {
          opacity: 1,
          x: 0,
          y: 0,
          rotateZ: 0,
          transformOrigin: '50% 50%'
        });

        gsap.timeline({
          onComplete: function() {
            if (drawState === 'draw_failed') return;
            drawState = 'card_back_rise';
            playSfx('cardAppear');
            gsap.set('#packLayer', { opacity: 0, pointerEvents: 'none' });

            var tlB = gsap.timeline();

            gsap.set('#cardTrigger', {
              scale: 1.72,
              rotateZ: 0,
              rotateX: 0
            });

            tlB
              .set('#cardLayer', { pointerEvents: 'none' })
              .to('#cardLayer', { opacity: 1, duration: 0.22, ease: 'power2.out' }, 0)
              .to('#cardGlow', { opacity: 0.92, scale: 1, duration: 0.28, ease: 'power2.out' }, 0)
              .fromTo('#cardTrigger',
                { y: 128, rotateZ: -4, rotateX: 5, scale: 1.56 },
                { y: 0, rotateZ: 0, rotateX: 0, scale: 1.78, duration: 0.42, ease: 'power3.out' },
                0.04
              )
              .to('#sceneGlow', { opacity: 0.72, scale: 1.02, duration: 0.28, ease: 'power2.out' }, 0)
              // 카드가 자리 잡히자마자 바로 클릭 가능
              .call(function() {
                drawState = 'card_back_wait';
                gsap.set('#cardLoadingHint', { opacity: 0 });
                enableRevealClick();
              }, [], 0.46)
              .fromTo('#flipHint',
                { opacity: 0, y: 10 },
                { opacity: 0.72, y: 0, duration: 0.28, ease: 'power2.out' },
                0.46
              );
          }
        })
        .to('#packHint', { opacity: 0, y: -8, duration: 0.15 }, 0)
        .to('#packTearLight', { width: '100%', duration: 0.14, ease: 'power2.out' }, 0)
        .to('#packInnerGlow', { opacity: 1, scale: 1.16, duration: 0.22, ease: 'power2.out' }, 0.02)
        .to('#drawPack', {
          clipPath: 'polygon(0 12%, 100% 10%, 100% 100%, 0 100%)',
          duration: 0.18,
          ease: 'power1.out'
        }, 0.03)
        .fromTo('#packCardPreview',
          { opacity: 0, scale: 0.9, y: 20 },
          { opacity: 0.92, scale: 1.04, y: -10, duration: 0.34, ease: 'power2.out' },
          0.08
        )
        .to('#packTopPiece', {
          y: -78,
          x: 8,
          rotateZ: 12,
          opacity: 0.98,
          duration: 0.32,
          ease: 'power2.out'
        }, 0.07)
        .to('#packTopPiece', {
          y: -126,
          x: 26,
          rotateZ: 24,
          opacity: 0,
          duration: 0.46,
          ease: 'power2.in'
        }, 0.30)
        .to('#drawPack', {
          y: 160,
          opacity: 0,
          duration: 0.42,
          ease: 'power2.in'
        }, 0.22)
        .to('#packCardPreview', {
          opacity: 0,
          scale: 1.08,
          y: -46,
          duration: 0.34,
          ease: 'power2.in'
        }, 0.34);
      }
    })();

    function enableRevealClick() {
      if (drawState !== 'card_back_wait') return;
      if (!drawResult) return;
      if (revealClickEnabled) return;

      revealClickEnabled = true;

      document.getElementById('cardLayer').style.pointerEvents = 'auto';
      document.getElementById('cardTrigger').classList.add('clickable');
      document.getElementById('flipHint').innerHTML = '<em>Tap to flip the card open</em>';

      playSfx('tapToFlip');
      gsap.to('#flipHint', { opacity: 1, y: 0, duration: 0.34, ease: 'power2.out' });
      stopLoadingDots();
      document.getElementById('cardLoadingHint').textContent = '두 근 두 근 . . . !';

      gsap.to('#cardTrigger', {
        y: -11,
        duration: 1.55,
        ease: 'sine.inOut',
        yoyo: true,
        repeat: -1
      });
    }

    /* 카드 클릭 — Timeline C (3D 플립 공개) */
    document.getElementById('cardTrigger').addEventListener('click', function() {
      if (!revealClickEnabled || drawState !== 'card_back_wait') return;

      revealClickEnabled = false;
      drawState = 'card_flip_reveal';
      isFlipping = true;

      playSfx('mouseClick');
      playSfx('cardSpin');

      if (spinAutoRevealTimer) { clearTimeout(spinAutoRevealTimer); spinAutoRevealTimer = null; }
      gsap.killTweensOf('#cardTrigger');
      gsap.killTweensOf('#cardInner');
      gsap.killTweensOf('#cardGlow');
      gsap.killTweensOf('#crossAfterglow');
      gsap.killTweensOf('#revealCross');
      stopLoadingDots();
      gsap.to('#cardLoadingHint', { opacity: 0, duration: 0.15 });

      gsap.set('#cardTrigger', { y: -8, rotateY: 0, rotateZ: 0 }); // 스핀 정지 + 위치 초기화
      gsap.set('#cardInner', { rotateY: 0, rotateX: 0 });

      document.getElementById('cardTrigger').classList.remove('clickable');
      gsap.to('#flipHint', { opacity: 0, y: -6, duration: 0.14 });

      // 신규 / 중복 이펙트 분기 — glow 클래스 적용
      var cardGlowEl  = document.getElementById('cardGlow');
      var sceneGlowEl = document.getElementById('sceneGlow');
      if (drawIsNew) {
        cardGlowEl.classList.add('glow-new');
        sceneGlowEl.classList.add('glow-new');
        // 금색 별은 스핀 중 배경에서 반짝임 — 빔은 카드 공개 시점(tlC)에 연출
        scheduleDrawTimer(twinkleGoldStars, 60);
      } else {
        cardGlowEl.classList.add('glow-dup');
        sceneGlowEl.classList.add('glow-dup');
      }

      // 클릭 순간 빙글빙글 시작 → 3초에 걸쳐 감속 → 완전히 멈추면 카드 공개
      gsap.to('#sceneGlow', {
        opacity: drawIsNew ? 0.74 : 0.38,
        scale: drawIsNew ? 1.10 : 1.02,
        duration: 1.2,
        ease: 'sine.inOut',
        yoyo: true,
        repeat: 1
      });
      gsap.to('#cardTrigger', {
        rotateY: 1800,   // 5바퀴 (duration:0.2 초속으로 시작, power3.out으로 감속)
        duration: 3.0,
        ease: 'power3.out',
        onComplete: function() {
          if (!drawOverlayActive) return;
          gsap.set('#cardTrigger', { rotateY: 0 }); // 깔끔하게 0°로 스냅

          playSfx('cardSparkle');
          burstRevealSparks(drawIsNew ? 1.3 : 0.5);

          var tlC = gsap.timeline({
            onComplete: function() {
              if (!drawOverlayActive) return;
              drawState = 'card_front_settle';
              isFlipping = false;
              playSfx(drawIsNew ? 'revealHidden' : 'revealNormal');

              gsap.set('#settleActions', { display: 'flex' });
              gsap.to('#settleActions', { opacity: 1, duration: 0.44, ease: 'power2.out' });

              // 후광 펄스 — 신규: 강하게 / 중복: 은은하게
              gsap.to('#cardGlow', {
                opacity: drawIsNew ? 0.88 : 0.52,
                scale:   drawIsNew ? 1.56 : 1.04,
                duration: drawIsNew ? 1.6 : 2.6,
                ease: 'sine.inOut', yoyo: true, repeat: -1
              });
              gsap.to('#sceneGlow', {
                opacity: drawIsNew ? 0.82 : 0.40,
                scale:   drawIsNew ? 1.18 : 1.04,
                duration: drawIsNew ? 2.2 : 3.2,
                ease: 'sine.inOut', yoyo: true, repeat: -1
              });
              // 신규 카드 — 임팩트 진동
              if (drawIsNew) {
                gsap.to('#cardTrigger', {
                  x: 3, duration: 0.04, repeat: 5, yoyo: true, ease: 'none',
                  onComplete: function() { gsap.set('#cardTrigger', { x: 0 }); }
                });
              }

              // 앞면 반짝임 sweep 루프
              var shimmerTl = gsap.timeline({ repeat: -1, repeatDelay: 2.2 });
              shimmerTl
                .fromTo('#cardFlipShine',
                  { opacity: 0, x: '-150%' },
                  { opacity: 0.82, x: '20%', duration: 0.28, ease: 'power2.in' }
                )
                .to('#cardFlipShine',
                  { opacity: 0, x: '160%', duration: 0.32, ease: 'power2.out' }
                );
            }
          });

          tlC
            .to('#sceneGlow', { opacity: drawIsNew ? 0.82 : 0.38, scale: drawIsNew ? 1.06 : 1.03, duration: 0.22, ease: 'power2.out' }, 0)
            .to('#cardGlow',  { opacity: drawIsNew ? 1 : 0.48, scale: drawIsNew ? 1.12 : 1.02, duration: 0.22, ease: 'power2.out' }, 0)
            .to('#flashEl',   { opacity: drawIsNew ? 0.96 : 0.22, duration: 0.05, ease: 'none' }, 0.06)
            .to('#flashEl',   { opacity: 0, duration: 0.16, ease: 'power1.out' }, 0.11)
            .fromTo('#ringEl',
              { opacity: drawIsNew ? 0.95 : 0.48, scale: drawIsNew ? 0.42 : 0.60 },
              { opacity: 0, scale: drawIsNew ? 1.62 : 1.18, duration: drawIsNew ? 0.52 : 0.46, ease: 'power2.out' },
              0.08
            )
            .fromTo('#ringEl2',
              { opacity: drawIsNew ? 0.80 : 0.30, scale: drawIsNew ? 0.38 : 0.55 },
              { opacity: 0, scale: drawIsNew ? 2.4 : 1.42, duration: drawIsNew ? 0.72 : 0.62, ease: 'power1.out' },
              0.22
            )
            .fromTo('#ringEl3',
              { opacity: drawIsNew ? 0.60 : 0.18, scale: drawIsNew ? 0.34 : 0.50 },
              { opacity: 0, scale: drawIsNew ? 3.6 : 1.62, duration: drawIsNew ? 1.0 : 0.70, ease: 'power1.out' },
              0.38
            )
            .to('#cardInner', { rotateY: 106, rotateX: 9, rotateZ: -3, duration: 0.28, ease: 'power2.in' }, 0.08)
            .to('#cardFlipShine', { opacity: 0.98, x: '155%', duration: 0.34, ease: 'power2.out' }, 0.26)
            .to('#cardInner', { rotateY: 194, rotateX: -3, rotateZ: 1.6, duration: 0.34, ease: 'power2.out' }, 0.31)
            .to('#cardInner', { rotateY: 180, rotateX: 0, rotateZ: 0, duration: 0.26, ease: 'back.out(1.3)' }, 0.62)
            .to('#cardTrigger', { scale: 1.94, duration: 0.09, ease: 'power3.out' }, 0.62)
            .to('#cardTrigger', { scale: 1.78, duration: 0.38, ease: 'elastic.out(1, 0.45)' }, 0.71)
            .to('#sceneGlow', { opacity: 0.78, scale: 1.04, duration: 0.48, ease: 'power2.out' }, 0.76)
            .to('#cardGlow',  { opacity: 0.86, scale: 1.02, duration: 0.48, ease: 'power2.out' }, 0.82);

          // ── 십자 빔 — 신규 카드 공개 순간만 ──
          if (drawIsNew) {
            // 수평 외곽 황금 잔광
            tlC
              .fromTo('#revealCross',
                { opacity: 0, scale: 0.70, rotate: -3 },
                { opacity: 0.94, scale: 1.02, rotate: 1, duration: 0.20, ease: 'power3.out' },
                0.56
              )
              .fromTo('#crossAfterglow',
                { opacity: 0, scale: 0.82, rotate: -3 },
                { opacity: 0.28, scale: 1.04, rotate: 0, duration: 0.24, ease: 'power2.out' },
                0.64
              )
              .to('#revealCross',
                { opacity: 0, scale: 1.12, duration: 0.48, ease: 'power2.out' },
                0.78
              )
              .to('#crossAfterglow',
                { opacity: 0, scale: 1.24, duration: 0.92, ease: 'sine.out' },
                0.88
              )
              .fromTo('#cardBeam',
                { opacity: 0, scaleX: 0.15, scaleY: 0.6 },
                { opacity: 0.82, scaleX: 1, scaleY: 1, duration: 0.10, ease: 'power4.out' },
                0.62
              )
              .to('#cardBeam', { opacity: 0.38, duration: 0.14, ease: 'power1.in' }, 0.72)
              .to('#cardBeam', { opacity: 0, duration: 0.82,  ease: 'power2.in' }, 0.86)
              // 수평 코어 라인: 순간 섬광
              .fromTo('#cardBeamCore',
                { opacity: 0, scaleX: 0.1 },
                { opacity: 0.78, scaleX: 1, duration: 0.08, ease: 'power4.out' },
                0.62
              )
              .to('#cardBeamCore', { opacity: 0, duration: 0.28, ease: 'power2.in' }, 0.70)
              // 수직 빔
              .fromTo('#cardBeamV',
                { opacity: 0, scaleY: 0.15, scaleX: 0.6 },
                { opacity: 1, scaleY: 1, scaleX: 1, duration: 0.10, ease: 'power4.out' },
                0.62
              )
              .to('#cardBeamV', { opacity: 0.54, duration: 0.14, ease: 'power1.in' }, 0.72)
              .to('#cardBeamV', { opacity: 0, duration: 0.82,  ease: 'power2.in' }, 0.86);
          }

          scheduleDrawTimer(function() { burstRevealSparks(drawIsNew ? 1.4 : 0.45); }, 120);
          if (drawIsNew) {
            scheduleDrawTimer(function() { burstRevealSparks(0.75); }, 560);
          }
        }
      });
    });

    /* ════════════════════════════
       기존 체크 로직
    ════════════════════════════ */
    function renderProgress(total) {
      const pct = Math.min(100, Math.round((total / GOAL_COUNT) * 100));
      document.getElementById('goalText').textContent = total;
      document.getElementById('goalCount').textContent = GOAL_COUNT;
      document.getElementById('progressPercent').textContent = `${pct}%`;
      document.getElementById('progressBar').style.width = `${pct}%`;
    }

    let _dashboardPromise = null;
    async function fetchDashboard() {
      if (_dashboardPromise) return _dashboardPromise;
      _dashboardPromise = fetch(`${API_BASE}?action=dashboard&t=${Date.now()}`, { cache: 'no-store' })
        .then(res => {
          if (!res.ok) throw new Error('현황을 불러오지 못했습니다.');
          return res.json();
        })
        .finally(() => { _dashboardPromise = null; });
      return _dashboardPromise;
    }

    function applyTabSettings(data) {
      if (!data || !data.tabSettings) return;
      const { prayer, secret, chat } = data.tabSettings;
      const prayerItem = document.querySelector('.drawer-item[data-section="prayer"]');
      const secretItem = document.querySelector('.drawer-item[data-section="secret"]');
      const chatItem   = document.querySelector('.drawer-item[data-section="chat"]');
      if (prayerItem) prayerItem.style.display = (prayer === false) ? 'none' : '';
      if (data.tabSettings.bbbSections) _bbbSections = Object.assign(_bbbSections, data.tabSettings.bbbSections);
      if (secretItem) secretItem.style.display = '';
      if (chatItem)   chatItem.style.display   = (chat   === false) ? 'none' : '';
    }

    function updateScoreProgress() {
      const wrap = document.getElementById('scoreProgressWrap');
      if (!currentNickname || !userStatus || userStatus.error || !lastConfigData) { wrap.style.display = 'none'; return; }
      const ws = userStatus.weekScore || 0;
      const dt = userStatus.drawThreshold || lastConfigData.drawThreshold || 6;
      const pct = Math.min(100, Math.round(ws / dt * 100));
      wrap.style.display = '';
      document.getElementById('scoreProgressText').textContent = `${ws} / ${dt}점`;
      document.getElementById('scoreProgressBar').style.width = pct + '%';
      const hint = document.getElementById('scoreProgressHint');
      const earned = userStatus.earnedTicketThisWeek;
      if (earned) {
        hint.innerHTML = '이번 주차 뽑기 티켓 획득 🎫 → <button onclick="document.getElementById(\'drawSection\').scrollIntoView({block:\'center\'})" style="margin-left:4px;padding:2px 10px;font-size:12px;font-weight:700;background:rgba(120,100,200,0.25);color:var(--primary);border:none;border-radius:999px;cursor:pointer;">뽑으러 가기</button>';
        hint.style.color = 'var(--success)';
      } else {
        hint.textContent = `앞으로 ${dt - ws}점 더 모으면 카드 뽑기권 획득!`;
        hint.style.color = 'var(--sub)';
      }
    }

    function renderItemText(text) {
      return text
        .replace(/[<>&]/g, c => ({'<':'&lt;','>':'&gt;','&':'&amp;'}[c]))
        .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer" onclick="event.stopPropagation();" style="color:var(--primary);text-decoration:underline;">$1</a>')
        .replace(/(?<![="'/>])(https?:\/\/[^\s<>]+)/g, '<a href="$1" target="_blank" rel="noopener noreferrer" onclick="event.stopPropagation();" style="color:var(--primary);text-decoration:underline;">링크 바로가기</a>')
        .replace(/\n/g, '<br>');
    }

    function renderConfig(data) {
      lastConfigData = data;
      weekTitleEl.textContent = data.weekTitle;
      checkListEl.innerHTML = '';
      const submittedToday = [...new Set([
        ...(userStatus?.todayItems || []),
        ...getSubmittedToday()
      ])];
      const submittedIndices = new Set([...(userStatus?.todayIndices || []), ...getSubmittedIndices()]);
      data.items.forEach((item, i) => {
        const id = `item_${i}`;
        const done = submittedToday.includes(item) || submittedIndices.has(i);
        const score = data.scores ? (data.scores[item] || 1) : 1;
        const cat   = data.cats   ? (data.cats[item]   || '') : '';
        const div = document.createElement('div');
        div.className = 'check-item' + (done ? ' submitted' : '') + (cat ? ` cat-${cat}` : '');
        div.innerHTML = `<input type="checkbox" id="${id}" name="items" value="${item.replace(/&/g,'&amp;').replace(/"/g,'&quot;')}"${done ? ' checked disabled' : ''}><label for="${id}">${renderItemText(item)}</label><span class="score-badge">${score}점</span>`;
        if (!done) {
          div.querySelector('input').addEventListener('change', e => {
            div.classList.toggle('checked', e.target.checked);
            if (e.target.checked && navigator.vibrate) navigator.vibrate(15);
          });
        }
        checkListEl.appendChild(div);
      });
      updateCheckUI(data.items);
      updateScoreProgress();
    }

    function renderCounts(data) {
      totalCountEl.textContent = data.totalCount;
      submissionCountEl.textContent = data.submissionCount;
      countListEl.innerHTML = '';
      const maxCnt = Math.max(1, ...data.items.map(item => data.counts[item] || 0));
      data.items.forEach(item => {
        const cnt = data.counts[item] || 0;
        const pct = Math.round((cnt / maxCnt) * 100);
        const div = document.createElement('div');
        div.className = 'count-item';
        div.innerHTML = `<span class="count-item-name">${item.replace(/[<>&]/g, c => ({'<':'&lt;','>':'&gt;','&':'&amp;'}[c])).replace(/\n/g, ' ')}</span><div class="count-item-bar-wrap"><div class="count-item-bar" style="width:${pct}%"></div></div><span class="count-item-count">${cnt}</span>`;
        countListEl.appendChild(div);
      });
      renderProgress(data.totalCount);
    }

    function setStatus(msg, type = '') {
      statusMessageEl.textContent = msg;
      statusMessageEl.className = `status ${type}`.trim();
    }

    function getTodayKey() {
      const n = new Date();
      return `${n.getFullYear()}-${String(n.getMonth()+1).padStart(2,'0')}-${String(n.getDate()).padStart(2,'0')}`;
    }
    function hasCheckedToday() {
      return localStorage.getItem('beyondus_last_check_date') === getTodayKey();
    }

    function saveCheckDate() {
      const today = getTodayKey();
      const dates = JSON.parse(localStorage.getItem('beyondus_check_dates') || '[]');
      if (!dates.includes(today)) {
        dates.push(today);
        localStorage.setItem('beyondus_check_dates', JSON.stringify(dates));
      }
    }

    function renderWeekCal() {
      const calEl = document.getElementById('weekCal');
      const titleEl = document.getElementById('weekCalTitle');
      if (!calEl) return;
      const checkDates = JSON.parse(localStorage.getItem('beyondus_check_dates') || '[]');
      const todayStr = getTodayKey();
      const today = new Date();
      const dayOfWeek = today.getDay() || 7;
      const monday = new Date(today);
      monday.setDate(today.getDate() - (dayOfWeek - 1));

      // "4월 2째주" 형식 타이틀 — 월 첫날 요일 기준으로 정확히 계산
      const firstDayOfMonth = new Date(today.getFullYear(), today.getMonth(), 1).getDay() || 7;
      const weekNum = Math.ceil((today.getDate() + firstDayOfMonth - 1) / 7);
      if (titleEl) titleEl.textContent = `${today.getMonth() + 1}월 ${weekNum}째주`;

      const SHEEP_BY_DAY = {
        0: { img: '월요일앤.png', style: 'width:31px;top:calc(50% - 16px);left:calc(50% - 16px);transform:translate(-50%,-50%);' },
        2: { img: '수요일앤.png', style: 'width:31px;top:calc(50% - 19px);left:calc(50% - 1px);transform:translate(-50%,-50%);' },
        4: { img: '금요일앤.png', style: 'width:38px;top:calc(50% + 8px);left:calc(50% + 18px);transform:translate(-50%,-50%);' },
        6: { img: '일요일앤.png', style: 'width:36px;top:calc(50% - 17px);left:calc(50% - 12px);transform:translate(-50%,-50%);' },
      };
      const labels = ['월','화','수','목','금','토','일'];
      calEl.innerHTML = labels.map((label, i) => {
        const d = new Date(monday);
        d.setDate(monday.getDate() + i);
        const dateStr = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
        const isChecked = checkDates.includes(dateStr);
        const isToday = dateStr === todayStr;
        const sheep = SHEEP_BY_DAY[i] || null;
        return `<div class="week-cal-day">
          <span class="week-cal-label">${label}</span>
          <div class="week-cal-dot-wrap">
            <div class="week-cal-dot${isChecked ? ' checked' : ''}${isToday && !isChecked ? ' today' : ''}">${d.getDate()}</div>
            ${isChecked && sheep ? `<img src="images/${sheep.img}" class="week-cal-sheep" style="${sheep.style}" alt="" />` : ''}
          </div>
        </div>`;
      }).join('');
    }
    function getSubmittedToday() {
      return JSON.parse(localStorage.getItem('beyondus_submitted_' + getTodayKey()) || '[]');
    }
    function getSubmittedIndices() {
      return JSON.parse(localStorage.getItem('beyondus_submitted_idx_' + getTodayKey()) || '[]');
    }
    function saveSubmittedItems(items) {
      const key = 'beyondus_submitted_' + getTodayKey();
      const merged = [...new Set([...getSubmittedToday(), ...items])];
      localStorage.setItem(key, JSON.stringify(merged));
      // 인덱스도 저장 (어드민 미션 텍스트 변경 시 폴백)
      if (lastConfigData?.items) {
        const idxKey = 'beyondus_submitted_idx_' + getTodayKey();
        const existing = getSubmittedIndices();
        const newIdx = items.map(item => lastConfigData.items.indexOf(item)).filter(i => i >= 0);
        localStorage.setItem(idxKey, JSON.stringify([...new Set([...existing, ...newIdx])]));
      }
    }
    function updateCheckUI(allItems) {
      if (!allItems || !allItems.length) { submitBtn.disabled = false; return; }
      const submitted = getSubmittedToday();
      const submittedIdx = new Set([...(userStatus?.todayIndices || []), ...getSubmittedIndices()]);
      const allDone = allItems.every((item, i) => submitted.includes(item) || submittedIdx.has(i));
      if (allDone) {
        submitBtn.disabled = true;
        setStatus('오늘 모든 미션을 완료했어요! 수고했어요 :)', 'success');
      } else {
        submitBtn.disabled = false;
      }
    }

    async function loadAll(options) {
      const silent = options && options.silent === true;
      if (!silent) setStatus('현황을 불러오고 있어요...');
      const data = await fetchDashboard();
      localStorage.setItem('beyondus_cache_config', JSON.stringify(data));
      renderConfig(data);   // 내부에서 updateCheckUI 호출
      renderCounts(data);
      applyTabSettings(data);
      updatePrayerDot();
      if (!silent) setStatus('최신 현황으로 업데이트되었어요.', 'success');
      return data;
    }

    let _serverSyncPromise = null;
    let _lastServerSyncAt = 0;
    const SERVER_SYNC_MIN_INTERVAL_MS = 45000;
    function syncServerChanges(force) {
      if (!currentNickname) return Promise.resolve();
      const now = Date.now();
      if (!force && now - _lastServerSyncAt < SERVER_SYNC_MIN_INTERVAL_MS) return _serverSyncPromise || Promise.resolve();
      if (_serverSyncPromise) return _serverSyncPromise;
      _lastServerSyncAt = now;
      _serverSyncPromise = Promise.all([
        loadAll({ silent: true }).catch(() => {}),
        loadNotices().catch(() => {}),
        loadUserStatus({ silent: true }).then(() => loadTrades()).catch(() => {}),
        _currentSection === 'secret' ? loadBBB(true).catch(() => {}) : Promise.resolve(),
        _currentSection === 'prayer' ? loadHoldPray(true).then(markHoldPraySeen).catch(() => {}) : Promise.resolve()
      ]).finally(() => { _serverSyncPromise = null; });
      return _serverSyncPromise;
    }

    checkForm.addEventListener('submit', async e => {
      e.preventDefault();
      const submittedToday = [...new Set([...(userStatus?.todayItems || []), ...getSubmittedToday()])];
      const submittedIdx = new Set([...(userStatus?.todayIndices || []), ...getSubmittedIndices()]);
      const allItems = lastConfigData?.items || [];
      const checked = [...document.querySelectorAll('input[name="items"]:checked:not(:disabled)')]
        .map(el => el.value)
        .filter(v => !submittedToday.includes(v) && !submittedIdx.has(allItems.indexOf(v)));
      if (!checked.length) { setStatus('실천한 항목을 1개 이상 선택해주세요.', 'error'); return; }

      submitBtn.disabled = true;
      refreshBtn.disabled = true;
      setStatus('저장하고 있어요...');
      const submitRequestId = 'submit_' + getTodayKey() + '_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8);
      const checkedScore = checked.reduce((s, item) => s + ((lastConfigData?.scores?.[item]) || 1), 0);
      const checkedIndices = checked.map(item => allItems.indexOf(item)).filter(i => i >= 0);
      const todayKey = getTodayKey();
      const optimisticKeys = [
        'beyondus_submitted_' + todayKey,
        'beyondus_submitted_idx_' + todayKey,
        'beyondus_check_dates',
        'beyondus_last_check_date'
      ];
      const optimisticStorage = {};
      optimisticKeys.forEach(key => { optimisticStorage[key] = localStorage.getItem(key); });
      const optimisticUserStatus = userStatus ? JSON.parse(JSON.stringify(userStatus)) : userStatus;
      function restoreOptimisticState() {
        optimisticKeys.forEach(key => {
          if (optimisticStorage[key] === null) localStorage.removeItem(key);
          else localStorage.setItem(key, optimisticStorage[key]);
        });
        userStatus = optimisticUserStatus ? JSON.parse(JSON.stringify(optimisticUserStatus)) : optimisticUserStatus;
      }

      saveSubmittedItems(checked);
      saveCheckDate();
      if (userStatus && !userStatus.error) {
        userStatus.weekScore = (Number(userStatus.weekScore) || 0) + checkedScore;
        userStatus.todayItems = [...new Set([...(userStatus.todayItems || []), ...checked])];
        userStatus.todayIndices = [...new Set([...(userStatus.todayIndices || []), ...checkedIndices])];
      }
      if (lastConfigData) renderConfig(lastConfigData);
      updateScoreProgress();
      renderWeekCal();
      submitBtn.disabled = true;
      refreshBtn.disabled = true;

      try {
        const res = await fetch(API_BASE, {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain;charset=utf-8' },
          body: JSON.stringify(withSession({ action: 'submit', items: checked, userId: currentNickname || '', weekKey: getWeekKey(), dateKey: getTodayKey(), score: checkedScore, requestId: submitRequestId }))
        });
        if (!res.ok) throw new Error('체크 저장에 실패했습니다.');
        const saved = await res.json();
        if (saved && saved.ok === false) throw new Error(saved.error || saved.message || '체크 저장에 실패했습니다.');
        const savedItems = Array.isArray(saved?.savedItems) ? saved.savedItems : checked;
        const savedIndices = Array.isArray(saved?.savedIndices) ? saved.savedIndices : savedItems.map(item => lastConfigData?.items?.indexOf(item)).filter(i => i >= 0);

        restoreOptimisticState();
        if (savedItems.length) {
          saveSubmittedItems(savedItems);
          saveCheckDate();
        }

        // 서버가 실제 저장한 항목만 로컬 반영
        if (userStatus) {
          const addedScore = Number(saved?.newScore);
          userStatus.weekScore = Number(saved?.weekScore) || ((userStatus.weekScore || 0) + (isNaN(addedScore) ? 0 : addedScore));
          userStatus.todayItems = [...new Set([...(userStatus.todayItems || []), ...savedItems])];
          userStatus.todayIndices = [...new Set([...(userStatus.todayIndices || []), ...savedIndices])];
          if (saved?.ticketEarned) {
            userStatus.earnedTicketThisWeek = true;
            userStatus.pendingDraws = (Number(userStatus.pendingDraws) || 0) + 1;
          }
        }
        if (lastConfigData) renderConfig(lastConfigData);
        renderDrawSection();
        updateScoreProgress();
        renderWeekCal();

        setStatus(savedItems.length ? '실천이 저장되었어요!' : '이미 저장된 실천이에요. 최신 상태로 맞췄어요.', 'success');

        // 백그라운드에서 서버 데이터 동기화
        loadAll({ silent: true }).catch(() => {});
        loadUserStatus().then(() => loadTrades()).catch(() => {});
      } catch(err) {
        restoreOptimisticState();
        if (lastConfigData) renderConfig(lastConfigData);
        updateScoreProgress();
        renderWeekCal();
        setStatus(err.message || '오류가 발생했습니다.', 'error');
        submitBtn.disabled = false;
      } finally {
        refreshBtn.disabled = false;
      }
    });

    refreshBtn.addEventListener('click', async () => {
      refreshBtn.disabled = true;
      submitBtn.disabled = true;
      try {
        await loadAll();
        updateCheckUI();
      } catch(err) {
        setStatus(err.message || '현황을 새로 불러오는 중 문제가 발생했어요.', 'error');
      } finally {
        refreshBtn.disabled = false;
        submitBtn.disabled = false;
      }
    });

    /* ════ 드로어 ════ */
    let _drawerSynced = false;
    function syncDrawerLabelWidth() {
      const labels = document.querySelectorAll('.drawer-nav .drawer-label');
      // inline으로 측정해야 숨겨진 상태에서도 텍스트 실제 너비 반환
      labels.forEach(l => { l.style.cssText += ';display:inline;width:auto;'; });
      let maxW = 0;
      labels.forEach(l => { maxW = Math.max(maxW, l.getBoundingClientRect().width); });
      labels.forEach(l => { l.style.display = 'block'; l.style.width = maxW + 'px'; });
      if (maxW > 0) _drawerSynced = true;
    }
    requestAnimationFrame(syncDrawerLabelWidth);

    function openDrawer() {
      document.getElementById('navDrawer').classList.add('open');
      document.getElementById('drawerOverlay').classList.remove('hidden');
      document.body.style.overflow = 'hidden';
      if (!_drawerSynced) requestAnimationFrame(syncDrawerLabelWidth);
    }
    function closeDrawer() {
      document.getElementById('navDrawer').classList.remove('open');
      document.getElementById('drawerOverlay').classList.add('hidden');
      document.body.style.overflow = '';
    }
    const drawerToggleEl = document.getElementById('drawerToggle');
    if (drawerToggleEl) drawerToggleEl.addEventListener('click', openDrawer);
    document.getElementById('drawerOverlay').addEventListener('click', closeDrawer);

    document.getElementById('logoutBtn').addEventListener('click', () => {
      if (window._tradePollingTimer) {
        clearTimeout(window._tradePollingTimer);
        window._tradePollingTimer = null;
      }
      Object.keys(localStorage)
        .filter(k => k.startsWith('beyondus_'))
        .forEach(k => localStorage.removeItem(k));
      currentNickname = null;
      currentParish   = null;
      closeDrawer();
      showAuth('login');
    });

    /* ════ 섹션 전환 ════ */
    const SECTION_IDS = {
      notice:     'sectionNotice',
      mission:    'sectionMission',
      collection: 'sectionCollection',
      prayer:     'sectionPrayer',
      secret:     'sectionSecret',
      inquiry:    'sectionInquiry',
      chat:       'sectionChat',
      faq:        'sectionFaq',
    };
    let _currentSection = 'mission';
    const _sectionScrollPos = {};
    let _bbbSections = { careBuddy:{open:false,text:'Coming Soon!\n6/14 Open'}, m1:{open:false,text:'Coming Soon!\n6/20 Open'}, m2:{open:false,text:'Coming Soon!\n6/20 Open'}, m3:{open:false,text:'Coming Soon!\n6/21 Open'}, secretBuddy:{open:false,text:'Coming Soon!\n6/20 Open'}, msgOpen:{open:false} };
    function switchSection(name) {
      const prev = _currentSection;
      _sectionScrollPos[prev] = window.scrollY;
      Object.values(SECTION_IDS).forEach(id => {
        document.getElementById(id).classList.add('hidden');
      });
      document.getElementById(SECTION_IDS[name]).classList.remove('hidden');
      document.querySelectorAll('.drawer-item').forEach(el => {
        el.classList.toggle('active', el.dataset.section === name);
      });
      if (name === 'notice') markAllSeen();
      if (name === 'inquiry') loadInquiries();
      if (name === 'prayer') {
        markHoldPraySeen();
        loadHoldPray(false).then(markHoldPraySeen).catch(() => {});
      }
      if (name === 'collection') {
        renderCollection();
        loadUserStatus({ silent: true }).then(() => { renderCollection(); loadTrades(); }).catch(() => {});
      }
      if (name === 'secret') { loadBBB(); }
      if (name === 'chat') initChat();
      else if (prev === 'chat') teardownChat();
      _currentSection = name;
      window.scrollTo(0, _sectionScrollPos[name] || 0);
      closeDrawer();
    }
    document.querySelectorAll('.drawer-item').forEach(el => {
      el.addEventListener('click', () => switchSection(el.dataset.section));
    });

    /* ════ 도움말 툴팁 ════ */
    function toggleHelpTip(btn) {
      const tip = btn.nextElementSibling;
      const isOpen = tip.classList.contains('show');
      document.querySelectorAll('.help-tooltip.show').forEach(t => { t.classList.remove('show'); t.style.marginLeft = ''; });
      if (!isOpen) {
        tip.style.marginLeft = '';
        tip.classList.add('show');
        const r = tip.getBoundingClientRect();
        if (r.left < 8) tip.style.marginLeft = (8 - r.left) + 'px';
        else if (r.right > window.innerWidth - 8) tip.style.marginLeft = -(r.right - window.innerWidth + 8) + 'px';
      }
    }
    document.addEventListener('click', e => {
      if (!e.target.closest('.help-wrap')) {
        document.querySelectorAll('.help-tooltip.show').forEach(t => t.classList.remove('show'));
      }
    });

    /* ════ QnA FAQ ════ */
    function toggleFaq(btn) {
      const item = btn.closest('.faq-item');
      const isOpen = item.classList.contains('open');
      document.querySelectorAll('.faq-item.open').forEach(i => i.classList.remove('open'));
      if (!isOpen) item.classList.add('open');
    }

    function filterFaq(query) {
      const q = query.trim().toLowerCase();
      const items = document.querySelectorAll('#sectionFaq .faq-item');
      const categories = document.querySelectorAll('#sectionFaq .faq-category');
      let anyVisible = false;

      items.forEach(item => {
        const text = item.textContent.toLowerCase();
        const visible = !q || text.includes(q);
        item.style.display = visible ? '' : 'none';
        if (visible) anyVisible = true;
      });

      // 카테고리 헤더: 바로 다음에 보이는 faq-item이 없으면 숨김
      categories.forEach(cat => {
        let next = cat.nextElementSibling;
        let hasVisible = false;
        while (next && !next.classList.contains('faq-category')) {
          if (next.classList.contains('faq-item') && next.style.display !== 'none') hasVisible = true;
          next = next.nextElementSibling;
        }
        cat.style.display = hasVisible ? '' : 'none';
      });

      document.getElementById('faqEmpty').style.display = anyVisible ? 'none' : 'block';
    }

    /* ════ 공지사항 ════ */
    let cachedNotices = [];

    function getSeenIds() {
      try { return JSON.parse(localStorage.getItem('beyondus_seen_notices') || '[]'); } catch { return []; }
    }
    function saveSeenIds(ids) {
      localStorage.setItem('beyondus_seen_notices', JSON.stringify(ids));
    }
    function noticeSeenKey(n) {
      const id = String(n?.id || '');
      const updatedAt = String(n?.updatedAt || '');
      const createdAt = String(n?.createdAt || '');
      return (updatedAt && createdAt && updatedAt !== createdAt) ? `${id}:${updatedAt}` : id;
    }
    function markHoldPraySeen() {
      if (lastConfigData?.weekTitle) localStorage.setItem('beyondus_hp_last_seen_week', lastConfigData.weekTitle);
      if (_hpWeekKey && _hpRevision) localStorage.setItem('beyondus_hp_seen_revision_' + _hpWeekKey, _hpRevision);
      document.getElementById('drawerPrayerDot')?.classList.remove('visible');
    }
    function updatePrayerDot() {
      const dot = document.getElementById('drawerPrayerDot');
      if (!dot) return;
      const weekTitle = lastConfigData?.weekTitle || '';
      const isNewWeek = weekTitle && weekTitle !== (localStorage.getItem('beyondus_hp_last_seen_week') || '');
      const isTicketWeek = (_hpWeekKey === 'w3' || _hpWeekKey === 'w6');
      const ticketNotSeen = isTicketWeek && !localStorage.getItem('beyondus_hp_ticket_seen_' + _hpWeekKey);
      const hpRevisionSeen = _hpWeekKey && _hpRevision && localStorage.getItem('beyondus_hp_seen_revision_' + _hpWeekKey) === _hpRevision;
      const hpContentChanged = _hpWeekKey && _hpRevision && !hpRevisionSeen;
      dot.classList.toggle('visible', !!(isNewWeek || ticketNotSeen || hpContentChanged));
    }

    function updateNoticeDot() {
      const seen = getSeenIds();
      const hasNew = cachedNotices.some(n => !seen.includes(noticeSeenKey(n)));
      document.getElementById('noticeDot').classList.toggle('visible', hasNew);
      document.getElementById('drawerNoticeDot').classList.toggle('visible', hasNew);
    }
    function markAllSeen() {
      const ids = cachedNotices.map(n => noticeSeenKey(n));
      saveSeenIds(ids);
      document.getElementById('noticeDot').classList.remove('visible');
      document.getElementById('drawerNoticeDot').classList.remove('visible');
    }

    function renderNoticeList(notices, seen) {
      const list = document.getElementById('noticeList');
      if (!notices.length) {
        list.innerHTML = '<p class="notice-empty">검색 결과가 없어요.</p>';
        return;
      }
      function parseNoticeImgs(imageUrl) {
        if (!imageUrl) return [];
        try { const p = JSON.parse(imageUrl); if (Array.isArray(p)) return p; } catch(e) {}
        return [imageUrl];
      }
      list.innerHTML = notices.map(n => {
        const isNew = !seen.includes(noticeSeenKey(n));
        const imgs = parseNoticeImgs(n.imageUrl);
        const imgHtml = imgs.length
          ? `<div style="display:flex;flex-wrap:wrap;gap:6px;margin-top:10px;">${imgs.map(u => `<img src="${u}" loading="lazy" onclick="openLightbox('${u}')" style="max-width:100%;max-height:260px;object-fit:contain;border-radius:8px;flex:1 1 auto;cursor:pointer;">`).join('')}</div>`
          : '';
        return `
        <div class="notice-item">
          <div class="notice-title">📢 ${escHtml(n.title)}${isNew ? ' <span style="font-size:10px;background:#ef4444;color:white;border-radius:999px;padding:1px 7px;font-weight:700;vertical-align:middle;">NEW</span>' : ''}</div>
          <div class="notice-content">${linkify(escHtml(n.content))}</div>
          ${imgHtml}
          <div class="notice-date">${formatNoticeDate(n.createdAt)}</div>
        </div>`;
      }).join('');
    }

    async function loadNotices() {
      const list = document.getElementById('noticeList');
      const noticeCacheKey = 'beyondus_cache_notices';
      const noticeCached = JSON.parse(localStorage.getItem(noticeCacheKey) || 'null');
      if (noticeCached && noticeCached.ok && noticeCached.notices?.length) {
        cachedNotices = noticeCached.notices;
        renderNoticeList(cachedNotices, getSeenIds());
        updateNoticeDot();
      }
      try {
        const res = await fetch(`${API_BASE}?action=getNotices&t=${Date.now()}`, { cache: 'no-store' }).then(r => r.json());
        if (!res.ok || !res.notices?.length) {
          cachedNotices = [];
          localStorage.removeItem(noticeCacheKey);
          list.innerHTML = '<p class="notice-empty">등록된 공지사항이 없어요.</p>';
          return;
        }
        localStorage.setItem(noticeCacheKey, JSON.stringify(res));
        cachedNotices = res.notices;
        renderNoticeList(cachedNotices, getSeenIds());
        updateNoticeDot();
      } catch(e) {
        if (!noticeCached) list.innerHTML = '<p class="notice-empty">불러오기 실패. 잠시 후 다시 시도해주세요.</p>';
      }
    }

    document.getElementById('noticeSearch').addEventListener('input', function() {
      const q = this.value.trim().toLowerCase();
      const filtered = q
        ? cachedNotices.filter(n => n.title.toLowerCase().includes(q) || n.content.toLowerCase().includes(q))
        : cachedNotices;
      renderNoticeList(filtered, getSeenIds());
    });
    function _compressImage(file, maxPx, quality) {
      return new Promise((resolve, reject) => {
        const img = new Image();
        const url = URL.createObjectURL(file);
        img.onload = () => {
          URL.revokeObjectURL(url);
          const scale = Math.min(1, maxPx / Math.max(img.width, img.height));
          const w = Math.round(img.width * scale), h = Math.round(img.height * scale);
          const canvas = document.createElement('canvas');
          canvas.width = w; canvas.height = h;
          canvas.getContext('2d').drawImage(img, 0, 0, w, h);
          resolve(canvas.toDataURL('image/jpeg', quality));
        };
        img.onerror = reject;
        img.src = url;
      });
    }

    function escHtml(s) {
      return String(s || '').replace(/[<>&"]/g, c => ({'<':'&lt;','>':'&gt;','&':'&amp;','"':'&quot;'}[c]));
    }

    /* URL → 하이퍼링크 변환 (escHtml 적용 후 호출) */
    function linkify(s) {
      // escHtml 후에 호출되므로 실제 <> 는 없음. & 에서 멈추면 &amp; &lt; 등 엔티티 앞에서 정지
      return s.replace(/(https?:\/\/[^\s&"]+)/g,
        url => `<a href="${url}" target="_blank" rel="noopener noreferrer" style="color:var(--primary);text-decoration:underline;word-break:break-all;">${url}</a>`);
    }

    /* 이미지 라이트박스 */
    function openLightbox(src) {
      const el = document.getElementById('lightboxOverlay');
      document.getElementById('lightboxImg').src = src;
      el.style.display = 'flex';
    }
    function closeLightbox() {
      document.getElementById('lightboxOverlay').style.display = 'none';
      document.getElementById('lightboxImg').src = '';
    }

    function formatNoticeDate(v) {
      if (!v) return '';
      const d = new Date(v);
      if (isNaN(d)) return String(v).slice(0, 10);
      return `${d.getFullYear()}.${String(d.getMonth()+1).padStart(2,'0')}.${String(d.getDate()).padStart(2,'0')}`;
    }

    /* ════ 개발자 문의 ════ */
    function updateInquiryLoginUI() {
      const loggedIn = !!currentNickname;
      [
        ['inquiryQuickWrap', 'inquiryLoginMsg'],
        ['inquiryComposeWrap', 'inquiryComposeLoginMsg'],
      ].forEach(([wrapId, msgId]) => {
        const wrap = document.getElementById(wrapId);
        const msg  = document.getElementById(msgId);
        if (wrap) wrap.style.display = loggedIn ? '' : 'none';
        if (msg)  msg.style.display  = loggedIn ? 'none' : '';
      });
    }

    async function loadInquiries() {
      const list = document.getElementById('inquiryList');
      if (!list) return;
      list.innerHTML = '<p style="color:var(--sub);text-align:center;padding:16px;">불러오는 중...</p>';
      try {
        const res  = await fetch(`${API_BASE}?action=getInquiries&t=${Date.now()}`, { cache: 'no-store' });
        const data = await res.json();
        if (!data.ok) throw new Error();
        renderInquiries(data.inquiries);
      } catch(e) {
        list.innerHTML = '<p style="color:var(--danger);text-align:center;padding:16px;">연결 오류</p>';
      }
    }

    function renderInquiries(inquiries) {
      const list = document.getElementById('inquiryList');
      inquiries = inquiries.filter(inq => !inq.content.startsWith('[H&P 힌트 요청]'));
      if (!inquiries.length) {
        list.innerHTML = '<p style="color:var(--sub);text-align:center;padding:16px;font-size:13px;">아직 문의가 없어요.</p>';
        return;
      }
      list.innerHTML = inquiries.map(inq => {
        const isOwn    = currentNickname && inq.nickname === currentNickname;
        const hasReply = !!inq.reply;
        const dateStr  = formatNoticeDate(inq.createdAt);
        return `
          <div class="inq-item" id="inqItem_${inq.id}" data-id="${inq.id}" data-content="${escHtml(inq.content)}" style="padding:14px 0; border-bottom:1px solid var(--line);">
            <div style="display:flex; justify-content:space-between; align-items:flex-start; gap:8px;">
              <div style="flex:1;">
                <div style="font-size:14px; font-weight:600; line-height:1.5; word-break:keep-all;">${escHtml(inq.content)}</div>
                <div style="font-size:12px; color:var(--sub); margin-top:4px;">${dateStr}</div>
              </div>
              <div style="display:flex; gap:6px; flex-shrink:0; align-items:center; flex-wrap:wrap; justify-content:flex-end;">
                ${!hasReply ? '<span style="font-size:11px;font-weight:700;color:var(--danger);background:#fee2e2;border-radius:999px;padding:2px 8px;">미답변</span>' : ''}
                ${isOwn ? `<button class="btn btn-secondary" style="flex:none;height:auto;font-size:12px;padding:4px 10px;border-radius:8px;" onclick="startInquiryEdit('${inq.id}')">수정</button><button class="btn btn-secondary" style="flex:none;height:auto;font-size:12px;padding:4px 10px;border-radius:8px;color:var(--danger);" onclick="startInquiryDelete('${inq.id}')">삭제</button>` : ''}
              </div>
            </div>
            ${hasReply ? `
              <div style="margin-top:10px;padding:10px 12px;background:var(--primary-soft);border-radius:10px;border-left:3px solid var(--primary);">
                <div style="font-size:11px;font-weight:700;color:var(--sub);margin-bottom:4px;">개발자 답변</div>
                <div style="font-size:14px;line-height:1.5;white-space:pre-wrap;">${escHtml(inq.reply)}</div>
              </div>` : ''}
          </div>`;
      }).join('');
    }

    function startInquiryEdit(id) {
      const item = document.getElementById(`inqItem_${id}`);
      const content = item.dataset.content;
      item.innerHTML = `
        <textarea id="inqEditText_${id}" style="width:100%;padding:10px 12px;font-size:14px;border:1.5px solid var(--line);border-radius:12px;background:var(--primary-soft);color:var(--text);outline:none;font-family:inherit;resize:vertical;line-height:1.5;min-height:72px;" maxlength="500">${escHtml(content)}</textarea>
        <div id="inqEditStatus_${id}" style="font-size:13px;font-weight:600;color:var(--danger);min-height:18px;margin-top:6px;"></div>
        <div style="display:flex;gap:8px;margin-top:8px;">
          <button class="btn btn-secondary" style="flex:1;" onclick="loadInquiries()">취소</button>
          <button class="btn btn-primary" style="flex:1;" onclick="saveInquiryEdit('${id}')">저장</button>
        </div>`;
    }

    function startInquiryDelete(id) {
      const item = document.getElementById(`inqItem_${id}`);
      const delWrap = document.createElement('div');
      delWrap.id = `inqDelWrap_${id}`;
      delWrap.style.cssText = 'margin-top:10px; padding:10px 12px; background:#fee2e2; border-radius:10px;';
      delWrap.innerHTML = `
        <div style="font-size:13px; font-weight:700; color:var(--danger); margin-bottom:8px;">정말 삭제할까요?</div>
        <div id="inqDelStatus_${id}" style="font-size:13px;font-weight:600;color:var(--danger);min-height:18px;margin-top:4px;"></div>
        <div style="display:flex;gap:8px;margin-top:8px;">
          <button class="btn btn-secondary" style="flex:1;height:36px;font-size:13px;" onclick="document.getElementById('inqDelWrap_${id}').remove()">취소</button>
          <button class="btn btn-secondary" style="flex:1;height:36px;font-size:13px;color:var(--danger);" onclick="confirmInquiryDelete('${id}')">삭제</button>
        </div>`;
      item.appendChild(delWrap);
    }

    async function confirmInquiryDelete(id) {
      const statusEl = document.getElementById(`inqDelStatus_${id}`);
      const dotsTimer = animDots(statusEl, '삭제 중');
      statusEl.style.color = 'var(--sub)';
      try {
        const res = await fetch(API_BASE, {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain;charset=utf-8' },
          body: JSON.stringify(withSession({ action: 'deleteInquiry', nickname: currentNickname, id }))
        });
        const data = await res.json();
        if (data.ok) {
          stopAnimDots(dotsTimer, statusEl, '');
          loadInquiries();
        } else if (data.error === 'wrong_password' || data.error === 'unauthorized') {
          stopAnimDots(dotsTimer, statusEl, '인증 오류. 다시 로그인해주세요.');
          statusEl.style.color = 'var(--danger)';
        } else {
          stopAnimDots(dotsTimer, statusEl, '오류가 발생했어요.');
          statusEl.style.color = 'var(--danger)';
        }
      } catch(e) {
        stopAnimDots(dotsTimer, statusEl, '연결 오류');
        statusEl.style.color = 'var(--danger)';
      }
    }

    async function saveInquiryEdit(id) {
      const content  = document.getElementById(`inqEditText_${id}`).value.trim();
      const statusEl = document.getElementById(`inqEditStatus_${id}`);
      if (!content) { statusEl.textContent = '내용을 입력해주세요.'; return; }
      const dotsTimerSave = animDots(statusEl, '저장 중');
      statusEl.style.color = 'var(--sub)';
      try {
        const res = await fetch(API_BASE, {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain;charset=utf-8' },
          body: JSON.stringify(withSession({ action: 'editInquiry', nickname: currentNickname, id, content }))
        });
        const data = await res.json();
        if (data.ok) {
          stopAnimDots(dotsTimerSave, statusEl, '');
          loadInquiries();
        } else if (data.error === 'wrong_password' || data.error === 'unauthorized') {
          stopAnimDots(dotsTimerSave, statusEl, '인증 오류. 다시 로그인해주세요.');
          statusEl.style.color = 'var(--danger)';
        } else {
          stopAnimDots(dotsTimerSave, statusEl, '오류가 발생했어요.');
          statusEl.style.color = 'var(--danger)';
        }
      } catch(e) {
        stopAnimDots(dotsTimerSave, statusEl, '연결 오류');
        statusEl.style.color = 'var(--danger)';
      }
    }

    async function submitInquiry(inputId, statusId, buttonId) {
      if (!currentNickname) return;
      const input    = document.getElementById(inputId);
      const statusEl = document.getElementById(statusId);
      const content  = input.value.trim();
      if (!content) { statusEl.textContent = '내용을 입력해주세요.'; return; }
      const btn = document.getElementById(buttonId);
      btn.disabled = true;
      const dotsTimerPost = animDots(statusEl, '등록 중');
      statusEl.style.color = 'var(--sub)';
      try {
        const res = await fetch(API_BASE, {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain;charset=utf-8' },
          body: JSON.stringify(withSession({ action: 'postInquiry', nickname: currentNickname, content }))
        });
        const data = await res.json();
        if (data.ok) {
          input.value = '';
          stopAnimDots(dotsTimerPost, statusEl, '등록됐어요!');
          statusEl.style.color = 'var(--success)';
          loadInquiries();
          setTimeout(() => { statusEl.textContent = ''; }, 2000);
        } else if (data.error === 'wrong_password' || data.error === 'unauthorized') {
          stopAnimDots(dotsTimerPost, statusEl, '인증 오류. 다시 로그인해주세요.');
          statusEl.style.color = 'var(--danger)';
        } else {
          stopAnimDots(dotsTimerPost, statusEl, '오류가 발생했어요.');
          statusEl.style.color = 'var(--danger)';
        }
      } catch(e) {
        stopAnimDots(dotsTimerPost, statusEl, '연결 오류');
        statusEl.style.color = 'var(--danger)';
      } finally {
        btn.disabled = false;
      }
    }

    document.getElementById('inquiryQuickBtn').addEventListener('click', async () => {
      submitInquiry('inquiryQuickInput', 'inquiryQuickStatus', 'inquiryQuickBtn');
    });

    document.getElementById('inquiryComposeBtn').addEventListener('click', async () => {
      submitInquiry('inquiryComposeInput', 'inquiryComposeStatus', 'inquiryComposeBtn');
    });

    document.getElementById('refreshInquiryBtn').addEventListener('click', loadInquiries);

    /* ════ B.B.B. ════ */
    let _bbbData = null;

    function _bbbShowPhoto(src) {
      const img = document.getElementById('bbbPhotoImg');
      img.src = src;
      img.style.display = 'block';
      const modalImg = document.getElementById('bbbPhotoModalImg');
      if (modalImg) modalImg.src = src;
      document.getElementById('bbbPhotoPlaceholder').style.display = 'none';
      document.getElementById('bbbPhotoPlaceholderText').style.display = 'none';
      document.getElementById('bbbPhotoLabel').style.border = '1px solid #1a1a1a';
    }
    function openBbbPhotoModal() {
      const modal = document.getElementById('bbbPhotoModal');
      if (modal) modal.style.display = 'flex';
    }
    function closeBbbPhotoModal() {
      const modal = document.getElementById('bbbPhotoModal');
      if (modal) modal.style.display = 'none';
    }
    function reopenBbbPhotoInput() {
      closeBbbPhotoModal();
      const input = document.getElementById('bbbPhotoInput');
      input.value = '';
      input.click();
    }
    async function deleteBbbPhoto() {
      if (!confirm('사진을 삭제할까요?')) return;
      closeBbbPhotoModal();
      const nickname = localStorage.getItem('beyondus_nickname') || '';
      const statusEl = document.getElementById('bbbPhotoStatus');
      let dotsTimer = null;
      if (statusEl) { dotsTimer = animDots(statusEl, '삭제 중'); statusEl.style.color = 'var(--sub)'; statusEl.style.fontWeight = '500'; }
      try {
        const res = await fetch(API_BASE, {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain' },
          body: JSON.stringify(withSession({ action: 'deleteBBBPhoto', userId: nickname })),
          redirect: 'follow'
        }).then(r => r.json());
        if (res.ok) {
          const img = document.getElementById('bbbPhotoImg');
          img.src = ''; img.style.display = 'none';
          const modalImg = document.getElementById('bbbPhotoModalImg');
          if (modalImg) modalImg.src = '';
          document.getElementById('bbbPhotoPlaceholder').style.display = '';
          document.getElementById('bbbPhotoPlaceholderText').style.display = '';
          document.getElementById('bbbPhotoLabel').style.border = '1.5px dashed var(--line)';
          if (statusEl) stopAnimDots(dotsTimer, statusEl, '');
        }
      } catch(e) {
        if (statusEl) stopAnimDots(dotsTimer, statusEl, '');
        alert('삭제 중 오류가 발생했어요.');
      }
    }

    let _bbbLoadPromise = null;
    let _bbbLoadedOnce = false;
    let _bbbLastLoadedAt = 0;
    const BBB_REFRESH_TTL_MS = 60000;

    async function loadBBB(silent = false, forceRefresh = false) {
      const nickname = localStorage.getItem('beyondus_nickname') || '';
      if (!nickname) return;
      const now = Date.now();
      if (!forceRefresh && _bbbLoadedOnce && now - _bbbLastLoadedAt < BBB_REFRESH_TTL_MS) return;
      if (_bbbLoadPromise) return _bbbLoadPromise;
      _bbbLoadPromise = (async () => {

      // 주기 동기화(silent) 시에는 로딩 UI를 띄우지 않아 깜빡임 방지
      if (!silent && !_bbbLoadedOnce) {
        document.getElementById('bbbLoading').style.display = '';
        document.getElementById('bbbContent').style.display = 'none';
        document.getElementById('bbbNoMatch').style.display = 'none';
        document.getElementById('bbbFieldMissionCard').style.display = 'none';
      }

      try {
        const [bbbRes, msgRes] = await Promise.all([
          fetch(`${API_BASE}?action=getBBB&userId=${encodeURIComponent(nickname)}${sessionParam()}`).then(r => r.json()),
          fetch(`${API_BASE}?action=getBBBMessages&userId=${encodeURIComponent(nickname)}${sessionParam()}`).then(r => r.json())
        ]);

        document.getElementById('bbbLoading').style.display = 'none';
        _bbbLoadedOnce = true;
        _bbbLastLoadedAt = Date.now();

        // 섹션별 Coming Soon / 오픈 토글 — 매칭 여부와 무관하게 먼저 적용
        // [key, csId, liveId, csDisplay, updateText]
        const _sectionMap = [
          ['careBuddy',   'bbbCareBuddyComingSoon', 'bbbCareBuddyLive', '', true ],
          ['m1',          'bbbM1ComingSoon',         'bbbM1Live',        '', true ],
          ['m2',          'bbbM2ComingSoon',         'bbbM2Live',        '', true ],
          ['m3',          'bbbM3ComingSoon',         'bbbM3Live',        '', true ],
          ['secretBuddy', 'bbbSecretComingSoon',     'bbbSecretLive',    '', true ],
        ];
        const _isDev = localStorage.getItem('beyondus_is_dev') === 'true';
        _sectionMap.forEach(([key, csId, liveId, csDisplay, updateText]) => {
          const sec  = _bbbSections[key] || {};
          const cs   = document.getElementById(csId);
          const live = document.getElementById(liveId);
          if (!sec.open && !_isDev) {
            if (cs) {
              cs.style.display = csDisplay || '';
              if (updateText) {
                const lines = (sec.text || 'Coming Soon!').split('\n');
                const spans = cs.querySelectorAll('span');
                if (spans[0]) spans[0].textContent = lines[0] || '';
                if (spans[1]) spans[1].textContent = lines[1] || '';
              }
            }
            if (live) live.style.display = 'none';
          } else {
            if (cs)   cs.style.display = 'none';
            if (live) live.style.display = '';
          }
        });

        // 메시지 보내기/받기 창 — 어드민 토글 기준 (스태프는 항상 오픈)
        const _msgOpen = _bbbSections.msgOpen?.open || _isDev;
        document.getElementById('bbbMsgSendWrap').style.display  = _msgOpen ? '' : 'none';
        document.getElementById('bbbMsgInboxWrap').style.display = _msgOpen ? '' : 'none';

        // 섹션 중 하나라도 잠금이면 bbbContent 표시 (매칭 없어도)
        const anyLocked = Object.values(_bbbSections).some(s => !s.open);
        if (!bbbRes.ok) {
          if (anyLocked || _isDev) {
            document.getElementById('bbbContent').style.display = 'flex';
            document.getElementById('bbbFieldMissionCard').style.display = '';
            if (_isDev) _bbbRenderM3Spots([null,null,null,null,null,null,null], false);
          } else {
            document.getElementById('bbbNoMatch').style.display = '';
          }
          return;
        }

        _bbbData = bbbRes;
        document.getElementById('bbbContent').style.display = 'flex';
        document.getElementById('bbbFieldMissionCard').style.display = '';

        // 케어버디
        document.getElementById('bbbCareBuddyName').textContent = bbbRes.careBuddy.name + ' 🗣️👂';
        document.getElementById('bbbCaughtBadge').style.display = bbbRes.caughtByBuddy ? '' : 'none';

        // 사진
        if (bbbRes.myPhoto) {
          _bbbShowPhoto(bbbRes.myPhoto);
          const st = document.getElementById('bbbPhotoStatus');
          if (st) { st.textContent = '✓ 뽑기권 획득 완료'; st.style.color = 'var(--sub)'; st.style.fontWeight = '500'; }
        }

        document.getElementById('bbbPhotoInput').onchange = async function() {
          const file = this.files[0];
          if (!file) return;
          const statusEl = document.getElementById('bbbPhotoStatus');
          const label = document.getElementById('bbbPhotoLabel');
          const dotsTimer = animDots(statusEl, '업로드 중');
          label.style.pointerEvents = 'none';
          try {
            const base64 = await _compressImage(file, 400, 0.55);
            const REDIRECT = await fetch(API_BASE, {
              method: 'POST',
              headers: { 'Content-Type': 'text/plain' },
              body: JSON.stringify(withSession({ action: 'uploadBBBPhoto', userId: nickname, photo: base64, missionType: 'm1' })),
              redirect: 'follow'
            });
            const res = await REDIRECT.json();
            if (res.ok) {
              _bbbShowPhoto(base64);
              stopAnimDots(dotsTimer, statusEl, res.rewarded ? '뽑기권 1개 지급됐어요 🎫' : '✓ 뽑기권 획득 완료');
              statusEl.style.color = res.rewarded ? 'var(--primary)' : 'var(--sub)';
              statusEl.style.fontWeight = res.rewarded ? '600' : '500';
            } else {
              stopAnimDots(dotsTimer, statusEl, res.error || '업로드 실패');
            }
          } catch(e) {
            stopAnimDots(dotsTimer, statusEl, '오류: ' + e.message);
          } finally {
            label.style.pointerEvents = '';
          }
        };

        // MISSION 2
        _bbbInitMission2(bbbRes);

        // MISSION 3
        _bbbInitMission3(bbbRes);

        // 시크릿버디
        if (bbbRes.secretBuddy) {
          if (bbbRes.secretBuddy.revealed) {
            document.getElementById('bbbSecretRevealed').style.display = '';
            document.getElementById('bbbSecretGuess').style.display = 'none';
            document.getElementById('bbbSecretName').textContent =
              bbbRes.secretBuddy.name || bbbRes.secretBuddy.nickname || '—';
          } else {
            document.getElementById('bbbSecretRevealed').style.display = 'none';
            document.getElementById('bbbSecretGuess').style.display = '';
            document.getElementById('bbbSecretHint').textContent =
              '나를 몰래 챙겨주는 사람이 있어요. 누구일까요?';
          }
        } else {
          document.getElementById('bbbSecretLive').style.display = 'none';
        }

        // 받은 메시지 + 보낸 메시지
        _renderBBBMessages(msgRes.messages || []);
        _renderBBBSentMessages(msgRes.sent || []);

      } catch(e) {
        if (!silent) {
          document.getElementById('bbbLoading').textContent = '불러오기 실패. 다시 시도해주세요.';
        }
      }
      })().finally(() => { _bbbLoadPromise = null; });
      return _bbbLoadPromise;
    }

    /* ── MISSION 2 ── */
    function _bbbShowM2Photo(src) {
      const img = document.getElementById('bbbM2Img');
      const modalImg = document.getElementById('bbbM2ModalImg');
      img.src = src; img.style.display = '';
      if (modalImg) modalImg.src = src;
      document.getElementById('bbbM2Placeholder').style.display = 'none';
      document.getElementById('bbbM2PlaceholderText').style.display = 'none';
      document.getElementById('bbbM2Label').style.border = '1px solid #1a1a1a';
    }
    function openBbbM2Modal() {
      const modal = document.getElementById('bbbM2Modal');
      modal.style.display = 'flex';
    }
    function closeBbbM2Modal() {
      document.getElementById('bbbM2Modal').style.display = 'none';
    }
    function reopenBbbM2Input() {
      closeBbbM2Modal();
      document.getElementById('bbbM2Input').click();
    }
    async function deleteBbbM2Photo() {
      const statusEl = document.getElementById('bbbM2Status');
      const dotsTimer = animDots(statusEl, '삭제 중');
      closeBbbM2Modal();
      try {
        const nickname = localStorage.getItem('beyondus_nickname') || '';
        const res = await fetch(API_BASE, {
          method: 'POST', headers: { 'Content-Type': 'text/plain' },
          body: JSON.stringify(withSession({ action: 'deleteBBBPhoto', userId: nickname, missionType: 'm2' })),
          redirect: 'follow'
        });
        const data = await res.json();
        if (data.ok) {
          const img = document.getElementById('bbbM2Img');
          img.src = ''; img.style.display = 'none';
          document.getElementById('bbbM2Placeholder').style.display = '';
          document.getElementById('bbbM2PlaceholderText').style.display = '';
          document.getElementById('bbbM2Label').style.border = '1.5px dashed var(--line)';
          stopAnimDots(dotsTimer, statusEl, '');
        } else {
          stopAnimDots(dotsTimer, statusEl, '삭제 실패');
        }
      } catch(e) { stopAnimDots(dotsTimer, statusEl, '오류'); }
    }
    function _bbbInitMission2(bbbRes) {
      const statusEl = document.getElementById('bbbM2Status');
      if (bbbRes.myPhotoM2) {
        _bbbShowM2Photo(bbbRes.myPhotoM2);
        if (statusEl) { statusEl.textContent = bbbRes.m2Rewarded ? '✓ 뽑기권 획득 완료' : ''; statusEl.style.color = 'var(--sub)'; statusEl.style.fontWeight = '500'; }
      }
      document.getElementById('bbbM2Input').onchange = async function() {
        const file = this.files[0];
        if (!file) return;
        const label = document.getElementById('bbbM2Label');
        const dotsTimer = animDots(statusEl, '업로드 중');
        label.style.pointerEvents = 'none';
        try {
          const nickname = localStorage.getItem('beyondus_nickname') || '';
          const base64 = await _compressImage(file, 400, 0.55);
          const res = await (await fetch(API_BASE, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: JSON.stringify(withSession({ action: 'uploadBBBPhoto', userId: nickname, photo: base64, missionType: 'm2' })), redirect: 'follow' })).json();
          if (res.ok) {
            _bbbShowM2Photo(base64);
            stopAnimDots(dotsTimer, statusEl, res.rewarded ? '뽑기권 1개 지급됐어요 🎫' : '✓ 뽑기권 획득 완료');
            statusEl.style.color = res.rewarded ? 'var(--primary)' : 'var(--sub)';
            statusEl.style.fontWeight = res.rewarded ? '600' : '500';
            if (res.rewarded) loadUserStatus();
          } else { stopAnimDots(dotsTimer, statusEl, res.error || '업로드 실패'); }
        } catch(e) { stopAnimDots(dotsTimer, statusEl, '오류: ' + e.message); }
        finally { label.style.pointerEvents = ''; }
      };
    }

    /* ── MISSION 3 ── */
    const BBB_M3_SPOTS = [
      { label: '좁은문',               top: 48, left: 45 }, // #6
      { label: '십자가',               top: 33, left: 65 }, // #14
      { label: '뷰티풀하우스',         top: 62, left: 48.5 }, // #20~23
      { label: '사망의 음침한 골짜기',  top: 81, left: 81 }, // #25
      { label: '기쁨의 산',            top: 16, left: 86 }, // #31
      { label: '뿔라의 땅',            top: 16, left: 44 }, // #36
      { label: '천성',                 top: 44, left: 12 }, // #39
    ];

    function _bbbRenderM3Spots(photos, m3Rewarded) {
      const container = document.getElementById('bbbM3Spots');
      if (!container) return;
      const SIZE = 46; // px
      container.innerHTML = BBB_M3_SPOTS.map((spot, i) => {
        const src = photos[i];
        const circleStyle = src
          ? `border:1px solid rgba(255,255,255,0.7);box-shadow:0 2px 8px rgba(0,0,0,0.28);background:transparent;`
          : `border:1px dashed rgba(255,255,255,0.9);box-shadow:0 1px 4px rgba(0,0,0,0.18);background:rgba(255,255,255,0.55);`;
        return `
          <div style="position:absolute;top:${spot.top}%;left:${spot.left}%;transform:translate(-50%,-50%);display:flex;flex-direction:column;align-items:center;gap:2px;z-index:2;">
            <div style="width:${SIZE}px;height:${SIZE}px;border-radius:50%;overflow:hidden;${circleStyle}display:flex;align-items:center;justify-content:center;cursor:pointer;"
                 onclick="${src ? `openBbbM3Modal(${i})` : `document.getElementById('bbbM3Input${i}').click()`}">
              ${src ? `<img src="${src}" style="width:100%;height:100%;object-fit:cover;" />` : `<span style="font-size:20px;color:rgba(255,255,255,0.85);font-weight:300;line-height:1;">+</span>`}
            </div>
            <span style="font-size:9px;font-weight:700;color:#333;background:rgba(255,255,255,0.85);padding:1px 5px;border-radius:6px;white-space:nowrap;">${spot.label}</span>
            <input type="file" id="bbbM3Input${i}" accept="image/*" style="display:none;" onchange="bbbM3Upload(${i}, this)" />
          </div>`;
      }).join('');
      const filled = photos.filter(Boolean).length;
      const statusEl = document.getElementById('bbbM3Status');
      if (statusEl) {
        statusEl.textContent = m3Rewarded ? '✓ 뽑기권 획득 완료' : filled > 0 ? `${filled}/7 완료` : '';
        statusEl.style.color = m3Rewarded ? 'var(--sub)' : 'var(--primary)';
      }
    }
    function _bbbInitMission3(bbbRes) {
      _bbbRenderM3Spots(bbbRes.myPhotoM3 || [null,null,null,null,null,null,null], bbbRes.m3Rewarded);
    }
    async function bbbM3Upload(spotIdx, input) {
      const file = input.files[0];
      if (!file) return;
      const statusEl = document.getElementById('bbbM3Status');
      const dotsTimer = animDots(statusEl, '업로드 중');
      try {
        const nickname = localStorage.getItem('beyondus_nickname') || '';
        const base64 = await _compressImage(file, 400, 0.55);
        const res = await (await fetch(API_BASE, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: JSON.stringify(withSession({ action: 'uploadBBBPhoto', userId: nickname, photo: base64, missionType: 'm3_' + spotIdx })), redirect: 'follow' })).json();
        if (res.ok) {
          if (_bbbData) { _bbbData.myPhotoM3 = _bbbData.myPhotoM3 || [null,null,null,null,null,null,null]; _bbbData.myPhotoM3[spotIdx] = base64; if (res.rewarded) _bbbData.m3Rewarded = true; }
          _bbbRenderM3Spots(_bbbData ? _bbbData.myPhotoM3 : [], res.rewarded || (_bbbData && _bbbData.m3Rewarded));
          stopAnimDots(dotsTimer, statusEl, '');
          if (res.rewarded) { loadUserStatus(); }
        } else { stopAnimDots(dotsTimer, statusEl, res.error || '업로드 실패'); }
      } catch(e) { stopAnimDots(dotsTimer, statusEl, '오류: ' + e.message); }
    }
    function openBbbM3Modal(spotIdx) {
      const src = _bbbData && _bbbData.myPhotoM3 && _bbbData.myPhotoM3[spotIdx];
      if (!src) return;
      const modal = document.getElementById('bbbM3Modal');
      if (!modal) return;
      document.getElementById('bbbM3ModalImg').src = src;
      modal.dataset.spot = spotIdx;
      modal.style.display = 'flex';
    }
    function closeBbbM3Modal() { const m = document.getElementById('bbbM3Modal'); if (m) m.style.display = 'none'; }
    function openBbbM3MapModal() { const m = document.getElementById('bbbM3MapModal'); if (m) { m.style.display = 'flex'; } }
    function closeBbbM3MapModal() { const m = document.getElementById('bbbM3MapModal'); if (m) m.style.display = 'none'; }
    function reopenBbbM3Input() { const spot = Number(document.getElementById('bbbM3Modal').dataset.spot); closeBbbM3Modal(); document.getElementById('bbbM3Input' + spot)?.click(); }
    async function deleteBbbM3Photo() {
      const spotIdx = Number(document.getElementById('bbbM3Modal').dataset.spot);
      const statusEl = document.getElementById('bbbM3Status');
      closeBbbM3Modal();
      const dotsTimer = animDots(statusEl, '삭제 중');
      try {
        const nickname = localStorage.getItem('beyondus_nickname') || '';
        const res = await (await fetch(API_BASE, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: JSON.stringify(withSession({ action: 'deleteBBBPhoto', userId: nickname, missionType: 'm3_' + spotIdx })), redirect: 'follow' })).json();
        if (res.ok) {
          if (_bbbData && _bbbData.myPhotoM3) _bbbData.myPhotoM3[spotIdx] = null;
          _bbbRenderM3Spots(_bbbData ? _bbbData.myPhotoM3 : [], _bbbData && _bbbData.m3Rewarded);
          stopAnimDots(dotsTimer, statusEl, '');
        } else { stopAnimDots(dotsTimer, statusEl, '삭제 실패'); }
      } catch(e) { stopAnimDots(dotsTimer, statusEl, '오류'); }
    }

    function _renderBBBMessages(messages) {
      const el = document.getElementById('bbbMsgList');
      if (!messages.length) {
        el.innerHTML = '<p style="font-size:13px;color:var(--sub);text-align:center;padding:8px 0;">아직 받은 메시지가 없어요.</p>';
        return;
      }
      function _fmtBBBDate(s) {
        if (!s) return '';
        const d = new Date(s.replace(' ', 'T'));
        if (isNaN(d)) return s.slice(0, 16).replace('T', ' ');
        const yy = String(d.getFullYear()).slice(2);
        const mo = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        const hh = d.getHours(), mm = String(d.getMinutes()).padStart(2, '0');
        const ampm = hh < 12 ? 'AM' : 'PM';
        const h12 = hh % 12 || 12;
        return `${yy}.${mo}.${dd} ${h12}:${mm} ${ampm}`;
      }
      // 받은 메시지 = 왼쪽 정렬 (시크릿버디 → 나)
      function _bubble(m) {
        return `<div style="display:flex;justify-content:flex-start;margin-bottom:6px;">
          <div style="max-width:80%;background:var(--primary-soft);border-radius:12px 12px 12px 2px;padding:10px 13px;">
            <p style="font-size:14px;color:var(--text);margin:0 0 4px;line-height:1.5;white-space:pre-wrap;">${escHtml(m.message)}</p>
            <p style="font-size:10px;color:var(--sub);margin:0;text-align:right;">${_fmtBBBDate(m.createdAt)}</p>
          </div>
        </div>`;
      }
      const latest = messages[messages.length - 1];
      const older  = messages.slice(0, messages.length - 1);
      const olderHtml = older.length
        ? `<div id="bbbMsgHistoryWrap" style="display:none;max-height:280px;overflow-y:auto;padding-bottom:4px;">${older.map(_bubble).join('')}</div>
           <button id="bbbMsgHistoryBtn" data-count="${older.length}" onclick="(function(b){var w=document.getElementById('bbbMsgHistoryWrap'),open=w.style.display!=='none';w.style.display=open?'none':'';b.textContent=open?'▾ 이전 메시지 보기 ('+b.dataset.count+'개)':'▴ 접기';})(this)" style="display:block;width:100%;background:none;border:none;font-size:12px;color:var(--sub);padding:4px 0 6px;cursor:pointer;text-align:center;">▾ 이전 메시지 보기 (${older.length}개)</button>`
        : '';
      el.innerHTML = olderHtml + _bubble(latest);
    }

    // 보낸 메시지 = 오른쪽 정렬 (나 → 케어버디)
    function _renderBBBSentMessages(messages) {
      const el = document.getElementById('bbbSentMsgList');
      if (!el) return;
      if (!messages.length) {
        el.innerHTML = '';
        return;
      }
      function _fmtBBBDate(s) {
        if (!s) return '';
        const d = new Date(s.replace(' ', 'T'));
        if (isNaN(d)) return s.slice(0, 16).replace('T', ' ');
        const yy = String(d.getFullYear()).slice(2);
        const mo = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        const hh = d.getHours(), mm = String(d.getMinutes()).padStart(2, '0');
        const ampm = hh < 12 ? 'AM' : 'PM';
        const h12 = hh % 12 || 12;
        return `${yy}.${mo}.${dd} ${h12}:${mm} ${ampm}`;
      }
      function _bubble(m) {
        return `<div style="display:flex;justify-content:flex-end;margin-bottom:6px;">
          <div style="max-width:80%;background:var(--primary);color:#faf6ef;border-radius:12px 12px 2px 12px;padding:10px 13px;">
            <p style="font-size:14px;margin:0 0 4px;line-height:1.5;white-space:pre-wrap;">${escHtml(m.message)}</p>
            <p style="font-size:10px;opacity:0.7;margin:0;text-align:left;">${_fmtBBBDate(m.createdAt)}</p>
          </div>
        </div>`;
      }
      // 최신 메시지는 기본 미표시 — 버튼 클릭 시 전체 노출
      el.innerHTML = `<div id="bbbSentHistoryWrap" style="display:none;max-height:280px;overflow-y:auto;padding-bottom:4px;">${messages.map(_bubble).join('')}</div>
        <button id="bbbSentHistoryBtn" data-count="${messages.length}" onclick="(function(b){var w=document.getElementById('bbbSentHistoryWrap'),open=w.style.display!=='none';w.style.display=open?'none':'';b.textContent=open?'▾ 보낸 메시지 보기 ('+b.dataset.count+'개)':'▴ 접기';})(this)" style="display:block;width:100%;background:none;border:none;font-size:12px;color:var(--sub);padding:4px 0 6px;cursor:pointer;text-align:center;">▾ 보낸 메시지 보기 (${messages.length}개)</button>`;
    }

    async function submitBBBGuess() {
      const nickname = localStorage.getItem('beyondus_nickname') || '';
      const guess = document.getElementById('bbbGuessInput').value.trim();
      const msgEl = document.getElementById('bbbGuessMsg');
      const btn = document.querySelector('#bbbSecretGuess button');
      if (!guess) { msgEl.style.color = '#f87171'; msgEl.textContent = '닉네임 또는 이름을 입력해주세요.'; return; }

      if (btn) btn.disabled = true;
      msgEl.style.color = 'var(--sub)';
      const dotsTimer = animDots(msgEl, '확인 중');
      try {
        const res = await post({ action: 'guessBBBSecret', userId: nickname, guess });
        if (res.error) { stopAnimDots(dotsTimer, msgEl, res.error); msgEl.style.color = '#f87171'; return; }
        if (res.correct) {
          stopAnimDots(dotsTimer, msgEl, '정답이에요! 🎉');
          msgEl.style.color = '#4ade80';
          document.getElementById('bbbSecretName').textContent = res.secretName || res.secretNickname;
          document.getElementById('bbbSecretRevealed').style.display = '';
          document.getElementById('bbbSecretGuess').style.display = 'none';
        } else {
          stopAnimDots(dotsTimer, msgEl, '아니에요. 다시 생각해봐요!');
          msgEl.style.color = '#f87171';
          document.getElementById('bbbGuessInput').value = '';
        }
      } catch(e) { stopAnimDots(dotsTimer, msgEl, '연결 오류'); msgEl.style.color = '#f87171'; }
      finally { if (btn) btn.disabled = false; }
    }

    async function sendBBBMsg() {
      const nickname = localStorage.getItem('beyondus_nickname') || '';
      const message  = document.getElementById('bbbMsgInput').value.trim();
      const resultEl = document.getElementById('bbbMsgSendResult');
      const btn      = document.getElementById('bbbMsgSendBtn');
      if (!message) { resultEl.style.color = '#f87171'; resultEl.textContent = '메시지를 입력해주세요.'; return; }

      btn.disabled = true;
      btn.innerHTML = '<span style="display:flex;gap:5px;align-items:center;justify-content:center;height:16px;">' +
        '<span style="width:6px;height:6px;border-radius:50%;background:#faf6ef;display:inline-block;animation:splashDot 1.2s ease-in-out infinite;"></span>' +
        '<span style="width:6px;height:6px;border-radius:50%;background:#faf6ef;display:inline-block;animation:splashDot 1.2s ease-in-out .2s infinite;"></span>' +
        '<span style="width:6px;height:6px;border-radius:50%;background:#faf6ef;display:inline-block;animation:splashDot 1.2s ease-in-out .4s infinite;"></span>' +
        '</span>';
      try {
        const res = await post({ action: 'sendBBBMessage', userId: nickname, message });
        if (res.error) { resultEl.style.color = '#f87171'; resultEl.textContent = res.error; return; }
        resultEl.style.color = '#4ade80';
        resultEl.textContent = '메시지를 보냈어요! 💌';
        document.getElementById('bbbMsgInput').value = '';
        setTimeout(() => { resultEl.textContent = ''; }, 3000);
      } catch(e) {
        resultEl.style.color = '#f87171'; resultEl.textContent = '연결 오류';
      } finally {
        btn.disabled = false;
        btn.innerHTML = '보내기';
      }
    }

    /* ════ Hold & Pray ════ */
    let _hpCards = [];
    let _hpCurrentIdx = 0;
    let _hpWeekKey = '';
    let _hpCorrectMap = {}; // {cardIndex: name} — per week, loaded from localStorage
    let _hpTicketAlreadyAwarded = false;
    let _hpTicketCardIdx = -1;
    let _hpHintReplies = {};
    let _hpRevision = '';

    function fitHpText(textEl, boxEl, opts = {}) {
      if (!textEl || !boxEl) return;
      const max = opts.max ?? 19;
      const min = opts.min ?? 9;
      textEl.style.visibility = 'hidden';
      textEl.style.fontSize = max + 'px';
      textEl.style.lineHeight = '1.5';
      if (boxEl.clientHeight === 0) {
        requestAnimationFrame(() => {
          textEl.style.visibility = '';
          fitHpText(textEl, boxEl, opts);
        });
        return;
      }
      let fs = max;
      while (fs > min &&
             (textEl.scrollHeight > boxEl.clientHeight ||
              textEl.scrollWidth  > boxEl.clientWidth)) {
        fs -= 0.5;
        textEl.style.fontSize = fs + 'px';
      }
      textEl.style.visibility = '';
    }

    async function loadHoldPray(forceRefresh) {
      const el = document.getElementById('hpContent');
      if (!el) return;

      if (_hpCards.length === 3 && !forceRefresh) {
        renderHoldPray();
        return;
      }

      const nick = localStorage.getItem('beyondus_nickname') || '';
      const hpCacheKey = 'beyondus_cache_hp_' + nick;
      const hpCached = JSON.parse(localStorage.getItem(hpCacheKey) || 'null');
      let hpHasCache = false;

      if (hpCached && hpCached.ok) {
        _hpCards = hpCached.cards || [];
        _hpWeekKey = hpCached.weekKey || '';
        _hpRevision = hpCached.hpRevision || '';
        _hpCurrentIdx = 0;
        _hpCorrectMap = {};
        _hpTicketAlreadyAwarded = hpCached.ticketAlreadyAwarded || false;
        _hpTicketCardIdx = hpCached.ticketCardIdx ?? -1;
        _hpHintReplies = hpCached.hintReplies || {};
        _hpCards.forEach((_, i) => {
          const saved = localStorage.getItem('beyondus_hp_correct_' + _hpWeekKey + '_' + i);
          if (saved) _hpCorrectMap[i] = saved;
        });
        renderHoldPray();
        updatePrayerDot();
        hpHasCache = true;
      } else {
        el.innerHTML = `
          <div style="display:flex;flex-direction:column;align-items:center;justify-content:center;flex:1;padding:40px 0;gap:20px;">
            <img src="images/hc_logo_png2.png" style="width:120px;height:auto;" alt="Beyond Us" />
            <div style="display:flex;gap:8px;align-items:center;">
              <div style="width:8px;height:8px;border-radius:50%;background:var(--primary);animation:splashDot 1.2s ease-in-out infinite;"></div>
              <div style="width:8px;height:8px;border-radius:50%;background:var(--primary);animation:splashDot 1.2s ease-in-out .2s infinite;"></div>
              <div style="width:8px;height:8px;border-radius:50%;background:var(--primary);animation:splashDot 1.2s ease-in-out .4s infinite;"></div>
            </div>
          </div>`;
      }
      if (hpHasCache && !forceRefresh) return;

      try {
        const [res] = await Promise.all([
          fetch(`${API_BASE}?action=getHoldPray&weekKey=&nickname=${encodeURIComponent(nick)}&t=${Date.now()}`),
          document.fonts.load('1em "Nanum Pen Script"').catch(() => {})
        ]);
        const data = await res.json();
        if (!data.ok) throw new Error(data.error || 'error');
        localStorage.setItem(hpCacheKey, JSON.stringify(data));
        const sameWeek = hpCached && hpCached.weekKey === data.weekKey;
        const prevIdx = _hpCurrentIdx;
        _hpCards = data.cards || [];
        _hpWeekKey = data.weekKey || '';
        _hpRevision = data.hpRevision || '';
        _hpCurrentIdx = (hpHasCache && sameWeek) ? prevIdx : 0;
        _hpCorrectMap = {};
        _hpTicketAlreadyAwarded = data.ticketAlreadyAwarded || false;
        _hpTicketCardIdx = data.ticketCardIdx ?? -1;
        _hpHintReplies = data.hintReplies || {};
        _hpCards.forEach((_, i) => {
          const saved = localStorage.getItem('beyondus_hp_correct_' + _hpWeekKey + '_' + i);
          if (saved) _hpCorrectMap[i] = saved;
        });
        if (data.correctMap) {
          _hpCards.forEach((_, i) => {
            if (!(String(i) in data.correctMap)) {
              delete _hpCorrectMap[i];
              localStorage.removeItem('beyondus_hp_correct_' + _hpWeekKey + '_' + i);
            }
          });
          Object.keys(data.correctMap).forEach(k => {
            const i = Number(k);
            _hpCorrectMap[i] = data.correctMap[k];
            localStorage.setItem('beyondus_hp_correct_' + _hpWeekKey + '_' + i, data.correctMap[k]);
          });
        }
        renderHoldPray();
        updatePrayerDot();
      } catch(e) {
        if (!hpHasCache) el.innerHTML = '<div class="hp-loading">불러오지 못했어요. 잠시 후 다시 시도해주세요.</div>';
      }
    }

    function hpConfetti() {
      const colors = ['#f4a261','#e76f51','#2a9d8f','#e9c46a','#ff9f1c','#a8dadc','#ffb347','#c77dff'];
      const cx = window.innerWidth / 2;
      const cy = window.innerHeight / 2;
      for (let i = 0; i < 32; i++) {
        const el = document.createElement('div');
        const size = 6 + Math.random() * 6;
        el.style.cssText = `position:fixed;width:${size}px;height:${size}px;border-radius:${Math.random()>.5?'50%':'3px'};background:${colors[i%colors.length]};left:${cx}px;top:${cy}px;pointer-events:none;z-index:9999;`;
        document.body.appendChild(el);
        const angle = (Math.random() * 360) * Math.PI / 180;
        const dist = 80 + Math.random() * 140;
        gsap.to(el, {
          x: Math.cos(angle) * dist, y: Math.sin(angle) * dist + 60,
          opacity: 0, rotation: Math.random() * 720 - 360,
          duration: 0.7 + Math.random() * 0.7, ease: 'power2.out',
          onComplete: () => el.remove()
        });
      }
    }

    function updateHpBadge() { /* badge removed — info lives in hp-guess-box */ }

    function renderHoldPray() {
      const el = document.getElementById('hpContent');
      if (!el || !_hpCards.length) return;
      const total = _hpCards.length;
      updateHpBadge();
      if (_hpWeekKey) { localStorage.setItem('beyondus_hp_ticket_seen_' + _hpWeekKey, '1'); updatePrayerDot(); }

      el.innerHTML = `
        <div class="hp-carousel-wrap" id="hpCarouselWrap">
          <div id="hpCardSlot"></div>
        </div>
        <button class="btn btn-secondary hp-home-btn" onclick="switchSection('mission')">← 홈으로 가기</button>`;

      renderHpCard(_hpCurrentIdx);

      const wrap = document.getElementById('hpCarouselWrap');
      if (wrap) {
        let touchStartX = 0, touchStartY = 0, touchLocked = false;
        wrap.addEventListener('touchstart', e => {
          touchStartX = e.touches[0].clientX;
          touchStartY = e.touches[0].clientY;
          touchLocked = false;
        }, { passive: false });
        wrap.addEventListener('touchmove', e => {
          const dx = Math.abs(e.touches[0].clientX - touchStartX);
          const dy = Math.abs(e.touches[0].clientY - touchStartY);
          if (!touchLocked) touchLocked = dx > dy ? 'h' : 'v';
          if (touchLocked === 'h') e.preventDefault();
        }, { passive: false });
        wrap.addEventListener('touchend', e => {
          const dx = e.changedTouches[0].clientX - touchStartX;
          if (Math.abs(dx) > 40) dx < 0 ? hpGoTo(_hpCurrentIdx + 1) : hpGoTo(_hpCurrentIdx - 1);
        });
        let mouseStartX = 0, mouseDragging = false;
        wrap.addEventListener('mousedown', e => { mouseDragging = true; mouseStartX = e.clientX; });
        wrap.addEventListener('mousemove', e => { if (mouseDragging) e.preventDefault(); }, { passive: false });
        wrap.addEventListener('mouseup', e => {
          if (!mouseDragging) return;
          mouseDragging = false;
          const dx = e.clientX - mouseStartX;
          if (Math.abs(dx) > 40) dx < 0 ? hpGoTo(_hpCurrentIdx + 1) : hpGoTo(_hpCurrentIdx - 1);
        });
        wrap.addEventListener('mouseleave', () => { mouseDragging = false; });
      }
    }

    function renderHpCard(idx) {
      const slot = document.getElementById('hpCardSlot');
      if (!slot || !_hpCards[idx]) return;
      const card = _hpCards[idx];
      const correctName = _hpCorrectMap[idx];

      const isTicketWeek = (_hpWeekKey === 'w3' || _hpWeekKey === 'w6');
      const ticketFooterCorrect = !isTicketWeek ? ''
        : (idx === _hpTicketCardIdx && _hpTicketCardIdx !== -1)
          ? `<p class="hp-ticket-done">공동체를 위해 기도해 주셔서 감사합니다.<br>뽑기권 1장 넣어드렸어요~ 🎫</p>`
          : `<p class="hp-ticket-done">공동체를 위해 기도해 주셔서 감사합니다.</p>`;
      // 미답 카드는 아직 미획득일 때만 "지급 예고" 표시
      const ticketFooterGuess = (isTicketWeek && !_hpTicketAlreadyAwarded)
        ? `<p class="hp-ticket-reward">🎫 정답 시 뽑기권이 지급돼요</p>`
        : '';
      const boxClass = `hp-guess-box${isTicketWeek ? ' ticket-week' : ''}`;

      let bottomHtml;
      if (card.anon) {
        bottomHtml = `<p class="hp-anon-label">익명으로 제출된 기도제목이에요 🙏</p>`;
      } else if (correctName) {
        bottomHtml = `
          <div class="${boxClass}">
            <div class="hp-inline-guess">
              <span class="hp-inline-label">이름 :</span>
              <span class="hp-inline-name">${escHtml(correctName)}</span>
            </div>
            ${ticketFooterCorrect}
          </div>`;
      } else {
        let hintHtml;
        if (_hpHintReplies[idx]) {
          hintHtml = `<p class="hp-hint-below-reply">💡 ${escHtml(_hpHintReplies[idx])}</p>`;
        } else if (localStorage.getItem('beyondus_hp_hint_' + _hpWeekKey + '_' + idx)) {
          hintHtml = `<p class="hp-hint-below-pending">힌트 요청이 접수됐어요 🙏</p>`;
        } else {
          hintHtml = `<button class="hp-hint-below" onclick="hpHintInquiry(${idx})">현수막에서 카드를 못 찾겠어요</button>`;
        }
        const promptText = (isTicketWeek && _hpTicketAlreadyAwarded)
          ? '뽑기권은 이미 받았어도 주인공을 맞혀볼 수 있어요!'
          : '이 기도제목의 주인공이 누구인지 알 것 같다면?';
        bottomHtml = `
          <div class="${boxClass}" id="hpGuessBox">
            <p class="hp-guess-prompt">${promptText}</p>
            <div class="hp-inline-guess" id="hpInlineGuess">
              <span class="hp-inline-label">이름</span>
              <input class="hp-inline-input" id="hpGuessInput" type="text" maxlength="10" autocomplete="off" placeholder="이름 입력" />
              <button class="hp-inline-btn" id="hpGuessBtn" onclick="guessHoldPray(${idx})">확인</button>
            </div>
            ${hintHtml}
            <p class="hp-result-inline" id="hpResult" style="display:none;"></p>
            ${ticketFooterGuess}
          </div>`;
      }

      const dotsHtml = `<div class="hp-dots" id="hpDots">${_hpCards.map((_, i) => `<span class="hp-dot${i === idx ? ' active' : ''}" onclick="hpGoTo(${i})"></span>`).join('')}</div>`;

      slot.innerHTML = `
        <div class="hp-card-frame">
          <div class="hp-card" style="margin-top:8px;">
            <img src="images/h&amp;p익명.jpeg" class="hp-card-img" alt="Hold &amp; Pray" />
            <div class="hp-overlay">
              <p class="hp-overlay-text">${escHtml(card.content).replace(/ (\d+\.) /g, '<br>$1 ')}</p>
            </div>
          </div>
        </div>
        ${dotsHtml}
        <div class="hp-bottom-area" style="margin-top:14px;">
          <p class="hp-lobby-inline">위 기도제목이 누구인지 궁금하다면,<br>1층 로비 Hold &amp; Pray 현수막에서 찾아보세요!<br>다른 지체의 기도제목에도 손을 얹어 함께 기도해주세요.</p>
          ${bottomHtml}
        </div>`;

      const input = document.getElementById('hpGuessInput');
      if (input) {
        const capturedIdx = idx;
        input.addEventListener('keydown', e => { if (e.key === 'Enter') guessHoldPray(capturedIdx); });
      }

      const overlayEl  = slot.querySelector('.hp-overlay');
      const overlayTxt = slot.querySelector('.hp-overlay-text');
      if (overlayTxt && overlayEl) fitHpText(overlayTxt, overlayEl);
    }

    function hpGoTo(idx) {
      const total = _hpCards.length;
      if (idx < 0 || idx >= total) return;
      const dir = idx > _hpCurrentIdx ? 'right' : 'left';
      _hpCurrentIdx = idx;
      renderHpCard(idx);
      const slot = document.getElementById('hpCardSlot');
      if (slot) {
        slot.classList.remove('hp-slide-from-right', 'hp-slide-from-left');
        void slot.offsetWidth;
        slot.classList.add(dir === 'right' ? 'hp-slide-from-right' : 'hp-slide-from-left');
      }
    }

    async function guessHoldPray(cardIdx) {
      if (_hpCorrectMap[cardIdx]) return;
      const input  = document.getElementById('hpGuessInput');
      const btn    = document.getElementById('hpGuessBtn');
      const result = document.getElementById('hpResult');
      const guess  = (input?.value || '').trim();
      if (!guess || !_hpCards.length) return;

      btn.disabled = true;
      if (result) result.style.display = 'none';

      try {
        const res = await fetch(API_BASE, {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain;charset=utf-8' },
          body: JSON.stringify(withSession({ action: 'submitHoldPrayGuess', weekKey: _hpWeekKey, guess, nickname: localStorage.getItem('beyondus_nickname') || '', cardIndex: cardIdx }))
        });
        const data = await res.json();
        if (data.correct) {
          _hpCorrectMap[cardIdx] = guess;
          localStorage.setItem('beyondus_hp_correct_' + _hpWeekKey + '_' + cardIdx, guess);
          renderHpCard(cardIdx);
          hpConfetti();
          const slot = document.getElementById('hpCardSlot');
          if (slot) {
            const msg = document.createElement('p');
            msg.className = 'hp-correct-msg';
            msg.textContent = '맞췄어요! 기도해주셔서 감사합니다 🙏';
            (slot.querySelector('.hp-guess-box') || slot.querySelector('.hp-bottom-area'))?.appendChild(msg);
          }
          if (data.ticketAwarded) {
            _hpTicketAlreadyAwarded = true;
            _hpTicketCardIdx = cardIdx;
            updateHpBadge();
            const ticketBadge = document.getElementById('ticketBadge');
            if (ticketBadge) {
              const cur = parseInt(ticketBadge.textContent.replace(/\D/g, '')) || 0;
              ticketBadge.textContent = `🎫 ${cur + 1}`;
            }
            if (slot) {
              const toast = document.createElement('button');
              toast.className = 'hp-ticket-notice';
              toast.textContent = '뽑기권 1장을 넣어드렸어요~ 🎫';
              toast.onclick = () => switchSection('mission');
              (slot.querySelector('.hp-guess-box') || slot.querySelector('.hp-bottom-area'))?.appendChild(toast);
            }
            loadUserStatus();
          }
        } else {
          if (result) { result.textContent = '아니에요. 1층 로비 현수막에서 한번 찾아봐요! 👀'; result.className = 'hp-result-inline wrong'; result.style.display = ''; }
          btn.disabled = false;
          if (input) { input.value = ''; input.focus(); }
        }
      } catch(e) {
        if (result) { result.textContent = '오류가 발생했어요. 다시 시도해주세요.'; result.className = 'hp-result-inline wrong'; result.style.display = ''; }
        if (btn) btn.disabled = false;
      }
    }

    async function hpHintInquiry(cardIdx) {
      const nick = localStorage.getItem('beyondus_nickname') || '';
      try {
        const res = await fetch(API_BASE, {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain;charset=utf-8' },
          body: JSON.stringify(withSession({ action: 'postHpHint', nickname: nick, weekKey: _hpWeekKey, cardIndex: cardIdx }))
        });
        const data = await res.json();
        if (data.ok) {
          localStorage.setItem('beyondus_hp_hint_' + _hpWeekKey + '_' + cardIdx, data.id || 'submitted');
          renderHpCard(cardIdx);
        }
      } catch(e) {
        alert('요청 전송 중 오류가 발생했어요. 잠시 후 다시 시도해주세요.');
      }
    }

    /* ════ Firebase 단톡방 ════ */
    const FIREBASE_CONFIG = {
      apiKey:            "AIzaSyB2eRzNSxvUDnPMyMWh7dU3wi2guZ0Un80",
      authDomain:        "agc-treat.firebaseapp.com",
      projectId:         "agc-treat",
      storageBucket:     "agc-treat.firebasestorage.app",
      messagingSenderId: "616140830937",
      appId:             "1:616140830937:web:25c126b5bdcbeee58d26c8",
    };

    let _fbApp = null;
    let _db    = null;
    let _chatUnsub = null;
    let _chatReady = false;

    let _fbLoadPromise = null;
    function ensureFirebase() {
      if (_fbApp) return Promise.resolve(true);
      if (FIREBASE_CONFIG.apiKey === 'REPLACE_ME') return Promise.resolve(false);
      if (_fbLoadPromise) return _fbLoadPromise;
      _fbLoadPromise = new Promise(function(resolve) {
        function initApp() {
          try {
            _fbApp = firebase.initializeApp(FIREBASE_CONFIG);
            _db    = firebase.firestore();
            _chatReady = true;
            resolve(true);
          } catch(e) { console.error('Firebase init error', e); resolve(false); }
        }
        var s1 = document.createElement('script');
        s1.src = 'https://www.gstatic.com/firebasejs/9.23.0/firebase-app-compat.js';
        s1.onload = function() {
          var s2 = document.createElement('script');
          s2.src = 'https://www.gstatic.com/firebasejs/9.23.0/firebase-firestore-compat.js';
          s2.onload = initApp;
          s2.onerror = function() { _fbLoadPromise = null; resolve(false); };
          document.head.appendChild(s2);
        };
        s1.onerror = function() { _fbLoadPromise = null; resolve(false); };
        document.head.appendChild(s1);
      });
      return _fbLoadPromise;
    }

    function chatTimestamp(ts) {
      const d = ts ? ts.toDate() : new Date();
      const h = d.getHours(), m = String(d.getMinutes()).padStart(2,'0');
      return `${h}:${m}`;
    }
    function chatDateLabel(ts) {
      const d = ts ? ts.toDate() : new Date();
      return `${d.getFullYear()}년 ${d.getMonth()+1}월 ${d.getDate()}일`;
    }

    function buildBubble(doc) {
      const data = doc.data();
      const nick = localStorage.getItem('beyondus_nickname') || '';
      const isOwn = data.nickname === nick;
      const wrap = document.createElement('div');
      wrap.className = 'chat-bubble-wrap' + (isOwn ? ' own' : '');
      wrap.dataset.id = doc.id;
      if (!isOwn) {
        const meta = document.createElement('div');
        meta.className = 'chat-meta';
        if (data.parish) {
          const badge = document.createElement('span');
          badge.className = 'chat-parish';
          badge.textContent = data.parish;
          meta.appendChild(badge);
        }
        const name = document.createElement('span');
        name.textContent = data.nickname || '익명';
        meta.appendChild(name);
        wrap.appendChild(meta);
      }
      const bubble = document.createElement('div');
      bubble.className = 'chat-bubble ' + (isOwn ? 'own' : 'other');
      bubble.textContent = data.text;
      const time = document.createElement('div');
      time.className = 'chat-time';
      time.textContent = chatTimestamp(data.createdAt);
      wrap.appendChild(bubble);
      wrap.appendChild(time);
      return wrap;
    }

    function initChat() {
      if (_chatUnsub) return;
      const msgs   = document.getElementById('chatMessages');
      const input  = document.getElementById('chatInput');
      const sendBtn= document.getElementById('chatSendBtn');
      const notice = document.getElementById('chatNotice');

      notice.innerHTML = '<span>채팅방 로딩 중...</span>';
      ensureFirebase().then(function(ok) {
        if (!ok) {
          notice.innerHTML = '<span>채팅 서비스 준비 중이에요.<br>잠시 후 다시 시도해주세요.</span>';
          return;
        }
        _startChatSession(msgs, input, sendBtn, notice);
      });
    }

    function _startChatSession(msgs, input, sendBtn, notice) {
      const nick = localStorage.getItem('beyondus_nickname');
      if (!nick) {
        notice.innerHTML = '<span>로그인 후 채팅에 참여할 수 있어요.</span>';
        return;
      }

      notice.style.display = 'none';
      input.disabled  = false;
      sendBtn.disabled = false;

      let lastDateLabel = '';
      _chatUnsub = _db.collection('messages')
        .orderBy('createdAt', 'asc')
        .limitToLast(100)
        .onSnapshot(snapshot => {
          snapshot.docChanges().forEach(change => {
            if (change.type !== 'added') return;
            const doc  = change.doc;
            const data = doc.data();
            const label = chatDateLabel(data.createdAt);
            if (label !== lastDateLabel) {
              lastDateLabel = label;
              const div = document.createElement('div');
              div.className = 'chat-date-divider';
              div.innerHTML = `<span>${label}</span>`;
              msgs.appendChild(div);
            }
            msgs.appendChild(buildBubble(doc));
          });
          msgs.scrollTop = msgs.scrollHeight;
        }, err => {
          console.error('Chat listen error', err);
        });

      function doSend() {
        const text = input.value.trim();
        if (!text) return;
        sendBtn.disabled = true;
        input.value = '';
        const parish = localStorage.getItem('beyondus_parish') || '';
        _db.collection('messages').add({
          nickname:  nick,
          parish:    parish,
          text:      text,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        }).catch(e => {
          console.error('Send error', e);
        }).finally(() => { sendBtn.disabled = false; });
      }

      sendBtn.onclick = doSend;
      input.onkeydown = e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); doSend(); } };
    }

    function teardownChat() {
      if (_chatUnsub) { _chatUnsub(); _chatUnsub = null; }
      const msgs = document.getElementById('chatMessages');
      if (msgs) msgs.innerHTML = '<div class="chat-notice" id="chatNotice"><span>불러오는 중...</span></div>';
      const input   = document.getElementById('chatInput');
      const sendBtn = document.getElementById('chatSendBtn');
      if (input)   { input.disabled = true; input.value = ''; input.onkeydown = null; }
      if (sendBtn) { sendBtn.disabled = true; sendBtn.onclick = null; }
    }

    /* ════ PWA 설치 배너 ════ */
    (function initInstallBanner() {
      const isStandalone = window.matchMedia('(display-mode: standalone)').matches
                        || window.navigator.standalone === true;
      if (isStandalone) return;
      const installDismissKey = 'beyondus_install_dismissed_v2';
      if (localStorage.getItem(installDismissKey)) return;

      const banner  = document.getElementById('installBanner');
      const btn     = document.getElementById('installBannerBtn');
      const close   = document.getElementById('installBannerClose');
      const desc    = document.getElementById('installBannerDesc');
      const title   = banner.querySelector('strong');
      const env     = detectBrowser();
      const ua      = navigator.userAgent;
      const isKakao = /kakaotalk/i.test(ua);
      const isNaver = /naver/i.test(ua);
      const isLine  = /line/i.test(ua);
      const inAppBrowser = isKakao || isNaver || isLine;
      let deferredPrompt = null;

      function setBanner(copy) {
        title.textContent = copy.title;
        desc.textContent = copy.desc;
        btn.textContent = copy.btn;
        btn.style.display = copy.btn ? '' : 'none';
        banner.classList.remove('hidden');
      }

      function copyCurrentUrl() {
        const url = location.href;
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(url).catch(() => {});
        }
      }

      function getManualGuide() {
        if (env.os === 'ios') {
          if (env.browser === 'safari') {
            return 'Safari 아래 공유 버튼을 누른 뒤 "홈 화면에 추가"를 선택하고, 오른쪽 위 "추가"를 누르면 돼요.';
          }
          return 'iPhone은 Safari에서 여는 게 가장 안정적이에요. 링크를 복사한 뒤 Safari 주소창에 붙여넣고, 공유 버튼 → "홈 화면에 추가"를 눌러주세요.';
        }
        if (env.browser === 'samsung') {
          return '삼성인터넷 하단 메뉴(≡)에서 "현재 페이지 추가" 또는 "추가"를 누른 뒤 "홈 화면"을 선택해주세요.';
        }
        if (env.browser === 'chrome') {
          return 'Chrome 오른쪽 위 메뉴(⋮)에서 "앱 설치"가 보이면 누르고, 없으면 "홈 화면에 추가"를 선택해주세요.';
        }
        return '브라우저 메뉴에서 "앱 설치", "홈 화면에 추가", "현재 페이지 추가" 중 보이는 메뉴를 선택해주세요.';
      }

      function showManualGuide(copyFirst) {
        if (copyFirst) copyCurrentUrl();
        alert(getManualGuide() + (copyFirst ? '\n\n링크도 복사해두었어요.' : ''));
      }

      close.addEventListener('click', () => {
        banner.classList.add('hidden');
        localStorage.setItem(installDismissKey, '1');
      });

      if (inAppBrowser) {
        setBanner({
          title: '브라우저에서 열기',
          desc: '홈 화면 추가는 Safari, Chrome, 삼성인터넷에서 가장 안정적이에요.',
          btn: '링크 복사'
        });
        btn.addEventListener('click', () => showManualGuide(true));
        return;
      }

      if (env.os === 'ios') {
        setBanner({
          title: env.browser === 'safari' ? '홈 화면에 추가하기' : 'Safari로 열기',
          desc: env.browser === 'safari'
            ? '공유 버튼에서 "홈 화면에 추가"를 누르면 앱처럼 열 수 있어요.'
            : 'iPhone은 Safari에서 홈 화면 추가가 가장 안정적이에요.',
          btn: env.browser === 'safari' ? '방법 보기' : '링크 복사'
        });
        btn.addEventListener('click', () => showManualGuide(env.browser !== 'safari'));
        return;
      }

      if (env.browser === 'samsung') {
        setBanner({
          title: '홈 화면에 추가하기',
          desc: '삼성인터넷 메뉴에서 직접 추가하면 오류가 적어요.',
          btn: '방법 보기'
        });
        btn.addEventListener('click', () => showManualGuide(false));
        return;
      }

      if (env.os === 'android') {
        setBanner({
          title: '홈 화면에 추가하기',
          desc: '설치 버튼이 안 되면 브라우저 메뉴에서 직접 추가할 수 있어요.',
          btn: '방법 보기'
        });
      }

      window.addEventListener('beforeinstallprompt', e => {
        e.preventDefault();
        deferredPrompt = e;
        if (env.os === 'android' && env.browser === 'chrome') {
          setBanner({
            title: '앱처럼 설치하기',
            desc: '설치가 가능해요. 막히면 메뉴(⋮)에서 "홈 화면에 추가"를 눌러주세요.',
            btn: '설치'
          });
        }
      });

      btn.addEventListener('click', async () => {
        if (!deferredPrompt) {
          showManualGuide(false);
          return;
        }
        try {
          deferredPrompt.prompt();
          const { outcome } = await deferredPrompt.userChoice;
          deferredPrompt = null;
          if (outcome === 'accepted') {
            banner.classList.add('hidden');
            localStorage.setItem(installDismissKey, '1');
          } else {
            setBanner({
              title: '홈 화면에 추가하기',
              desc: '설치창이 닫혔어요. 메뉴에서 직접 추가하면 더 안정적이에요.',
              btn: '방법 보기'
            });
          }
        } catch(e) {
          deferredPrompt = null;
          setBanner({
            title: '홈 화면에 추가하기',
            desc: '설치 버튼 대신 브라우저 메뉴에서 직접 추가해주세요.',
            btn: '방법 보기'
          });
        }
      });

      window.addEventListener('appinstalled', () => {
        banner.classList.add('hidden');
        localStorage.setItem(installDismissKey, '1');
      });
    })();

    /* ════ 서비스 워커 등록 ════ */
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('./sw.js').catch(() => {});
    }

    /* ════ 초기화 ════ */
    document.addEventListener('contextmenu', function(e) {
      if (e.target.tagName === 'IMG') e.preventDefault();
    });
    updateMainInstallGuide();
    renderWeekCal();
    autoLogin();

    window.addEventListener('focus', () => {
      syncServerChanges(false).catch(() => {});
    });
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) syncServerChanges(false).catch(() => {});
    });
    function schedulePeriodicSync() {
      const delay = 55000 + Math.floor(Math.random() * 30000);
      setTimeout(() => {
        if (!document.hidden) syncServerChanges(false).catch(() => {});
        schedulePeriodicSync();
      }, delay);
    }
    schedulePeriodicSync();

    /* ════ 오프라인 감지 ════ */
    (function initOfflineBanner() {
      const banner = document.getElementById('offlineBanner');
      function show() { banner.classList.add('visible'); }
      function hide() { banner.classList.remove('visible'); }
      if (!navigator.onLine) show();
      window.addEventListener('offline', show);
      window.addEventListener('online',  hide);
    })();

    /* ════ Pull-to-Refresh ════ */
    (function initPTR() {
      const indicator = document.getElementById('ptrIndicator');
      const ptrText   = document.getElementById('ptrText');
      const THRESHOLD = 64;
      let startY = 0, currentY = 0, isPulling = false, isRefreshing = false;

      document.addEventListener('touchstart', e => {
        const appHidden = document.getElementById('appScreen').classList.contains('hidden');
        if (appHidden || window.scrollY > 0 || isRefreshing || _currentSection === 'chat' || _currentSection === 'prayer') return;
        startY = e.touches[0].clientY;
        isPulling = false;
      }, { passive: true });

      document.addEventListener('touchmove', e => {
        const appHidden = document.getElementById('appScreen').classList.contains('hidden');
        if (appHidden || isRefreshing || _currentSection === 'chat' || _currentSection === 'prayer') {
          isPulling = false;
          indicator.classList.remove('pulling','ready');
          indicator.style.height = '0';
          return;
        }
        const dy = e.touches[0].clientY - startY;
        if (dy <= 0 || window.scrollY > 0) { isPulling = false; return; }
        isPulling = true;
        currentY = Math.min(dy, THRESHOLD * 1.5);
        const pct = Math.min(currentY / THRESHOLD, 1);
        indicator.classList.toggle('pulling', pct > 0.05);
        indicator.classList.toggle('ready',   pct >= 1);
        indicator.style.height = (pct > 0.05 ? Math.round(pct * 52) : 0) + 'px';
        ptrText.textContent = pct >= 1 ? '놓으면 새로고침' : '당겨서 새로고침';
      }, { passive: true });

      document.addEventListener('touchend', () => {
        const appHidden = document.getElementById('appScreen').classList.contains('hidden');
        if (appHidden) {
          indicator.classList.remove('pulling','ready');
          indicator.style.height = '0';
          isPulling = false;
          return;
        }
        if (!isPulling || isRefreshing) { indicator.classList.remove('pulling','ready'); indicator.style.height = '0'; isPulling = false; return; }
        isPulling = false;
        const dy = currentY;
        if (dy < THRESHOLD) { indicator.classList.remove('pulling','ready'); indicator.style.height = '0'; return; }
        isRefreshing = true;
        indicator.classList.remove('pulling','ready');
        indicator.classList.add('refreshing');
        indicator.style.height = '52px';
        ptrText.textContent = '새로고침 중...';
        if (navigator.vibrate) navigator.vibrate(10);
        syncServerChanges(true).catch(() => {}).finally(() => {
          isRefreshing = false;
          indicator.classList.remove('refreshing');
          indicator.style.height = '0';
          ptrText.textContent = '당겨서 새로고침';
        });
      }, { passive: true });
    })();

    let _fitResizeTimer;
    window.addEventListener('resize', () => {
      clearTimeout(_fitResizeTimer);
      _fitResizeTimer = setTimeout(() => {
        const csOverlay = document.getElementById('csHpOverlay');
        const csTxt     = document.getElementById('csHpContent');
        if (csTxt && csOverlay && csTxt.textContent.trim()) fitHpText(csTxt, csOverlay);

        const hpContent = document.getElementById('hpContent');
        if (hpContent) {
          const overlayEl  = hpContent.querySelector('.hp-overlay');
          const overlayTxt = hpContent.querySelector('.hp-overlay-text');
          if (overlayTxt && overlayEl && overlayTxt.textContent.trim()) fitHpText(overlayTxt, overlayEl);
        }
      }, 150);
    });
