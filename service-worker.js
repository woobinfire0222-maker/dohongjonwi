self.addEventListener('push', event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (_) { data = { title: '새 알림', body: event.data ? event.data.text() : '' }; }
  const title = data.title || '새 알림';
  const scopePath = new URL('./', self.registration.scope).pathname;
  const normalizeUrl = value => {
    if (!value) return scopePath + 'app/notifications';
    if (/^https?:\/\//i.test(value)) return value;
    if (value.startsWith(scopePath)) return value;
    if (value.startsWith('/app/')) return scopePath + value.slice(5);
    if (value.startsWith('/')) return value;
    return scopePath + value.replace(/^\/+/, '');
  };
  event.waitUntil(self.registration.showNotification(title, {
    body: data.body || data.content || '',
    data: { url: normalizeUrl(data.url) },
    tag: data.tag || 'dohongjonwi-notification',
    renotify: true
  }));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const fallback = new URL('./app/notifications', self.registration.scope).href;
  const url = event.notification?.data?.url || fallback;
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    for (const client of list) {
      if ('focus' in client) { try { client.navigate(url); } catch (_) {} return client.focus(); }
    }
    return clients.openWindow(url);
  }));
});
