(() => {
  const chat = document.getElementById('chat');
  const messages = document.getElementById('messages');
  const wrap = document.getElementById('input-wrap');
  const input = document.getElementById('input');
  const sugBox = document.getElementById('suggestions');
  const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'mars_chat';

  let fadeMs = 10000, maxMessages = 100;
  const suggestions = new Map();
  const history = [];
  let historyIndex = -1;

  const post = (name, data) =>
    fetch(`https://${resource}/${name}`, { method: 'POST', body: JSON.stringify(data || {}) }).catch(() => {});

  // strip any HTML coming from other resources' templates; we only render text
  const plain = (v) => String(v ?? '').replace(/<[^>]*>/g, '').replace(/\^[0-9]/g, '');

  function rgb(c) {
    if (Array.isArray(c) && c.length >= 3) return `rgb(${c[0]},${c[1]},${c[2]})`;
    return '#c4b5fd';
  }

  function addMessage(m) {
    const args = Array.isArray(m.args) ? m.args : [];
    let author = '', text = '';
    if (m.template) {
      text = plain(String(m.template).replace(/\{(\d+)\}/g, (_, i) => args[i] ?? ''));
    } else if (args.length >= 2) {
      author = plain(args[0]); text = plain(args.slice(1).join(' '));
    } else {
      text = plain(args[0] ?? m.text ?? '');
    }
    if (!author && !text) return;

    const div = document.createElement('div');
    div.className = 'msg';
    div.dir = 'auto';
    if (author) {
      const a = document.createElement('span');
      a.className = 'author';
      a.style.color = rgb(m.color);
      a.textContent = author + ':';
      div.appendChild(a);
    }
    const t = document.createElement('span');
    t.textContent = text;
    div.appendChild(t);
    messages.appendChild(div);

    while (messages.children.length > maxMessages) messages.removeChild(messages.firstChild);
    messages.scrollTop = messages.scrollHeight;
    setTimeout(() => div.classList.add('faded'), fadeMs);
  }

  function renderSuggestions() {
    sugBox.innerHTML = '';
    const v = input.value;
    if (!v.startsWith('/')) return;
    const word = v.split(' ')[0].toLowerCase();
    let shown = 0;
    for (const [name, help] of suggestions) {
      if (!name.toLowerCase().startsWith(word) || shown >= 6) continue;
      const li = document.createElement('li');
      const b = document.createElement('b');
      b.textContent = name;
      li.appendChild(b);
      li.appendChild(document.createTextNode(help || ''));
      sugBox.appendChild(li);
      shown++;
    }
  }

  function openChat() {
    chat.classList.add('open');
    wrap.classList.remove('hidden');
    input.value = '';
    historyIndex = -1;
    renderSuggestions();
    setTimeout(() => input.focus(), 10);
    messages.scrollTop = messages.scrollHeight;
  }

  function closeChat() {
    chat.classList.remove('open');
    wrap.classList.add('hidden');
    input.blur();
    sugBox.innerHTML = '';
  }

  input.addEventListener('input', renderSuggestions);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      const msg = input.value.trim();
      if (msg) { history.unshift(msg); if (history.length > 30) history.pop(); }
      closeChat();
      post('send', { message: msg });
    } else if (e.key === 'Escape') {
      e.preventDefault();
      closeChat();
      post('close');
    } else if (e.key === 'ArrowUp' && history.length) {
      e.preventDefault();
      historyIndex = Math.min(historyIndex + 1, history.length - 1);
      input.value = history[historyIndex];
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      historyIndex = Math.max(historyIndex - 1, -1);
      input.value = historyIndex >= 0 ? history[historyIndex] : '';
    } else if (e.key === 'PageUp') {
      messages.scrollTop -= 100;
    } else if (e.key === 'PageDown') {
      messages.scrollTop += 100;
    }
  });

  window.addEventListener('message', (e) => {
    const d = e.data || {};
    switch (d.type) {
      case 'open': openChat(); break;
      case 'close': closeChat(); break;
      case 'message': addMessage(d.message || {}); break;
      case 'suggestions':
        (d.list || []).forEach((s) => { if (s && s.name) suggestions.set(s.name.startsWith('/') ? s.name : '/' + s.name, s.help || ''); });
        break;
      case 'removeSuggestion': suggestions.delete(d.name); break;
      case 'clear': messages.innerHTML = ''; break;
      case 'config':
        if (d.fade) fadeMs = d.fade * 1000;
        if (d.max) maxMessages = d.max;
        if (d.maxLength) input.maxLength = d.maxLength;
        break;
    }
  });
})();
