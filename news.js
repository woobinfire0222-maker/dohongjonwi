(() => {
  const API = 'https://mflequqbncpzzwdmibty.supabase.co/rest/v1';
  const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1mbGVxdXFibmNwenp3ZG1pYnR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0MjAzNDYsImV4cCI6MjEwMzk5NjM0Nn0.aNXdE5V2nhu41toGN2k7sJymYTsjGUs-ZTRuhorCPdA';
  const table = 'news_articles';
  let lastPath = location.pathname;
  let newsCache = [];
  let editingId = null;

  const esc = (v='') => String(v).replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const session = () => {
    try {
      const key = Object.keys(localStorage).find(k => /^sb-[a-z0-9]+-auth-token$/.test(k));
      if (!key) return null;
      const raw = JSON.parse(localStorage.getItem(key) || 'null');
      return raw?.access_token || raw?.currentSession?.access_token || null;
    } catch { return null; }
  };
  const headers = () => ({ apikey: ANON, Authorization: `Bearer ${session() || ANON}`, 'Content-Type':'application/json', Prefer:'return=representation' });
  async function api(path, opts={}) {
    const r = await fetch(`${API}/${path}`, { ...opts, headers: { ...headers(), ...(opts.headers||{}) }});
    const text = await r.text();
    let data = null; try { data = text ? JSON.parse(text) : null; } catch { data = text; }
    if (!r.ok) throw new Error(data?.message || data?.hint || data?.details || data?.error || `요청 실패 (${r.status})`);
    return data;
  }
  async function isAdmin() {
    const token = session(); if (!token) return false;
    try {
      const u = JSON.parse(atob(token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));
      if (!u?.sub) return false;
      const p = await api(`profiles?id=eq.${encodeURIComponent(u.sub)}&select=role&limit=1`);
      return p?.[0]?.role === 'admin';
    } catch { return false; }
  }
  const fmt = d => new Intl.DateTimeFormat('ko-KR',{year:'numeric',month:'long',day:'numeric',hour:'2-digit',minute:'2-digit'}).format(new Date(d));

  function injectStyles(){
    if(document.getElementById('dh-news-style')) return;
    const s=document.createElement('style'); s.id='dh-news-style'; s.textContent=`
      .dh-news-link{display:flex;align-items:center;gap:10px;width:100%;border:0;background:transparent;color:inherit;padding:10px 12px;border-radius:10px;font:inherit;font-weight:600;cursor:pointer;text-align:left}
      .dh-news-link:hover{background:rgba(37,99,235,.08)} .dh-news-link .dh-news-ico{font-size:18px;line-height:1}
      .dh-news-overlay{position:fixed;inset:0;z-index:9999;background:rgba(15,23,42,.48);backdrop-filter:blur(8px);display:flex;align-items:flex-start;justify-content:center;padding:30px 18px;overflow:auto}
      .dh-news-shell{width:min(1050px,100%);min-height:calc(100dvh - 60px);background:#f8fafc;border:1px solid rgba(148,163,184,.28);border-radius:24px;box-shadow:0 30px 90px rgba(15,23,42,.25);overflow:hidden}
      .dh-news-head{padding:24px 28px;background:linear-gradient(135deg,#fff,#eff6ff);border-bottom:1px solid #e2e8f0;display:flex;justify-content:space-between;gap:20px;align-items:center}
      .dh-news-title{font-size:25px;font-weight:900;letter-spacing:-.04em}.dh-news-sub{margin-top:5px;color:#64748b;font-size:13px}
      .dh-news-close{border:0;background:#fff;border:1px solid #dbe3ef;border-radius:12px;width:42px;height:42px;font-size:20px;cursor:pointer}
      .dh-news-grid{display:grid;grid-template-columns:1fr 1fr;gap:18px;padding:22px}
      .dh-news-card{background:#fff;border:1px solid #e2e8f0;border-radius:18px;padding:20px;box-shadow:0 8px 25px rgba(15,23,42,.05);cursor:pointer;transition:.18s}.dh-news-card:hover{transform:translateY(-2px);box-shadow:0 14px 30px rgba(15,23,42,.08)}
      .dh-news-card:first-child{grid-column:1/-1;background:linear-gradient(135deg,#eff6ff,#fff)}
      .dh-news-meta{display:flex;gap:8px;align-items:center;color:#64748b;font-size:12px}.dh-news-badge{padding:4px 8px;border-radius:999px;background:#dbeafe;color:#1d4ed8;font-weight:800}.dh-news-card h3{margin:10px 0 7px;font-size:18px;letter-spacing:-.025em}.dh-news-card p{margin:0;color:#64748b;line-height:1.65;font-size:13px;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
      .dh-news-empty{grid-column:1/-1;padding:60px 20px;text-align:center;color:#64748b;background:#fff;border:1px dashed #cbd5e1;border-radius:18px}
      .dh-news-admin{margin-top:24px;border:1px solid #dbe3ef;border-radius:18px;background:#fff;padding:20px}.dh-news-admin h3{margin:0 0 5px;font-size:18px}.dh-news-admin p{margin:0 0 18px;color:#64748b;font-size:12px}
      .dh-news-form{display:grid;gap:10px}.dh-news-form input,.dh-news-form textarea,.dh-news-form select{width:100%;box-sizing:border-box;border:1px solid #d7e0ec;border-radius:10px;padding:11px 12px;font:inherit;background:#fff}.dh-news-form textarea{min-height:150px;resize:vertical}.dh-news-form .row{display:grid;grid-template-columns:1fr 1fr;gap:10px}.dh-news-actions{display:flex;justify-content:flex-end;gap:8px}.dh-news-btn{border:0;border-radius:10px;padding:10px 14px;font-weight:800;cursor:pointer;background:#1769c2;color:#fff}.dh-news-btn.secondary{background:#eef2f7;color:#334155}.dh-news-admin-list{margin-top:18px;border-top:1px solid #e2e8f0}.dh-news-admin-row{display:flex;align-items:center;gap:10px;padding:12px 0;border-bottom:1px solid #edf2f7}.dh-news-admin-row .grow{flex:1;min-width:0}.dh-news-admin-row .grow strong{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.dh-news-admin-row small{color:#64748b}.dh-news-mini{border:1px solid #dbe3ef;background:#fff;border-radius:8px;padding:6px 9px;cursor:pointer}.dh-news-toast{position:fixed;left:50%;bottom:25px;transform:translateX(-50%);z-index:10001;background:#0f172a;color:#fff;padding:11px 16px;border-radius:999px;font-size:13px;box-shadow:0 10px 30px rgba(0,0,0,.2)}
      @media(max-width:700px){.dh-news-overlay{padding:0}.dh-news-shell{min-height:100dvh;border-radius:0}.dh-news-head{padding:18px}.dh-news-grid{grid-template-columns:1fr;padding:14px}.dh-news-card:first-child{grid-column:auto}.dh-news-admin .row{grid-template-columns:1fr}.dh-news-admin{margin:14px}.dh-news-title{font-size:21px}}
    `; document.head.appendChild(s);
  }
  function toast(msg){const old=document.querySelector('.dh-news-toast');old?.remove();const d=document.createElement('div');d.className='dh-news-toast';d.textContent=msg;document.body.appendChild(d);setTimeout(()=>d.remove(),2400)}

  async function loadNews(all=false){
    const q = all ? `select=*&order=published_at.desc` : `published=eq.true&select=id,title,summary,content,category,emoji,published,published_at,created_at&order=published_at.desc`;
    newsCache = await api(`${table}?${q}`) || []; return newsCache;
  }
  function close(){document.querySelector('.dh-news-overlay')?.remove(); if(location.hash==='#news') history.pushState({},'',location.pathname);}
  function openArticle(n){
    const ov=document.querySelector('.dh-news-overlay'); if(!ov)return;
    const body=ov.querySelector('.dh-news-shell'); body.innerHTML=`<div class="dh-news-head"><div><div class="dh-news-meta"><span class="dh-news-badge">${esc(n.emoji)} ${esc(n.category)}</span><span>${fmt(n.published_at)}</span></div><div class="dh-news-title" style="margin-top:8px">${esc(n.title)}</div></div><button class="dh-news-close">×</button></div><article style="padding:28px;max-width:820px;margin:auto;background:#fff;min-height:500px"><p style="font-weight:800;color:#475569;line-height:1.7">${esc(n.summary)}</p><div style="margin-top:25px;line-height:2;color:#334155;white-space:pre-wrap">${esc(n.content)}</div></article>`;
    body.querySelector('.dh-news-close').onclick=close;
  }
  async function renderPublic(){
    injectStyles();
    const ov=document.createElement('div');ov.className='dh-news-overlay';ov.innerHTML=`<section class="dh-news-shell"><div class="dh-news-head"><div><div class="dh-news-meta"><span class="dh-news-badge">📰 NEWS ROOM</span><span>돼홍존위 소식</span></div><div class="dh-news-title">뉴스룸</div><div class="dh-news-sub">운영실에서 전하는 새로운 소식과 업데이트</div></div><button class="dh-news-close">×</button></div><div class="dh-news-grid"><div class="dh-news-empty">뉴스를 불러오는 중...</div></div></section>`;
    document.body.appendChild(ov); ov.querySelector('.dh-news-close').onclick=close;
    try{const items=await loadNews(false);const grid=ov.querySelector('.dh-news-grid');grid.innerHTML=items.length?items.map(n=>`<article class="dh-news-card" data-id="${n.id}"><div class="dh-news-meta"><span class="dh-news-badge">${esc(n.emoji)} ${esc(n.category)}</span><span>${fmt(n.published_at)}</span></div><h3>${esc(n.title)}</h3><p>${esc(n.summary||n.content)}</p></article>`).join(''):`<div class="dh-news-empty">📰 아직 등록된 뉴스가 없습니다.</div>`;grid.querySelectorAll('.dh-news-card').forEach(c=>c.onclick=()=>openArticle(items.find(n=>n.id===c.dataset.id)));}catch(e){ov.querySelector('.dh-news-grid').innerHTML=`<div class="dh-news-empty">뉴스를 불러오지 못했습니다.<br><small>${esc(e.message)}</small></div>`}
  }

  function addSidebarLink(){
    if(document.querySelector('[data-dh-news-link]')) return;
    const candidates=[...document.querySelectorAll('a,button')].filter(x=>['공지사항','단체 채팅','진급 요청','부서 요청','투표'].includes(x.textContent?.trim()));
    const anchor=candidates.find(x=>x.textContent?.trim()==='공지사항') || candidates[0];
    if(!anchor?.parentElement) return;
    const wrap=anchor.parentElement.cloneNode(false); const btn=document.createElement('button');btn.className=anchor.className+' dh-news-link';btn.setAttribute('data-dh-news-link','1');btn.innerHTML='<span class="dh-news-ico">📰</span><span>뉴스룸</span>';btn.onclick=()=>{history.pushState({},'',location.pathname+'#news');renderPublic()};wrap.appendChild(btn);anchor.parentElement.after(wrap);
  }

  function adminPanel(){
    if(document.querySelector('[data-dh-news-admin]')) return;
    const headings=[...document.querySelectorAll('h2,h3')];
    const target=headings.find(h=>h.textContent?.trim()==='공지사항 관리')?.closest('div.rounded-xl') || headings.find(h=>h.textContent?.trim()==='공지사항 관리')?.parentElement?.parentElement;
    const host=target?.parentElement || document.querySelector('main'); if(!host) return;
    const box=document.createElement('section');box.setAttribute('data-dh-news-admin','1');box.className='dh-news-admin';box.innerHTML=`<h3>📰 뉴스룸 관리</h3><p>회원에게 공개할 뉴스와 업데이트를 작성합니다. 등록된 뉴스는 뉴스룸에서 확인할 수 있습니다.</p><form class="dh-news-form"><div class="row"><input name="title" placeholder="뉴스 제목" required><select name="category"><option>일반</option><option>업데이트</option><option>이벤트</option><option>안내</option><option>속보</option></select></div><div class="row"><input name="emoji" value="📰" maxlength="4" placeholder="대표 이모지"><select name="published"><option value="true">즉시 공개</option><option value="false">임시 저장</option></select></div><input name="summary" placeholder="한 줄 요약"><textarea name="content" placeholder="뉴스 내용을 작성하세요" required></textarea><div class="dh-news-actions"><button type="reset" class="dh-news-btn secondary">초기화</button><button class="dh-news-btn">뉴스 등록</button></div></form><div class="dh-news-admin-list"><div style="padding:15px 0;color:#64748b;font-size:12px">등록된 뉴스 불러오는 중...</div></div>`;
    host.appendChild(box);
    const form=box.querySelector('form'); form.onsubmit=async e=>{e.preventDefault();const f=new FormData(form);try{const payload={title:f.get('title'),summary:f.get('summary')||'',content:f.get('content'),category:f.get('category'),emoji:f.get('emoji')||'📰',published:f.get('published')==='true',created_by:JSON.parse(atob(session().split('.')[1])).sub};await api(table,{method:'POST',body:JSON.stringify(payload)});form.reset();form.querySelector('[name=emoji]').value='📰';toast('뉴스를 등록했습니다.');await refreshAdminList(box)}catch(err){toast(`등록 실패: ${err.message}`)}};
    refreshAdminList(box);
  }
  async function refreshAdminList(box){try{const items=await loadNews(true);box.querySelector('.dh-news-admin-list').innerHTML=items.length?items.map(n=>`<div class="dh-news-admin-row"><div class="grow"><strong>${esc(n.emoji)} ${esc(n.title)}</strong><small>${esc(n.category)} · ${n.published?'공개':'임시 저장'} · ${fmt(n.published_at)}</small></div><button class="dh-news-mini" data-edit="${n.id}">수정</button><button class="dh-news-mini" data-del="${n.id}">삭제</button></div>`).join(''):`<div style="padding:15px 0;color:#64748b;font-size:12px">등록된 뉴스가 없습니다.</div>`;box.querySelectorAll('[data-del]').forEach(b=>b.onclick=async()=>{if(!confirm('이 뉴스를 삭제할까요?'))return;try{await api(`${table}?id=eq.${b.dataset.del}`,{method:'DELETE'});toast('삭제했습니다.');refreshAdminList(box)}catch(e){toast(`삭제 실패: ${e.message}`)}});box.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>editNews(box,items.find(n=>n.id===b.dataset.edit)));}catch(e){box.querySelector('.dh-news-admin-list').textContent=`불러오지 못했습니다: ${e.message}`}}
  function editNews(box,n){const f=box.querySelector('form');Object.entries({title:n.title,category:n.category,emoji:n.emoji,summary:n.summary,content:n.content,published:String(n.published)}).forEach(([k,v])=>{const el=f.elements[k];if(el)el.value=v});editingId=n.id;f.querySelector('.dh-news-btn:not(.secondary)').textContent='뉴스 수정';f.onsubmit=async e=>{e.preventDefault();const fd=new FormData(f);try{await api(`${table}?id=eq.${editingId}`,{method:'PATCH',body:JSON.stringify({title:fd.get('title'),summary:fd.get('summary')||'',content:fd.get('content'),category:fd.get('category'),emoji:fd.get('emoji')||'📰',published:fd.get('published')==='true'})});editingId=null;f.reset();f.elements.emoji.value='📰';f.querySelector('.dh-news-btn:not(.secondary)').textContent='뉴스 등록';toast('뉴스를 수정했습니다.');refreshAdminList(box)}catch(err){toast(`수정 실패: ${err.message}`)}}}

  async function tick(){
    injectStyles();
    if(location.pathname!==lastPath){lastPath=location.pathname;document.querySelector('.dh-news-overlay')?.remove()}

    // 이 사이트는 GitHub Pages SPA라서 /admin, /app 같은 별도 경로를 사용하지 않습니다.
    // 실제 화면이 렌더링된 뒤 DOM을 기준으로 뉴스 메뉴/관리 패널을 붙입니다.
    addSidebarLink();
    if(await isAdmin()) adminPanel();

    if(location.hash==='#news'&&!document.querySelector('.dh-news-overlay')) renderPublic();
  }
  window.addEventListener('popstate',tick); window.addEventListener('hashchange',tick);
  const mo=new MutationObserver(()=>{clearTimeout(window.__dhNewsT);window.__dhNewsT=setTimeout(tick,250)}); mo.observe(document.body,{childList:true,subtree:true});
  setTimeout(tick,500); setInterval(tick,2500);
})();
