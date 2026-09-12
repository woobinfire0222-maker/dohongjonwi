import webpush from 'npm:web-push@3.6.7';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY')!;
const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY')!;
const vapidSubject = Deno.env.get('VAPID_SUBJECT') || 'mailto:admin@example.com';

webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey);

Deno.serve(async req => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });
  try {
    const payload = await req.json();
    const record = payload?.record ?? payload?.data?.record ?? payload;
    const userId = record?.user_id;
    if (!userId) return Response.json({ ok: false, error: 'user_id is missing' }, { status: 400 });

    const headers = { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` };
    const res = await fetch(`${supabaseUrl}/rest/v1/push_subscriptions?user_id=eq.${encodeURIComponent(userId)}&select=id,endpoint,p256dh,auth`, { headers });
    if (!res.ok) throw new Error(await res.text());
    const subscriptions = await res.json();

    const body = JSON.stringify({
      title: record.title || '새 알림',
      body: record.content || '',
      url: '/app/notifications',
      tag: `notification-${record.id || Date.now()}`
    });

    const stale: string[] = [];
    for (const sub of subscriptions) {
      try {
        await webpush.sendNotification({ endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } }, body);
      } catch (err) {
        const status = (err as { statusCode?: number })?.statusCode;
        if (status === 404 || status === 410) stale.push(sub.id);
      }
    }

    for (const id of stale) {
      await fetch(`${supabaseUrl}/rest/v1/push_subscriptions?id=eq.${encodeURIComponent(id)}`, { method: 'DELETE', headers });
    }

    return Response.json({ ok: true, sent: subscriptions.length, removed: stale.length });
  } catch (error) {
    console.error(error);
    return Response.json({ ok: false, error: String(error) }, { status: 500 });
  }
});
