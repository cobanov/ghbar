// The hero's panel: a working copy of GHBar's, with the app's example data. Rows turn
// seen when clicked, and the count on the menu bar item follows, as in the app.
(function () {
  'use strict';

  var people = {
    'lena-k': '#5b4b8a',
    'tomasz': '#7a5240',
    'dependabot': '#5a3343',
    'ayse-dev': '#3d4b63'
  };

  function pr(repo, number, title, hours, author, extra) {
    return Object.assign({ repo: repo, number: number, title: title, hours: hours, author: author, seen: false }, extra || {});
  }

  var tabs = [
    { key: 'review', title: 'To review', rows: [
      pr('atkctl', 4, 'Support the VXE R1 receiver', 4, 'tomasz')
    ] },
    { key: 'prs', title: 'Pull requests', rows: [
      pr('herdrchat', 55, 'Let the last row scroll clear of the composer', 2, 'lena-k'),
      pr('ghbar', 12, 'Add keyboard navigation to the menu', 5, 'tomasz'),
      pr('teslamate-mcp', 9, 'Bump actions/checkout from 4 to 5', 20, 'dependabot', { bot: true, seen: true }),
      pr('instagram', 3, 'fix: cache-control headers on the media proxy', 30, 'ayse-dev', { draft: true, seen: true }),
      { group: 'paul-graham-turkce', open: false, rows: [1, 2, 3, 4, 5, 6].map(function (n) {
        return pr('paul-graham-turkce', 40 + n, 'Çeviri: essay ' + n, 50 + n, 'lena-k');
      }) }
    ] },
    { key: 'issues', title: 'Issues', rows: [
      pr('teslamate-mcp', 8, 'Optional sponsored field in the trip summary', 72, 'ayse-dev')
    ] }
  ];
  var current = 1;

  var $ = function (id) { return document.getElementById(id); };
  var panel = $('panel'), statusItem = $('status-item');
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  function items(rows) {
    return rows.reduce(function (all, row) { return all.concat(row.group ? row.rows : [row]); }, []);
  }
  function unseen(rows) { return items(rows).filter(function (r) { return !r.seen; }).length; }
  function age(hours) { return hours < 24 ? hours + 'h' : Math.round(hours / 24) + 'd'; }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function icon(id, cls) {
    var ns = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(ns, 'svg');
    if (cls) svg.setAttribute('class', cls);
    svg.setAttribute('aria-hidden', 'true');
    var use = document.createElementNS(ns, 'use');
    use.setAttribute('href', '#' + id);
    svg.appendChild(use);
    return svg;
  }

  function itemRow(item, child) {
    var row = el('button', 'row' + (item.seen ? ' seen' : '') + (child ? ' child' : ''));
    var av = el('span', 'av' + (item.bot ? ' bot' : ''), item.author[0].toUpperCase());
    av.style.background = people[item.author];
    av.setAttribute('aria-hidden', 'true');
    var main = el('span', 'r-main');
    var top = el('span', 'r-top');
    top.appendChild(el('span', 'r-title', item.title));
    top.appendChild(el('span', 'r-age', age(item.hours)));
    main.appendChild(top);
    main.appendChild(el('span', 'r-meta', item.repo + ' #' + item.number + ' by ' + item.author + (item.draft ? ', draft' : '')));
    row.appendChild(av);
    row.appendChild(main);
    row.appendChild(el('span', 'r-dot'));
    row.setAttribute('aria-label', item.title + ', ' + item.repo + ' #' + item.number + ' by ' + item.author + (item.seen ? '' : ', new'));
    row.addEventListener('click', function () { item.seen = true; render(); });
    return row;
  }

  function groupRow(group) {
    var n = unseen(group.rows);
    var row = el('button', 'row group' + (n ? '' : ' seen'));
    row.setAttribute('aria-expanded', String(group.open));
    var av = el('span', 'av folder');
    av.appendChild(icon('folder-glyph'));
    row.appendChild(av);
    row.appendChild(el('span', 'r-title', group.group));
    row.appendChild(el('span', 'g-count' + (n ? ' new' : ''), String(n || group.rows.length)));
    row.appendChild(icon('chev-glyph', 'chev'));
    row.addEventListener('click', function () { group.open = !group.open; render(); });
    return row;
  }

  function render() {
    var tabBar = $('tabs');
    tabBar.textContent = '';
    tabs.forEach(function (tab, i) {
      var n = unseen(tab.rows);
      var b = el('button', 'p-tab', tab.title + ' ');
      b.setAttribute('role', 'tab');
      b.setAttribute('aria-selected', String(i === current));
      b.appendChild(el('span', 'n' + (n ? ' new' : ''), String(n || items(tab.rows).length)));
      b.addEventListener('click', function () { current = i; render(); });
      tabBar.appendChild(b);
    });

    var list = $('list');
    list.textContent = '';
    tabs[current].rows.forEach(function (row) {
      if (!row.group) return list.appendChild(itemRow(row));
      list.appendChild(groupRow(row));
      if (row.open) row.rows.forEach(function (child) { list.appendChild(itemRow(child, true)); });
    });

    $('mark-seen').disabled = unseen(tabs[current].rows) === 0;

    var total = tabs.reduce(function (sum, tab) { return sum + unseen(tab.rows); }, 0);
    $('status-count').textContent = total ? String(total) : '';
    statusItem.setAttribute('aria-label', total ? 'GHBar, ' + total + ' new' : 'GHBar');
  }

  function hhmm(date) {
    return date.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  }
  function tick() {
    var now = new Date();
    $('clock').textContent = now.toLocaleDateString('en-US', { weekday: 'short' }) + ' ' + hhmm(now);
  }

  // The arrow points at the menu bar item, wherever the layout put the panel.
  function place() {
    var s = statusItem.getBoundingClientRect();
    var p = panel.getBoundingClientRect();
    var x = Math.min(Math.max(s.left + s.width / 2 - p.left, 38), p.width - 38);
    panel.style.setProperty('--ax', x + 'px');
  }

  function setOpen(open) {
    panel.hidden = !open;
    statusItem.setAttribute('aria-expanded', String(open));
    if (open && !reduceMotion) {
      panel.classList.remove('opening');
      void panel.offsetWidth;
      panel.classList.add('opening');
    }
  }

  $('mark-seen').addEventListener('click', function () {
    items(tabs[current].rows).forEach(function (r) { r.seen = true; });
    render();
  });

  $('refresh').addEventListener('click', function () {
    var button = this;
    button.classList.remove('spin');
    void button.offsetWidth;
    button.classList.add('spin');
    $('updated').textContent = 'Updated ' + hhmm(new Date());
  });

  statusItem.addEventListener('click', function () { setOpen(panel.hidden); });

  document.querySelectorAll('.copy').forEach(function (button) {
    button.addEventListener('click', function () {
      navigator.clipboard.writeText(button.dataset.copy).then(function () {
        button.textContent = 'Copied';
        button.classList.add('copied');
        setTimeout(function () {
          button.textContent = 'Copy';
          button.classList.remove('copied');
        }, 1600);
      });
    });
  });

  $('updated').textContent = 'Updated ' + hhmm(new Date());
  tick();
  setInterval(tick, 15000);
  render();
  place();
  window.addEventListener('resize', place);
  if (document.fonts) document.fonts.ready.then(place);
  setOpen(true);
})();
