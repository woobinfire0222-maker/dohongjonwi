self.addEventListener('push', event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (_) { data = { title: '새 알림', body: event.data ? event.data.text() : '' }; }
  const title = data.title || '새 알림';
  const options = {
    body: data.body || data.content || '',
    icon: data.icon || '/favicon.ico',
    badge: data.badge || '/favicon.ico',
    data: { url: data.url || '/app/notifications' },
    tag: data.tag || 'dohongjonwi-notification',
    renotify: true
  };
  event.waitUntil(self.registration.showNotification(title, options));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const url = event.notification?.data?.url || '/app/notifications';
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    for (const client of list) {
      if ('focus' in client) {
        try { client.navigate(url); } catch (_) {}
        return client.focus();
      }
    }
    return clients.openWindow(url);
  }));
});
