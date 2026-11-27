(() => {
  const $ = (id) => document.getElementById(id);
  const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'mars_pawnshop';
  let S = null;            // shop state from the server
  let imgBase = '';
  let selected = null;     // { mode: 'sell'|'buy'|'black'|'melt', item }
  let filter = 'All';
  let busy = false;

  const money = (n) => '$' + Math.floor(n).toLocaleString('en-US');
  const post = (name, data) => fetch(`https://${res}/${name}`, { method: 'POST', body: JSON.stringify(data || {}) })
    .then((r) => r.json()).catch(() => ({ ok: false, msg: 'Connection error' }));
  const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };
  const fmtTime = (s) => { s = Math.max(0, Math.floor(s)); const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
    return h > 0 ? `${h}h ${m}m` : `${m}:${String(x).padStart(2, '0')}`; };

  function toast(msg, ok) {
    const t = $('toast');
    t.textContent = msg; t.className = 'toast show ' + (ok ? 'ok' : 'err');
    clearTimeout(t._t); t._t = setTimeout(() => (t.className = 'toast'), 3200);
  }

  function img(name) {
    const i = el('img'); i.src = imgBase + name + '.png';
    i.onerror = () => { i.onerror = null; i.src = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><text x="32" y="44" font-size="34" text-anchor="middle">💎</text></svg>'; };
    return i;
  }

  // ── header ──
  function renderHeader() {
    $('shop-name').textContent = S.shop;
    $('cash').textContent = money(S.cash);
    const r = S.rep;
    $('rep-label').textContent = `Lv ${r.level} · ${r.label}`;
    $('rep-bonus').textContent = `+${Math.round(r.bonus * 100)}% prices`;
    if (r.nextXp) {
      const pct = ((r.xp - r.levelXp) / Math.max(1, r.nextXp - r.levelXp)) * 100;
      $('rep-fill').style.width = Math.max(2, Math.min(100, pct)) + '%';
      $('rep-next').textContent = `${money(r.xp).slice(1)} / ${money(r.nextXp).slice(1)} XP → ${r.nextLabel}`;
    } else {
      $('rep-fill').style.width = '100%';
      $('rep-next').textContent = 'Max reputation';
    }
    $('tab-black').textContent = S.black ? '✖ Back room' : '🔒 Back room';
  }

  // ── sell ──
  function renderSell() {
    $('hot-list').textContent = S.hot.join(' · ') || '—';
    const cats = ['All', ...new Set(S.sell.map((i) => i.category))];
    const f = $('filters'); f.innerHTML = '';
    cats.forEach((c) => { const b = el('button', 'chip' + (c === filter ? ' on' : ''), c); b.onclick = () => { filter = c; renderSell(); }; f.appendChild(b); });

    const g = $('sell-grid'); g.innerHTML = '';
    S.sell.filter((i) => filter === 'All' || i.category === filter).forEach((it) => {
      const c = el('div', 'card' + (it.count < 1 ? ' empty' : ''));
      if (it.hot) c.appendChild(el('div', 'badge hot', 'HOT'));
      if (it.annoyed) c.appendChild(el('div', 'badge angry', 'ANNOYED'));
      c.appendChild(img(it.name));
      c.appendChild(el('div', 'cat', it.category));
      c.appendChild(el('div', 'lbl', it.label));
      const m = el('div', 'meta');
      const p = el('div', 'price', money(it.price));
      p.appendChild(el('span', 'trend ' + it.trend, it.trend === 'up' ? '▲' : it.trend === 'soft' ? '▬' : '▼'));
      m.appendChild(p); m.appendChild(el('div', 'own', it.count > 0 ? `you have ${it.count}` : 'none'));
      c.appendChild(m);
      if (it.count > 0) c.onclick = () => openDrawer('sell', it);
      g.appendChild(c);
    });
  }

  // ── buy-back ──
  function renderBuy() {
    const g = $('buy-grid'); g.innerHTML = '';
    if (!S.stock.length) { g.appendChild(el('div', 'empty-msg', 'Nothing on the shelves right now.')); return; }
    S.stock.forEach((it) => {
      const c = el('div', 'card');
      c.appendChild(img(it.name));
      c.appendChild(el('div', 'lbl', it.label));
      const m = el('div', 'meta'); m.appendChild(el('div', 'price', money(it.price))); m.appendChild(el('div', 'own', `${it.count} in stock`));
      c.appendChild(m);
      c.onclick = () => openDrawer('buy', it);
      g.appendChild(c);
    });
  }

  // ── smelter ──
  function renderSmelter() {
    const j = $('smelt-jobs'); j.innerHTML = '';
    if (!S.smelter.length) j.appendChild(el('div', 'empty-msg', 'The furnace is empty.'));
    S.smelter.forEach((job) => {
      const d = el('div', 'job' + (job.left <= 0 ? ' ready' : ''));
      d.appendChild(el('div', '', `${job.count} × ${job.label}`));
      const l = el('div', 'left', job.left <= 0 ? 'READY' : fmtTime(job.left)); l.dataset.left = job.left;
      d.appendChild(l); j.appendChild(d);
    });
    $('collect').disabled = !S.smelter.some((x) => x.left <= 0);

    const g = $('melt-grid'); g.innerHTML = '';
    const meltable = S.sell.filter((i) => i.melt && i.count > 0);
    if (!meltable.length) g.appendChild(el('div', 'empty-msg', 'You have no jewelry to melt.'));
    meltable.forEach((it) => {
      const c = el('div', 'card');
      c.appendChild(img(it.name));
      c.appendChild(el('div', 'lbl', it.label));
      c.appendChild(el('div', 'own', `you have ${it.count}`));
      c.onclick = () => openDrawer('melt', it);
      g.appendChild(c);
    });
  }

  // ── ledger ──
  function renderHistory() {
    const t = $('ledger'); t.innerHTML = '';
    if (!S.history.length) { const tr = el('tr'); const td = el('td', 'empty-msg', 'No sales yet.'); td.colSpan = 7; tr.appendChild(td); t.appendChild(tr); return; }
    S.history.forEach((h) => {
      const tr = el('tr');
      [h.no, h.date, h.item, h.count, money(h.unit)].forEach((v) => tr.appendChild(el('td', '', v)));
      tr.appendChild(el('td', 'money', money(h.total)));
      const tags = el('td');
      if (h.hot) tags.appendChild(el('span', 'pill h', 'HOT'));
      if (h.haggled) tags.appendChild(el('span', 'pill g', 'HAGGLED'));
      tr.appendChild(tags); t.appendChild(tr);
    });
  }

  // ── black market ──
  function renderBlack() {
    $('black-locked').classList.toggle('hidden', !!S.black);
    $('black-open').classList.toggle('hidden', !S.black);
    $('black-why').textContent = `Reach reputation level ${S.rep.blackAt} (${S.rep.blackLabel}) and the owner might show you what is behind the curtain.`;
    if (!S.black) return;
    const g = $('black-grid'); g.innerHTML = '';
    S.black.forEach((it) => {
      const c = el('div', 'card');
      c.appendChild(img(it.name));
      c.appendChild(el('div', 'lbl', it.label));
      const m = el('div', 'meta'); m.appendChild(el('div', 'price', money(it.price))); c.appendChild(m);
      c.onclick = () => openDrawer('black', it);
      g.appendChild(c);
    });
  }

  function renderAll() { renderHeader(); renderSell(); renderBuy(); renderSmelter(); renderHistory(); renderBlack(); }

  // ── drawer ──
  function openDrawer(mode, item) {
    selected = { mode, item };
    const d = $('drawer');
    const di = $('d-img');
    di.onerror = () => { di.onerror = null; di.src = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><text x="32" y="44" font-size="34" text-anchor="middle">💎</text></svg>'; };
    di.src = imgBase + item.name + '.png';
    $('d-cat').textContent = { sell: item.category, buy: 'Buy-back', black: 'Back room', melt: 'Smelter' }[mode];
    $('d-name').textContent = item.label;
    const max = mode === 'sell' || mode === 'melt' ? item.count : mode === 'buy' ? item.count : 10;
    const q = $('q'); q.max = Math.max(1, max); q.value = 1;
    const unit = mode === 'melt' ? 0 : item.price;
    $('d-unit').textContent = mode === 'melt' ? '—' : money(unit);

    const a = $('d-actions'); a.innerHTML = '';
    if (mode === 'sell') {
      const sell = el('button', 'btn gold wide', 'SELL'); sell.onclick = () => act('sell', 0); a.appendChild(sell);
      const h = el('div', 'haggle');
      S.haggle.list.forEach((x, i) => {
        const b = el('button', 'btn small', 'Ask ' + x.label);
        const chance = Math.min(100, x.chance + (S.rep.level - 1) * (S.haggle.repBonus || 0));
        b.appendChild(el('small', '', `${chance}% chance`));
        b.onclick = () => act('sell', i + 1);
        h.appendChild(b);
      });
      a.appendChild(h);
      $('d-note').textContent = item.annoyed
        ? 'He is annoyed with you about this item — offers are lower for a few minutes.'
        : 'Asking for more can pay off, but if he refuses he gets annoyed and lowers his offers on this item for a few minutes. Selling many at once lowers the price per unit.';
    } else if (mode === 'buy') {
      const b = el('button', 'btn gold wide', 'BUY'); b.onclick = () => act('buy'); a.appendChild(b);
      $('d-note').textContent = 'Second-hand goods, sold as seen.';
    } else if (mode === 'black') {
      const b = el('button', 'btn red wide', 'BUY'); b.onclick = () => act('buyBlack'); a.appendChild(b);
      $('d-note').textContent = 'No receipts. If anyone asks, you found it.';
    } else {
      const b = el('button', 'btn gold wide', 'PUT IN FURNACE'); b.onclick = () => act('melt'); a.appendChild(b);
      $('d-note').textContent = 'Melting takes a while. Come back and collect your gold bars and diamonds from the Smelter tab.';
    }
    updateTotal();
    d.classList.add('open');
  }

  function updateTotal() {
    if (!selected) return;
    const q = +$('q').value;
    $('q-val').textContent = q;
    $('d-total').textContent = selected.mode === 'melt' ? `${q} unit(s)` : money(selected.item.price * q);
  }

  function closeDrawer() { $('drawer').classList.remove('open'); selected = null; }

  async function act(kind, haggle) {
    if (!selected || busy) return;
    busy = true;
    const r = await post(kind, { name: selected.item.name, count: +$('q').value, haggle: haggle || 0 });
    busy = false;
    if (r.state) { S = r.state; renderAll(); }
    if (r.ok && r.ticket) { closeDrawer(); showTicket(r.ticket); }
    else { toast(r.msg || (r.ok ? 'Done.' : 'Failed.'), !!r.ok); if (r.ok) closeDrawer(); }
  }

  function showTicket(t) {
    $('t-no').textContent = t.no; $('t-date').textContent = t.date;
    $('t-item').textContent = t.item; $('t-qty').textContent = '× ' + t.count;
    $('t-unit').textContent = money(t.unit); $('t-total').textContent = money(t.total);
    $('t-tags').textContent = [t.hot ? '★ wanted item bonus' : '', t.haggled ? '★ haggled price' : ''].filter(Boolean).join('   ');
    $('ticket').classList.remove('hidden');
  }

  // ── events ──
  document.querySelectorAll('nav button').forEach((b) => b.onclick = () => {
    document.querySelectorAll('nav button').forEach((x) => x.classList.remove('active'));
    document.querySelectorAll('.tab').forEach((x) => x.classList.remove('active'));
    b.classList.add('active'); $(b.dataset.tab).classList.add('active'); closeDrawer();
  });
  $('q').oninput = updateTotal;
  $('q-minus').onclick = () => { $('q').value = Math.max(1, +$('q').value - 1); updateTotal(); };
  $('q-plus').onclick = () => { $('q').value = Math.min(+$('q').max, +$('q').value + 1); updateTotal(); };
  $('drawer-close').onclick = closeDrawer;
  $('t-ok').onclick = () => $('ticket').classList.add('hidden');
  $('collect').onclick = async () => { const r = await post('collect', {}); if (r.state) { S = r.state; renderAll(); } toast(r.msg, r.ok); };
  const close = () => { $('app').classList.add('hidden'); closeDrawer(); post('close'); };
  $('close').onclick = close;
  document.addEventListener('keyup', (e) => { if (e.key === 'Escape' && !$('app').classList.contains('hidden')) close(); });

  // countdowns
  setInterval(() => {
    if (!S) return;
    S.hotLeft = Math.max(0, S.hotLeft - 1);
    $('hot-left').textContent = fmtTime(S.hotLeft);
    document.querySelectorAll('.job .left').forEach((l) => {
      let v = +l.dataset.left - 1; l.dataset.left = v;
      if (v <= 0) { l.textContent = 'READY'; l.parentElement.classList.add('ready'); $('collect').disabled = false; }
      else l.textContent = fmtTime(v);
    });
  }, 1000);

  window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.type === 'open') {
      S = d.state; imgBase = d.images || '';
      filter = 'All'; renderAll(); $('app').classList.remove('hidden');
    } else if (d.type === 'close') {
      $('app').classList.add('hidden'); closeDrawer();
    }
  });
})();
