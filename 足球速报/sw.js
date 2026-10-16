var CACHE = 'football-report-v9';
var ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './report-data.js',
  './vendor/marked.min.js',
  './css/smart.css',
  './js/fb-smart.js',
  './icon-192.png',
  './icon-512.png',
  './icon-180.png'
];

self.addEventListener('install', function (e) {
  e.waitUntil(
    caches.open(CACHE)
      .then(function (c) { return c.addAll(ASSETS); })
      .then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener('activate', function (e) {
  e.waitUntil(
    caches.keys()
      .then(function (ks) {
        return Promise.all(ks.map(function (k) { return k === CACHE ? null : caches.delete(k); }));
      })
      .then(function () { return self.clients.claim(); })
  );
});

/* 页面 + 日报数据：网络优先。
   原因：日报每天 07:00 更新，缓存优先会导致"第一次打开还是昨天的"，
   要刷第二次才看到新的。断网时才回退到缓存。 */
function freshFirst(url){
  var p = url.pathname;
  return p === '/' || p.indexOf('.html') >= 0 || p.indexOf('data.js') >= 0
      || p.indexOf('/js/') >= 0 || p.indexOf('/css/') >= 0;
}

self.addEventListener('fetch', function (e) {
  if (e.request.method !== 'GET') return;
  var url;
  try { url = new URL(e.request.url); } catch (err) { return; }
  if (url.origin !== self.location.origin) return;

  if (freshFirst(url)) {
    e.respondWith(
      fetch(e.request).then(function (res) {
        if (res && res.status === 200) {
          var copy = res.clone();
          caches.open(CACHE).then(function (c) { c.put(e.request, copy); });
        }
        return res;
      }).catch(function () {
        return caches.match(e.request, { ignoreSearch: true });
      })
    );
    return;
  }

  /* 图标 / vendor 等不变资源：缓存优先，加载更快 */
  e.respondWith(
    caches.match(e.request, { ignoreSearch: true }).then(function (cached) {
      return cached || fetch(e.request).then(function (res) {
        if (res && res.status === 200) {
          var copy = res.clone();
          caches.open(CACHE).then(function (c) { c.put(e.request, copy); });
        }
        return res;
      });
    })
  );
});
