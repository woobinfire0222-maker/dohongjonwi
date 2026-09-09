(() => {
  const SUPABASE_URL = 'https://mflequqbncpzzwdmibty.supabase.co';
  const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1mbGVxdXFibmNwenp3ZG1pYnR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0MjAzNDYsImV4cCI6MjEwMzk5NjM0Nn0.aNXdE5V2nhu41toGN2k7sJymYTsjGUs-ZTRuhorCPdA';
  const VAPID_PUBLIC_KEY = 'BGcf3PbqW1E0HYiQ9VTOSuFaB7xuybNr25z0KOEb03HJ8-lcdisYhk65hNdAlkbvgB2daTcLkz_O17_sBHCe-eI';
  const DB = `${SUPABASE_URL}/rest/v1/push_subscriptions`;
  const AUTH_KEY = `sb-${new URL(SUPABASE_URL).hostname.split('.')[0]}-auth-token`;
  const KEY = 'dohongjonwi_push_prompt_dismissed';

  const b64ToUint8 = base64 => {
    const padding = '='.repeat((4 - base64.length % 4) % 4);
    const raw = atob((base64 + padding).replace(/-/g, '+').replace(/_/g, '/'));
    return Uint8Array.from([...raw].map(c => c.charCodeAt(0)));
  };
  const getSession = () => {
    try {
      const raw = localStorage.getItem(AUTH_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      return parsed?.access_token ? parsed : parsed?.currentSession || null;
    } catch (_) { return null; }
  };
  const rest = async (path, options = {}) => {
    const session = getSession();
    if (!session?.access_token) throw new Error('로그인이 필요합니다.');
    const headers = {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${session.access_token}`,
      'Content-Type': 'application/json',
      ...(options.headers || {})
    };
    const res = await fetch(`${DB}${path}`, { ...options, headers });
    if (!res.ok) throw new Error(await res.text());
    return res.status === 204 ? null : res.json();
  };
  const saveSubscription = async sub => {
    const session = getSession();
    if (!session?.user?.id) return;
    const json = sub.toJSON();
    await rest('', {
      method: 'POST',
      headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify({ user_id: session.user.id, endpoint: json.endpoint, p256dh: json.keys?.p256dh, auth: json.keys?.auth })
    });
  };
  const subscribe = async () => {
    if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) throw new Error('이 브라우저는 웹 푸시를 지원하지 않습니다.');
    if (Notification.permission === 'denied') throw new Error('브라우저 알림 권한이 차단되어 있습니다. 사이트 권한에서 허용해 주세요.');
    const permission = Notification.permission === 'granted' ? 'granted' : await Notification.requestPermission();
    if (permission !== 'granted') return false;
    const reg = await navigator.serviceWorker.register('/service-worker.js', { scope: '/' });
    let sub = await reg.pushManager.getSubscription();
    if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64ToUint8(VAPID_PUBLIC_KEY) });
    await saveSubscription(sub);
    localStorage.removeItem(KEY);
    document.getElementById('push-permission-banner')?.remove();
    return true;
  };
  const showPrompt = () => {
    if (localStorage.getItem(KEY) === '1' || Notification.permission === 'granted' || Notification.permission === 'denied') return;
    if (document.getElementById('push-permission-banner')) return;
    const el = document.createElement('div');
    el.id = 'push-permission-banner';
    el.innerHTML = `<div style="position:fixed;right:20px;bottom:20px;z-index:99999;width:min(380px,calc(100vw - 40px));padding:18px;border:1px solid rgba(128,128,128,.22);border-radius:16px;background:rgba(255,255,255,.96);box-shadow:0 12px 40px rgba(0,0,0,.16);font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif"><div style="font-size:16px;font-weight:800">🔔 알림을 켜시겠어요?</div><div style="margin-top:7px;font-size:13px;line-height:1.5;color:#666">새 메시지와 관리자 알림을 사이트를 닫은 뒤에도 받을 수 있습니다.</div><div style="display:flex;gap:8px;margin-top:14px"><button id="push-allow" style="flex:1;border:0;border-radius:10px;padding:10px;background:#111;color:#fff;font-weight:700;cursor:pointer">알림 허용</button><button id="push-later" style="border:0;border-radius:10px;padding:10px 13px;background:#eee;color:#333;font-weight:600;cursor:pointer">나중에</button></div><div id="push-error" style="margin-top:8px;font-size:11px;color:#d33"></div></div>`;
    document.body.appendChild(el);
    document.getElementById('push-later').onclick = () => { localStorage.setItem(KEY, '1'); el.remove(); };
    document.getElementById('push-allow').onclick = async () => { const b=document.getElementById('push-allow'); const er=document.getElementById('push-error'); b.disabled=true; b.textContent='설정 중...'; try { await subscribe(); } catch(e) { er.textContent=e?.message||'알림 설정에 실패했습니다.'; b.disabled=false; b.textContent='다시 시도'; } };
  };
  const init = () => {
    if (!location.protocol.startsWith('http')) return;
    if (!('serviceWorker' in navigator)) return;
    navigator.serviceWorker.register('/service-worker.js', { scope: '/' }).catch(() => {});
    setTimeout(showPrompt, 1200);
  };
  window.dohongPush = { subscribe };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
