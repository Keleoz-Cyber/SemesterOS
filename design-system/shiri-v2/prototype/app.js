/* =====================================================================
   拾日 · 晴日 v2 — 可交互原型
   - 演示数据为匿名合成数据（第10周，今天 11月4日 周三，现在 13:18）
   - 所有动效参数与 tokens/tokens.json 一致；弹簧曲线在启动时按
     stiffness/damping 计算成 CSS linear()，与 Flutter SpringDescription 同模型
   ===================================================================== */
(() => {
'use strict';

/* ---------- 参数 ---------- */
const Q = new URLSearchParams(location.search);
const SHOT = Q.get('shot');          // 单屏截图模式：today | night | dawn | dusk | schedule | list | tasks | semester | assistant | detail
const VIEW = Q.get('view') || 'screens';
const ASSET = '../assets';
const ICON_FALLBACK = '../../../apps/mobile/assets/brand/app_icon.svg';

/* ---------- 图标（界面用，Material Rounded 风格）---------- */
const S = (p, extra = '') => `<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" ${extra}>${p}</svg>`;
const st = 'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"';
const I = {
  chevR: S('<path d="M9.3 6.7a1 1 0 0 1 1.4 0l4.6 4.6a1 1 0 0 1 0 1.4l-4.6 4.6a1 1 0 1 1-1.4-1.4L13.2 12 9.3 8.1a1 1 0 0 1 0-1.4z"/>'),
  chevL: S('<path d="M14.7 6.7a1 1 0 0 1 0 1.4L10.8 12l3.9 3.9a1 1 0 1 1-1.4 1.4l-4.6-4.6a1 1 0 0 1 0-1.4l4.6-4.6a1 1 0 0 1 1.4 0z"/>'),
  plus: S('<path d="M12 5a1 1 0 0 1 1 1v5h5a1 1 0 1 1 0 2h-5v5a1 1 0 1 1-2 0v-5H6a1 1 0 1 1 0-2h5V6a1 1 0 0 1 1-1z"/>'),
  tune: S(`<path d="M4 7h9M18 7h2M4 17h2M11 17h9" ${st}/><circle cx="15.5" cy="7" r="2.3" ${st}/><circle cx="8.5" cy="17" r="2.3" ${st}/>`),
  spark: S('<path d="M11 3.5c.45 3.9 2.6 6.05 6.5 6.5-3.9.45-6.05 2.6-6.5 6.5-.45-3.9-2.6-6.05-6.5-6.5 3.9-.45 6.05-2.6 6.5-6.5z"/><path d="M18.2 14.2c.2 1.7 1.1 2.6 2.8 2.8-1.7.2-2.6 1.1-2.8 2.8-.2-1.7-1.1-2.6-2.8-2.8 1.7-.2 2.6-1.1 2.8-2.8z" opacity=".8"/>'),
  mic: S(`<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M6 11a6 6 0 0 0 12 0M12 17v3" ${st}/>`),
  image: S(`<rect x="3.5" y="5" width="17" height="14" rx="3.5" ${st}/><circle cx="9" cy="10" r="1.7"/><path d="M5.5 17.5l3.7-3.7a1.5 1.5 0 0 1 2.1 0l1.7 1.7 2.2-2.2a1.5 1.5 0 0 1 2.1 0l2.2 2.2" ${st}/>`),
  person: S(`<circle cx="12" cy="8.5" r="3.6" ${st}/><path d="M5 19.5c1.3-3.1 3.8-4.7 7-4.7s5.7 1.6 7 4.7" ${st}/>`),
  history: S(`<path d="M4.6 12.5A7.5 7.5 0 1 0 6.8 6.7" ${st}/><path d="M4.2 4.4v3.8H8" ${st}/><path d="M12 8.2v4.1l2.7 1.7" ${st}/>`),
  close: S('<path d="M6.7 6.7a1 1 0 0 1 1.4 0L12 10.6l3.9-3.9a1 1 0 1 1 1.4 1.4L13.4 12l3.9 3.9a1 1 0 0 1-1.4 1.4L12 13.4l-3.9 3.9a1 1 0 0 1-1.4-1.4l3.9-3.9-3.9-3.9a1 1 0 0 1 0-1.4z"/>'),
  check: S('<path d="M5 12.6l4.3 4.2L19 7.2" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/>'),
  clock: S(`<circle cx="12" cy="12" r="8" ${st}/><path d="M12 8v4.4l2.9 1.8" ${st}/>`),
  cal: S(`<rect x="4" y="5.5" width="16" height="14.5" rx="3.5" ${st}/><path d="M8 3.5v4M16 3.5v4M4 10.5h16" ${st}/>`),
  pin: S(`<path d="M12 20.5s-6.3-5.4-6.3-10.6a6.3 6.3 0 0 1 12.6 0c0 5.2-6.3 10.6-6.3 10.6z" ${st}/><circle cx="12" cy="9.9" r="2.2" ${st}/>`),
  back: S('<path d="M19.5 12H5.5m6-6.5L5 12l6.5 6.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'),
  more: S('<circle cx="12" cy="5.5" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="12" cy="18.5" r="1.8"/>'),
  arrow: S('<path d="M5 12h13.5m-6-6L18.5 12l-6 6" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>'),
  edit: S(`<path d="M5 19h3.6L18.4 9.2a2.5 2.5 0 0 0-3.6-3.6L5 15.4z" ${st}/>`),
  flag: S(`<path d="M6 20.5V4.5m0 0h9.5l-1.8 3.5 1.8 3.5H6" ${st}/>`),
  /* 导航（outline / filled 同形）*/
  navToday: [S(`<circle cx="12" cy="13" r="4.2" ${st}/><path d="M12 4.6v1.6M5.9 7.2l1.2 1.2M18.1 7.2l-1.2 1.2M3.8 13h1.6M18.6 13h1.6M6.5 20h11" ${st}/>`),
             S(`<circle cx="12" cy="13" r="5"/><path d="M12 4.6v1.6M5.9 7.2l1.2 1.2M18.1 7.2l-1.2 1.2M3.8 13h1.6M18.6 13h1.6M6.5 20h11" ${st}/>`)],
  navSchedule: [S(`<rect x="3.6" y="5.2" width="16.8" height="15" rx="3.6" ${st}/><path d="M3.6 10.4h16.8M9.3 10.4v9.8M14.7 10.4v9.8M8.2 3.4v3.4M15.8 3.4v3.4" ${st}/>`),
                S(`<path d="M7.2 5.2h9.6a3.6 3.6 0 0 1 3.6 3.6v1.6H3.6V8.8a3.6 3.6 0 0 1 3.6-3.6zM3.6 12h4.9v8.2H7.2a3.6 3.6 0 0 1-3.6-3.6zm6.5 0h3.8v8.2h-3.8zm5.4 0h4.9v4.6a3.6 3.6 0 0 1-3.6 3.6h-1.3z"/><path d="M8.2 3.4v3.4M15.8 3.4v3.4" ${st}/>`)],
  navTasks: [S(`<circle cx="7" cy="7.5" r="2.7" ${st}/><circle cx="7" cy="16.5" r="2.7" ${st}/><path d="M12.6 7.5h7.4M12.6 16.5h7.4" ${st}/>`),
             S(`<circle cx="7" cy="7.5" r="3.6"/><path d="M5.4 7.5l1.1 1.1 2-2.1" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/><circle cx="7" cy="16.5" r="2.7" ${st}/><path d="M12.6 7.5h7.4M12.6 16.5h7.4" ${st}/>`)],
  navSemester: [S(`<path d="M3.8 17.5h5.6M14.6 17.5h5.6" ${st}/><circle cx="6.8" cy="17.5" r="1.5"/><circle cx="17.2" cy="17.5" r="1.5"/><circle cx="12" cy="17.5" r="2.6" ${st}/><path d="M12 14.9V5.2h5.6l-1.5 2.2 1.5 2.2H12" ${st}/>`),
                S(`<path d="M3.8 17.5h16.4" ${st}/><circle cx="6.8" cy="17.5" r="1.5"/><circle cx="17.2" cy="17.5" r="1.5"/><circle cx="12" cy="17.5" r="3.2"/><path d="M12 14.9V5.2h5.6l-1.5 2.2 1.5 2.2H12z" fill="currentColor" ${st}/>`)],
};
const icon = (name, size = 22, alt = '') => `<img src="${ASSET}/icons/${name}.svg" width="${size}" height="${size}" alt="${alt}">`;

/* ---------- 太阳 / 月亮 / 波浪（与新图标同形）---------- */
const SUN = `<svg viewBox="0 0 64 64" aria-hidden="true"><defs><linearGradient id="sg" x1="14" y1="18" x2="48" y2="58" gradientUnits="userSpaceOnUse"><stop stop-color="#FFEBA6"/><stop offset="1" stop-color="#F6C86B"/></linearGradient><radialGradient id="sglow" cx="32" cy="38" r="30" gradientUnits="userSpaceOnUse"><stop stop-color="#FFE9A8" stop-opacity=".7"/><stop offset="1" stop-color="#FFE9A8" stop-opacity="0"/></radialGradient></defs><circle cx="32" cy="38" r="30" fill="url(#sglow)"/><circle cx="32" cy="38" r="15" fill="url(#sg)"/><g stroke="url(#sg)" stroke-width="4.4" stroke-linecap="round"><path d="M20.4 21.6l-4.4-6.2"/><path d="M32 18v-8"/><path d="M43.6 21.6l4.4-6.2"/></g><path d="M22 36.5c3.4-2.4 7.4-2.6 10.6-.6 3.2 2 6 4.2 8.6 6.4" stroke="#fff" stroke-opacity=".75" stroke-width="3.2" stroke-linecap="round" fill="none"/></svg>`;
const MOON = `<svg viewBox="0 0 64 64" aria-hidden="true"><defs><linearGradient id="mg" x1="18" y1="16" x2="46" y2="52" gradientUnits="userSpaceOnUse"><stop stop-color="#FFF1BF"/><stop offset="1" stop-color="#F6C86B"/></linearGradient><radialGradient id="mglow" cx="32" cy="34" r="28" gradientUnits="userSpaceOnUse"><stop stop-color="#FFE9A8" stop-opacity=".35"/><stop offset="1" stop-color="#FFE9A8" stop-opacity="0"/></radialGradient></defs><circle cx="32" cy="34" r="28" fill="url(#mglow)"/><path d="M38.5 18.5a16 16 0 1 0 8 26.6A13 13 0 0 1 38.5 18.5z" fill="url(#mg)"/><path d="M47 14.5c.3 2.2 1.5 3.4 3.7 3.7-2.2.3-3.4 1.5-3.7 3.7-.3-2.2-1.5-3.4-3.7-3.7 2.2-.3 3.4-1.5 3.7-3.7z" fill="#FFF1BF"/></svg>`;

/* ---------- 演示数据（匿名）---------- */
const NOW = { h: 13, m: 18 };
const PAL = {
  sky: ['#E8F2FF', '#4A90F0', '#1D5BB5'], mint: ['#E4F6EF', '#3DBE8B', '#0F7656'], aqua: ['#E3F6FA', '#33B5CF', '#0E6F85'],
  lilac: ['#EFECFF', '#8C7BF0', '#5443BE'], apricot: ['#FFF0E6', '#F39A62', '#A9501F'], blossom: ['#FDECF2', '#E7779D', '#A83A61'],
  wheat: ['#FFF6DD', '#E5B23C', '#8A6100'], mist: ['#EDF1F6', '#8193AB', '#44566E'],
};
const PERIODS = [['08:00', 1], ['09:00', 2], ['10:10', 3], ['11:10', 4], null, ['14:00', 5], ['15:00', 6], ['16:10', 7], ['17:10', 8], null, ['19:00', 9], ['20:00', 10]];
// [day 0-6, startRow(1-10, 可带小数), endRow, title, room, kind, palette]
const BLOCKS = [
  [0, 1, 2, '高等数学', 'A301', 'course', 'sky'], [0, 3, 4, '大学英语', 'B204', 'course', 'lilac'], [0, 5, 6, '数据结构', 'A305', 'course', 'mint'],
  [1, 1, 2, '线性代数', 'A301', 'course', 'aqua'], [1, 3, 4, '程序设计', '机房3', 'course', 'apricot'], [1, 7, 8, '体育', '操场', 'course', 'wheat'],
  [2, 1, 2, '大学物理', 'C102', 'course', 'blossom'], [2, 5, 6, '数据结构', 'A305', 'course', 'mint'], [2, 7.85, 8.85, '组会', '实验室302', 'event'],
  [3, 1, 2, '高等数学', 'A301', 'course', 'sky'], [3, 3, 4, '操作系统', 'A402', 'course', 'mist'], [3, 6, 7, '开会', '办公室', 'event'], [3, 9, 10, '概率论', 'B102', 'course', 'lilac'],
  [4, 1, 2, '软件工程', 'A305', 'course', 'aqua'], [4, 3, 4, '大学英语', 'B204', 'course', 'lilac'], [4, 5, 6, '大学物理', 'C102', 'exam'], [4, 9, 10.5, '复习线代', '学习安排', 'plan'],
];
const DAYS = [['一', 2], ['二', 3], ['三', 4], ['四', 5], ['五', 6], ['六', 7], ['日', 8]];

/* ---------- 弹簧 → CSS linear() ---------- */
function springEasing(stiffness, damping, mass = 1) {
  const dt = 1 / 600; let x = 0, v = 0, t = 0; const pts = [];
  while (t < 2.5) {
    const a = (-stiffness * (x - 1) - damping * v) / mass;
    v += a * dt; x += v * dt; t += dt; pts.push(x);
    if (t > 0.08 && Math.abs(x - 1) < 0.0015 && Math.abs(v) < 0.02) break;
  }
  const n = 48, out = [];
  for (let i = 0; i <= n; i++) out.push(i === 0 ? 0 : i === n ? 1 : +pts[Math.min(pts.length - 1, Math.round(i / n * pts.length) - 1)].toFixed(4));
  return { easing: `linear(${out.join(', ')})`, ms: Math.round(t * 1000) };
}
function installSprings() {
  const r = document.documentElement.style;
  [['snappy', 520, 38], ['gentle', 260, 26], ['pop', 420, 20]].forEach(([k, s, d]) => {
    const e = springEasing(s, d); r.setProperty(`--spring-${k}`, e.easing); r.setProperty(`--spring-${k}-d`, `${e.ms}ms`);
  });
}

/* ---------- 工具 ---------- */
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const stagger = (i) => `style="animation-delay:${Math.min(i, 8) * 36}ms"`;
const fmt = (h, m) => `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
function skyPhase(h, m) { const t = h + m / 60; if (t >= 5 && t < 8) return 'dawn'; if (t >= 8 && t < 16.5) return 'day'; if (t >= 16.5 && t < 19) return 'dusk'; return 'night'; }
function sunPos(h, m) { const p = Math.min(1, Math.max(0, (h + m / 60 - 6) / 12)); const x = 176 * p; const y = 96 * ((1 - p) ** 2 + p ** 2) - 160 * p * (1 - p); return { x, y, p }; }

/* =====================================================================
   屏幕：今日
   ===================================================================== */
function sky(h = NOW.h, m = NOW.m) {
  const ph = skyPhase(h, m); const night = ph === 'night'; const s = sunPos(h, m);
  const arc = `<svg viewBox="0 0 176 104" aria-hidden="true"><path d="M0 96Q88 -80 176 96" fill="none" stroke="${night ? 'rgba(255,255,255,.28)' : 'rgba(255,255,255,.9)'}" stroke-width="2" stroke-dasharray="2 6" stroke-linecap="round"/>${night ? '' : `<path d="M0 96Q88 -80 176 96" fill="none" stroke="url(#arcg)" stroke-width="2.4" stroke-linecap="round" pathLength="100" stroke-dasharray="${(s.p * 100).toFixed(1)} 100"/>`}<defs><linearGradient id="arcg" x1="0" y1="0" x2="176" y2="0" gradientUnits="userSpaceOnUse"><stop stop-color="#FFE7A6" stop-opacity=".2"/><stop offset="1" stop-color="#F6C86B"/></linearGradient></defs></svg>`;
  return `<section class="sky ${ph}" data-sky>
    <div class="sky-top"><div class="brand"><img src="${ASSET}/brand/mark.svg" onerror="this.onerror=null;this.src='${ICON_FALLBACK}'" alt="">拾日</div><button class="avatar" aria-label="我的">${I.person}</button></div>
    <div class="sky-date"><div class="row"><span class="t-display">11月4日</span><span class="wk">周三</span></div>
      <div class="chips"><span class="chip chip-glass">第 10 周</span><span class="t-caption" style="align-self:center;opacity:.7">共 20 周</span></div></div>
    <div class="arc">${arc}<div class="sun rise" style="left:${night ? 140 : s.x.toFixed(1)}px;top:${night ? 22 : s.y.toFixed(1)}px">${night ? MOON : SUN}</div></div>
    <div class="wave"><img src="${ASSET}/patterns/wave-hero.svg" alt=""></div>
  </section>`;
}
function nextCard() {
  return `<article class="next-card card-raised pressable" tabindex="0" aria-label="下一节 数据结构，14:00 开始，还有 42 分钟">
    <span class="bar" style="background:${PAL.mint[1]}"></span>
    <div class="body">
      <div class="lead"><span class="now-dot"></span>下一节<span class="count-pill"><span class="roll" data-roll="42">42</span> 分钟后</span></div>
      <div class="main"><span class="t-num-l">14:00</span><span class="t-title">数据结构</span></div>
      <div class="meta"><span class="num">14:00–15:50</span> · A305 · 第5–6节</div>
    </div>
  </article>`;
}
function gapCard() {
  return `<article class="gap-card" data-gap>
    <div class="hd">${icon('gap', 22)}<span class="ttl">课前空档</span><span class="dur num">40 分钟</span></div>
    <div class="slot" data-slot><div class="fill"><span class="ok">${I.check.replace('currentColor', '#2E6FE0')}</span>20 分钟</div></div>
    <div class="slot-times num"><span>13:20</span><span>14:00 数据结构</span></div>
    <div class="task"><b>整理实验数据</b><span class="ink-500 t-body-s">预计需要 20 分钟</span></div>
    <div class="acts"><button class="btn btn-primary btn-sm" data-act="arrange">${I.arrow}安排这项</button><button class="btn btn-text">查看任务</button></div>
    <div class="preview"><span class="ink-500">${I.clock}</span><div style="flex:1"><div class="t-body-strong num">今天 13:20–13:40</div><div class="t-caption ink-500">只追加这一段，已有安排不动</div></div><button class="btn btn-primary btn-sm" data-act="save-plan">保存</button></div>
    <div class="receipt"><span class="ok" style="width:22px;height:22px;border-radius:50%;background:var(--success-accent);display:grid;place-items:center;color:#fff">${I.check}</span>已安排 <span class="num">13:20–13:40</span><button class="btn btn-text" style="margin-left:auto" data-act="undo-plan">撤销</button></div>
  </article>`;
}
function timeline(arranged = false) {
  const row = (cls, t, end, color, title, meta, kind = '', i = 0) => `<div class="tl-row ${cls}" ${stagger(i)}><div class="t"><span class="t-num-m">${t}</span>${end ? `<span class="end">${end}</span>` : ''}</div><div class="rail"><span class="node" style="background:${color}"></span></div><div class="item ${kind}"><div class="tt">${title}</div><div class="mm">${meta}</div></div></div>`;
  return `<div class="timeline stagger">
    ${row('past', '08:00', '09:50', PAL.blossom[1], '大学物理', '<span>C102</span><span class="chip chip-neutral" style="height:22px">已结束</span>', '', 0)}
    <div class="tl-free" ${stagger(1)}><span></span><div class="rail"></div><span>空闲 3 小时 28 分</span></div>
    <div class="tl-now" ${stagger(2)}><span class="lbl">13:18</span><div class="rail" style="height:100%;position:relative"><span class="now-dot" style="position:absolute;top:10px"></span></div><div class="line"></div></div>
    ${arranged
      ? row('', '13:20', '13:40', '#4CA4FF', '整理实验数据', '<span class="chip chip-primary" style="height:22px">学习安排</span><span>20 分钟</span>', 'k-plan', 3)
      : row('', '13:20', '14:00', '#9BC9EE', '课前空档 · 40 分钟', '<span>可放进一项 20 分钟以内的待办</span>', 'k-plan', 3)}
    ${row('next', '14:00', '15:50', PAL.mint[1], '数据结构', '<span>A305</span><span>·</span><span>第5–6节</span>', '', 4)}
    ${row('', '17:00', '18:00', '#3FBF8F', '组会', '<span>实验室302</span><span class="chip chip-success" style="height:22px">活动</span>', 'k-event', 5)}
  </div>`;
}
function taskRow(t, i = 0) {
  return `<div class="task-row" data-task="${t.id}" ${stagger(i)}>
    <button class="check" data-act="complete" aria-label="完成 ${t.title}"><span class="ring"><svg viewBox="0 0 24 24"><circle class="track" cx="12" cy="12" r="10.5"/><circle class="fill" cx="12" cy="12" r="12"/><circle class="arc" cx="12" cy="12" r="10.5"/><path class="tick" d="M7.2 12.4l3.2 3.1 6.4-6.6"/></svg></span></button>
    <div class="tbody"><div class="ttl"><span class="strike">${t.title}</span></div><div class="meta">${t.chip}<span class="src">${t.src}</span></div></div>
    <span class="rem">${t.rem}</span>
  </div>`;
}
const TASKS = [
  { id: 't1', title: '提交实验报告', chip: `<span class="chip chip-danger">${I.clock}今天 23:59</span>`, src: '大学物理', rem: '还需 1 小时' },
  { id: 't2', title: '助学金申请', chip: `<span class="chip chip-warning">${I.flag}11月6日</span>`, src: '学工通知', rem: '还需 30 分钟' },
  { id: 't3', title: '公式推导', chip: `<span class="chip chip-neutral">11月10日</span>`, src: '线性代数', rem: '还需 1.5 小时' },
];
function examCard(d, title, meta, calm = false) {
  return `<article class="exam-card ${calm ? 'calm' : ''}"><div class="d"><span class="t-num-xl">${d}</span><span class="u">天后</span></div><div class="n">${title}</div><div class="m num">${meta}</div></article>`;
}
function weekBars() {
  const hrs = [6, 6, 5, 7, 7, 0, 1];
  return `<div class="bars">${hrs.map((h, i) => `<div class="b ${i === 2 ? 'today' : ''}"><span class="hrs">${h ? h + 'h' : ''}</span><i class="col ${i > 4 ? 'light' : ''}" style="height:${Math.max(6, h / 8 * 80)}px;animation-delay:${i * 40}ms"></i><span class="lb">${DAYS[i][0]}</span></div>`).join('')}</div>`;
}
function todayScreen(opts = {}) {
  const { h = NOW.h, m = NOW.m } = opts;
  return `${sky(h, m)}
    ${nextCard()}
    ${gapCard()}
    <div class="section-head"><h3>今天</h3><span class="count">4</span><button class="more">全部${I.chevR}</button></div>
    ${timeline()}
    <div class="section-head"><h3>待办</h3><span class="count">3</span><button class="more">全部${I.chevR}</button></div>
    <div class="card task-list stagger" data-list>${TASKS.map(taskRow).join('')}</div>
    <div class="section-head"><h3>近期考试</h3><span class="count">3</span></div>
    <div class="h-scroll">${examCard(2, '大学物理 · 期中', '11月6日 周五 14:00 · C102')}${examCard(6, '线性代数 · 期中', '11月10日 周二 09:00 · A301')}${examCard(13, '大学英语 · 口语', '11月17日 周二 10:10 · B204', true)}</div>
    <div class="section-head"><h3>本周</h3><span class="ink-500 t-body-s" style="margin-left:auto">已排 <b class="num">32</b> 小时</span></div>
    <div class="card week-card">${weekBars()}</div>
    <div class="screen-pad-bottom"></div>`;
}

/* =====================================================================
   屏幕：日程（周课表 / 列表）
   ===================================================================== */
function rowTop(r) { // r: 1..10，可带小数；午休、晚饭各压缩成 14px
  const whole = Math.floor(r), frac = r - whole;
  let y = (whole - 1) * 56 + frac * 56;
  if (whole >= 5) y += 14; if (whole >= 9) y += 14;
  return y;
}
function scheduleGrid() {
  const axis = PERIODS.map(p => p ? `<div class="p"><b>${p[1]}</b><small>${p[0]}</small></div>` : '<div class="brk"></div>').join('');
  const nowY = rowTop(5) - 9; // 13:18 位于午休带内
  const cols = DAYS.map((d, di) => {
    const cells = PERIODS.map(p => p ? '<div class="cell"></div>' : '<div class="cell brk"></div>').join('');
    const blocks = BLOCKS.filter(b => b[0] === di).map(b => {
      const [, s, e, title, room, kind, pal] = b;
      const top = rowTop(s), h = rowTop(e + 1) - top - 4 - (Math.floor(e + 1) === 5 || Math.floor(e + 1) === 9 ? 14 : 0);
      const p = PAL[pal] || PAL.sky;
      const style = kind === 'course' ? `--bgc:${p[0]};--acc:${p[1]};--txt:${p[2]};` : '';
      const badge = kind === 'plan' ? '<span class="badge">计划</span>' : kind === 'exam' ? '<span class="badge">考试</span>' : '';
      return `<div class="blk k-${kind}" style="top:${top + 2}px;height:${h}px;${style}" data-act="open-detail" data-title="${title}" data-room="${room}" data-pal="${pal || ''}" data-kind="${kind}" tabindex="0" role="button" aria-label="${title} ${room}">${badge}<span class="bt">${title}</span><span class="bl">${room}</span></div>`;
    }).join('');
    return `<div class="col ${di === 2 ? 'today' : ''}">${cells}${blocks}</div>`;
  }).join('');
  return `<div class="days"><div class="now"><span>现在</span><b>13:18</b></div>${DAYS.map((d, i) => `<div class="d ${i === 2 ? 'today' : ''}"><span class="w">${i === 2 ? '今天' : '周' + d[0]}</span><span class="n">${d[1]}</span></div>`).join('')}</div>
    <div class="grid"><div class="axis">${axis}<div class="rail" style="height:${nowY}px"><span class="now-dot"></span></div></div>${cols}</div>`;
}
function agenda() {
  const day = (title, sub, rows) => `<div class="day"><h4>${title}<small>${sub}</small></h4>${rows.map(([t, e, n, meta, acc]) => `<div class="row" style="--acc:${acc}"><div class="tm"><span class="t-num-m">${t}</span><small>${e}</small></div><div style="flex:1;min-width:0"><div class="t-body-strong">${n}</div><div class="t-caption ink-500">${meta}</div></div>${I.chevR.replace('<svg', '<svg width="18" height="18" style="color:var(--ink-400)"')}</div>`).join('')}</div>`;
  return `<div class="agenda stagger">
    ${day('今天 · 周三', '11月4日 · 3 项', [['08:00', '09:50', '大学物理', 'C102 · 课程', PAL.blossom[1]], ['14:00', '15:50', '数据结构', 'A305 · 课程', PAL.mint[1]], ['17:00', '18:00', '组会', '实验室302 · 活动', '#3FBF8F']])}
    ${day('周四', '11月5日 · 4 项', [['08:00', '09:50', '高等数学', 'A301 · 课程', PAL.sky[1]], ['10:10', '12:00', '操作系统', 'A402 · 课程', PAL.mist[1]], ['15:00', '16:00', '开会', '办公室 · 活动', '#3FBF8F'], ['19:00', '20:50', '概率论', 'B102 · 课程', PAL.lilac[1]]])}
    ${day('周五', '11月6日 · 4 项', [['14:00', '15:40', '大学物理 · 期中', 'C102 · 考试', '#F0705A'], ['19:00', '20:30', '复习线代', '学习安排', '#4CA4FF']])}
  </div>`;
}
function scheduleScreen(view = 'grid') {
  return `<header class="sched-head">
      <div class="r1"><div class="ttl"><span class="t-headline">第10周</span><small>11/2 – 11/8</small></div>
        <button class="icon-btn" aria-label="上一周" style="margin-left:auto">${I.chevL}</button><button class="today-chip">今天</button><button class="icon-btn" aria-label="下一周">${I.chevR}</button></div>
      <div class="r2"><div class="seg" role="tablist" data-seg="sched"><span class="seg-ind"></span><button role="tab" aria-selected="${view === 'grid'}" data-act="seg" data-i="0">周课表</button><button role="tab" aria-selected="${view === 'list'}" data-act="seg" data-i="1">列表</button></div><span class="sp"></span>
        <button class="icon-btn" aria-label="筛选">${I.tune}</button><button class="icon-btn" aria-label="新建">${I.plus}</button></div>
    </header>
    <div data-sched-body class="enter">${view === 'grid' ? scheduleGrid() : agenda()}</div>
    <div class="screen-pad-bottom"></div>`;
}

/* =====================================================================
   屏幕：任务
   ===================================================================== */
function tasksScreen() {
  const g = (dot, label, n) => `<div class="group-head"><span class="dot" style="background:${dot}"></span>${label}<span class="num ink-400">${n}</span></div>`;
  return `<header class="page-head"><span class="t-headline">任务</span><button class="icon-btn" aria-label="筛选">${I.tune}</button><button class="icon-btn" aria-label="新建任务">${I.plus}</button></header>
    <div class="stats stagger"><div class="stat hot" ${stagger(0)}><div class="v"><span class="t-num-l roll" data-roll="1">1</span></div><div class="k">今天截止</div></div><div class="stat" ${stagger(1)}><div class="v"><span class="t-num-l">4</span></div><div class="k">本周</div></div><div class="stat" ${stagger(2)}><div class="v"><span class="t-num-l">1</span></div><div class="k">未定日期</div></div></div>
    <div style="padding:16px var(--page) 0"><div class="seg" role="tablist" data-seg="tasks"><span class="seg-ind"></span><button role="tab" aria-selected="true" data-act="seg" data-i="0">待处理</button><button role="tab" aria-selected="false" data-act="seg" data-i="1">已完成</button><button role="tab" aria-selected="false" data-act="seg" data-i="2">已取消</button></div></div>
    ${g('var(--danger-accent)', '今天', 1)}
    <div class="card task-list" data-list>${taskRow(TASKS[0])}</div>
    ${g('var(--warning-accent)', '本周', 2)}
    <div class="card task-list" data-list>${taskRow(TASKS[1])}${taskRow({ id: 't4', title: '整理实验数据', chip: `<span class="chip chip-primary">${I.cal}已安排 今天 13:20</span>`, src: '数据结构', rem: '还需 20 分钟' })}</div>
    ${g('var(--line-strong)', '下周及以后', 1)}
    <div class="card task-list" data-list>${taskRow(TASKS[2])}</div>
    ${g('var(--line-strong)', '未定日期', 1)}
    <div class="card task-list" data-list>${taskRow({ id: 't5', title: '提交报名表', chip: '<span class="chip chip-neutral">方便时</span>', src: '交给班级负责人', rem: '' })}</div>
    <div class="section-head"><h3>学习安排</h3><span class="ink-500 t-body-s">本周 3 段 · <span class="num">2</span> 小时 <span class="num">10</span> 分</span></div>
    <div class="plan-card"><div class="hd">${icon('plan', 22)}<b>按你设定的学习时段排</b><button class="btn btn-text">设置时段</button></div>
      <div class="plan-chips"><div class="plan-chip"><div class="w">今天 13:20</div><div class="n">整理实验数据</div></div><div class="plan-chip"><div class="w">周五 19:00</div><div class="n">复习线代</div></div><div class="plan-chip"><div class="w">周六 10:00</div><div class="n">阅读文献</div></div></div></div>
    <div class="screen-pad-bottom"></div>`;
}

/* =====================================================================
   屏幕：学期
   ===================================================================== */
function horizon() {
  // 20 周排在一条地平线弧上，太阳在第10周（弧顶）
  const W = 390, pts = [];
  for (let i = 0; i < 20; i++) { const t = i / 19; const x = 24 + t * (W - 48); const y = 128 - Math.sin(Math.PI * t) * 70; pts.push([x, y]); }
  const marks = { 5: ['#3FBF8F', '国庆'], 10: ['#F0705A', '期中'], 11: ['#F0705A', ''], 19: ['#F0705A', '期末'], 20: ['#F0705A', ''] };
  const path = pts.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
  const done = pts.slice(0, 10).map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
  const sun = pts[9];
  return `<svg viewBox="0 0 390 150" aria-label="学期进度：第10周，共20周"><defs><linearGradient id="hz" x1="0" x2="1"><stop stop-color="#4CA4FF"/><stop offset=".52" stop-color="#63CFE9"/><stop offset="1" stop-color="#8DE0B2"/></linearGradient></defs>
    <path d="${path}" fill="none" stroke="#D2DDEA" stroke-width="2" stroke-dasharray="2 5" stroke-linecap="round"/>
    <path d="${done}" fill="none" stroke="url(#hz)" stroke-width="3.2" stroke-linecap="round"/>
    ${pts.map((p, i) => { const mk = marks[i + 1]; return `<circle cx="${p[0].toFixed(1)}" cy="${p[1].toFixed(1)}" r="${mk ? 4.2 : 2.4}" fill="${mk ? mk[0] : (i < 10 ? '#63CFE9' : '#D2DDEA')}" stroke="#fff" stroke-width="${mk ? 2 : 0}"/>${mk && mk[1] ? `<text x="${p[0].toFixed(1)}" y="${(p[1] + 20).toFixed(1)}" text-anchor="middle" font-size="11" font-weight="700" fill="${mk[0]}">${mk[1]}</text>` : ''}`; }).join('')}
    <g transform="translate(${(sun[0] - 23).toFixed(1)} ${(sun[1] - 40).toFixed(1)})"><svg width="46" height="46" viewBox="0 0 64 64">${SUN.replace(/^<svg[^>]*>/, '').replace('</svg>', '')}</svg></g>
    <text x="24" y="146" font-size="11" fill="#8291A7" font-weight="600">第1周</text><text x="366" y="146" font-size="11" fill="#8291A7" font-weight="600" text-anchor="end">第20周</text>
  </svg>`;
}
function semesterScreen() {
  const weeks = Array.from({ length: 20 }, (_, i) => i + 1);
  const date = (w) => { const d = new Date(2026, 7, 31 + (w - 1) * 7); return `${d.getMonth() + 1}/${d.getDate()}`; };
  return `<section class="sem-hero"><div class="cap">2026–2027 学年 · 第一学期</div><div class="big"><span class="t-num-xl">第10周</span><span class="of">共 20 周 · 还剩 10 周</span></div><div class="horizon">${horizon()}</div></section>
    <div class="weeks" data-weeks><span class="selpill"></span>${weeks.map(w => `<button class="wk ${w === 10 ? 'sel cur' : ''}" data-act="week" data-w="${w}" aria-label="第${w}周"><b>${w}</b><small>${date(w)}</small>${[10, 11, 19, 20].includes(w) ? '<i class="mk"></i>' : ''}</button>`).join('')}</div>
    <div class="wk-body" data-wkbody>
      <div class="range"><span class="t-title">11月2日 – 11月8日</span><span class="chip chip-danger">1 场考试</span></div>
      <div class="card" style="margin-top:8px">
        <div class="ev-row">${icon('exam', 24)}<div class="tx"><b>大学物理 · 期中考试</b><small class="num">11月6日 周五 14:00 · C102</small></div><span class="chip chip-danger">D-2</span></div>
        <div class="ev-row">${icon('deadline', 24)}<div class="tx"><b>提交实验报告</b><small class="num">今天 23:59 截止</small></div></div>
        <div class="ev-row">${icon('deadline', 24)}<div class="tx"><b>助学金申请</b><small class="num">11月6日 截止</small></div></div>
        <div class="ev-row">${icon('event', 24)}<div class="tx"><b>组会 · 开会</b><small class="num">周三 17:00 · 周四 15:00</small></div></div>
        <div class="ev-row">${icon('reschedule', 24)}<div class="tx"><b>概率论 调课</b><small class="num">周四 19:00 → 周五 19:00</small></div><span class="chip chip-primary">变动</span></div>
      </div>
    </div>
    <div class="section-head"><h3>学期资料</h3></div>
    <div class="tiles stagger">${[['course', '课程', '10 门'], ['exam', '考试', '4 场'], ['stats', '统计', '本周 32 小时'], ['tag', '标签', '6 个'], ['import', '导入课表', '核对后保存'], ['semester', '学期管理', '20 周']].map(([ic, n, s], i) => `<button class="tile pressable" ${stagger(i)}><span class="ic">${icon(ic, 24)}</span><b>${n}</b><small>${s}</small></button>`).join('')}</div>
    <div class="screen-pad-bottom"></div>`;
}

/* =====================================================================
   屏幕：助手面板
   ===================================================================== */
function assistantSheet() {
  return `<div class="scrim" data-act="close-assistant"></div>
  <section class="sheet" role="dialog" aria-label="助手">
    <div class="grab"></div>
    <div class="sh-head"><button class="icon-btn" data-act="close-assistant" aria-label="收起">${I.close}</button><div class="ttl"><b>助手</b><small>2026–2027 第一学期</small></div><button class="icon-btn" aria-label="历史">${I.history}</button><button class="icon-btn" aria-label="新对话">${I.plus}</button></div>
    <div class="convo">
      <div class="bubble-u">这周哪天有一小时空闲？</div>
      <div class="ai"><span class="av" style="color:#fff">${I.spark}</span><div class="txt">按已记录的日程，<em>11月5–8日</em>每天都有至少 <em>1 小时</em>空档。</div></div>
      <div class="slots"><div class="t-label ink-500">日程空档 · 查询 08:00–22:00</div>
        ${[['11月5日 周四', '12:00–15:00', 4 / 14, 7 / 14], ['11月6日 周五', '16:00–19:00', 8 / 14, 11 / 14], ['11月7日 周六', '08:00–22:00', 0, 1]].map(([d, t, a, b]) => `<div class="sr"><span class="t-body-strong">${d}</span><span class="num t-body-s ink-700">${t}</span><div class="bar"><i style="left:${a * 100}%;width:${(b - a) * 100}%"></i></div></div>`).join('')}
        <button class="btn btn-text" style="margin-left:-12px">再显示 2 项</button></div>
      <div class="bubble-u">大家明天下午三点到我办公室开会 @所有人</div>
      <div class="ai"><span class="av" style="color:#fff">${I.spark}</span><div class="txt">整理出 1 项日程，确认后保存。</div></div>
      <div class="parse reveal" data-parse>
        <div class="ph" style="animation-delay:0ms">${icon('event', 20)}添加到日程<span class="chip chip-success" style="margin-left:auto;height:22px">活动</span></div>
        <div class="pt" style="animation-delay:40ms">开会</div>
        <div class="fields"><div class="f" style="animation-delay:80ms"><span>时间</span><span><span class="hl num">11月5日 周四 15:00</span> <span class="chip chip-primary" style="height:22px">明天</span></span></div><div class="f" style="animation-delay:120ms"><span>地点</span><span>发布者办公室</span></div><div class="f" style="animation-delay:160ms"><span>对象</span><span>全体成员</span></div></div>
        <div class="pa" style="animation-delay:200ms"><button class="btn btn-text">暂不添加</button><button class="btn btn-primary btn-sm" data-act="confirm-add">确认添加</button></div>
      </div>
    </div>
    <div class="composer"><span class="ctx">${I.cal}浏览：11月2日–11月8日<button class="icon-btn" style="width:28px;height:28px" aria-label="移除浏览范围">${I.close}</button></span>
      <div class="box"><div class="in">输入通知或问题</div><div class="tools"><div class="wave-pill">${Array.from({ length: 18 }, (_, i) => `<i style="animation-delay:${(i * 53) % 400}ms"></i>`).join('')}</div><button class="icon-btn ghost" aria-label="按住说话" data-hold>${I.mic}</button><button class="icon-btn ghost" aria-label="图片">${I.image}</button><button class="send" aria-label="发送">${I.arrow.replace('M5 12h13.5m-6-6L18.5 12l-6 6', 'M12 19V5.5m-6 6L12 5.5l6 6')}</button></div></div></div>
  </section>`;
}

/* =====================================================================
   课程详情（容器变换的终点）
   ===================================================================== */
function detailView(title = '数据结构', room = 'A305', pal = 'mint') {
  const p = PAL[pal] || PAL.mint;
  return `<div class="detail" data-detail style="--bgc:${p[0]};--txt:${p[2]}">
    <div class="dh"><div class="top"><button class="icon-btn" data-act="close-detail" aria-label="返回">${I.back}</button><button class="icon-btn" aria-label="更多">${I.more}</button></div>
      <h2>${title}</h2><div class="chips"><span class="chip num">周一 · 周三 14:00–15:50</span><span class="chip">${room}</span><span class="chip num">第 1–16 周</span></div></div>
    <div class="stagger">
      <div class="card sec" ${stagger(0)}><h5>本次课</h5><div class="kv">${icon('plan', 22)}<div><div class="t-body-strong num">11月4日 周三 14:00–15:50</div><div class="t-caption ink-500">第5–6节 · 还有 42 分钟</div></div></div><div class="kv">${icon('location', 22)}<div class="t-body-strong">${room}</div></div></div>
      <div class="card sec" ${stagger(1)}><h5>相关任务</h5>${taskRow({ id: 'd1', title: '整理实验数据', chip: `<span class="chip chip-primary">${I.cal}已安排 今天 13:20</span>`, src: '', rem: '20 分钟' }).replace('class="task-row"', 'class="task-row" style="padding-left:12px;padding-right:0"')}</div>
      <div class="card sec" ${stagger(2)}><h5>调课与停课</h5><div class="t-body ink-500">本学期没有变动</div></div>
      <div class="card sec" ${stagger(3)}><h5>全部课次</h5><div class="t-body">16 次 · 已上 <b class="num">9</b> 次</div><div class="progress"><i style="width:56%"></i></div></div>
    </div></div>`;
}

/* =====================================================================
   手机外壳 + 导航坞
   ===================================================================== */
const TABS = [['today', '今日', I.navToday], ['schedule', '日程', I.navSchedule], ['tasks', '任务', I.navTasks], ['semester', '学期', I.navSemester]];
function dock(active) {
  return `<nav class="dock" aria-label="主导航"><span class="ind"></span>${TABS.map(([id, label, ic]) => `<button data-act="tab" data-tab="${id}" ${id === active ? 'aria-current="page"' : ''}><span class="ic"><span class="o">${ic[0]}</span><span class="f">${ic[1]}</span></span><span class="lb">${label}</span></button>`).join('')}</nav>`;
}
function pill() {
  return `<div class="ask" data-pill><span class="spark" style="color:var(--sky)">${I.spark}</span><button class="ph" data-act="open-assistant" style="text-align:left">记一条通知，或问问日程</button><button class="act" aria-label="图片" data-act="open-assistant">${I.image}</button><button class="mic" aria-label="按住说话" data-hold>${I.mic}</button></div>`;
}
function statusbar(dark) {
  return `<div class="statusbar ${dark ? 'on-dark' : ''}"><span>13:18</span><span class="icons"><i style="width:17px;height:11px;clip-path:polygon(0 100%,100% 0,100% 100%)"></i><i style="width:15px;height:11px;border-radius:8px 8px 2px 2px"></i><i style="width:24px;height:12px;border-radius:4px;opacity:.9"></i></span></div>`;
}
function screenHTML(id, opts = {}) {
  if (id === 'today') return todayScreen(opts);
  if (id === 'schedule') return scheduleScreen(opts.view || 'grid');
  if (id === 'tasks') return tasksScreen();
  if (id === 'semester') return semesterScreen();
  return '';
}
function phone(id, opts = {}) {
  const night = id === 'today' && opts.h !== undefined && skyPhase(opts.h, opts.m || 0) === 'night';
  return `<div class="phone" data-phone data-screen="${id}" data-h="${opts.h ?? ''}" data-m="${opts.m ?? ''}">
    ${statusbar(night)}
    <div class="screen" data-scroll>${screenHTML(id, opts)}</div>
    ${pill()}${dock(id)}
    <div class="toast" role="status"><span class="ok">${I.check.replace('currentColor', '#fff')}</span><span class="msg"></span><button data-act="undo">撤销</button></div>
    ${opts.assistant ? assistantSheet() : ''}
    ${opts.detail ? detailView() : ''}
  </div>`;
}

/* =====================================================================
   组件板 & 动效板
   ===================================================================== */
function componentsBoard() {
  const sw = (c, n) => `<div class="sw" style="background:${c}"><span>${n}</span></div>`;
  return `<div class="board">
    <section class="panel"><h4>品牌与语义色</h4><p class="spec">品牌渐变只做装饰（进度、指示、插画），不放小字。正文与按钮用 <code>primary #2E6FE0</code>（白底 4.7:1）。</p>
      <div class="swatches">${sw('var(--grad-brand)', 'brand')}${sw('var(--grad-sun)', 'sun')}${sw('#2E6FE0', 'primary')}${sw('#EAF2FF', 'primarySoft')}${sw('#0F7F63', 'success')}${sw('#96620A', 'warning')}${sw('#C2412D', 'danger')}${sw('#142238', 'ink900')}${sw('#5B6B82', 'ink500')}${sw('#F3F7FC', 'bg')}${sw('#EEF3F9', 'sunken')}${sw('#E4ECF5', 'line')}</div></section>
    <section class="panel"><h4>课程色（8 组）+ 类型样式</h4><p class="spec">类型不只靠颜色：活动=白底描边，计划=虚线框+“计划”，考试=珊瑚底+“考试”。</p>
      <div class="palette-grid">${Object.entries(PAL).map(([k, p]) => `<div class="blk k-course" style="--bgc:${p[0]};--acc:${p[1]};--txt:${p[2]}"><span class="bt">${{ sky: '高等数学', mint: '数据结构', aqua: '线性代数', lilac: '大学英语', apricot: '程序设计', blossom: '大学物理', wheat: '体育', mist: '操作系统' }[k]}</span><span class="bl">A301</span></div>`).join('')}
        <div class="blk k-event"><span class="bt">组会</span><span class="bl">302</span></div><div class="blk k-plan"><span class="badge">计划</span><span class="bt">复习线代</span></div><div class="blk k-exam"><span class="badge">考试</span><span class="bt">大学物理</span></div></div></section>
    <section class="panel"><h4>字体阶梯</h4><p class="spec">系统字体；数字一律 <code>tabularFigures</code>。正文 16 起，支持 1.6 倍放大。</p>
      <div class="t-display">11月4日</div><div class="t-headline">第10周</div><div class="t-title">数据结构</div><div class="t-title-s">提交实验报告</div><div class="t-body">按已记录的日程查询空档</div><div class="t-body-s ink-500">A305 · 第5–6节</div><div class="row" style="margin-top:8px"><span class="t-num-xl">D-6</span><span class="t-num-l">14:00</span><span class="t-num-m">13:20–13:40</span></div></section>
    <section class="panel"><h4>按钮</h4><p class="spec">主按钮 48–52 高、圆角 16、按下缩放 0.97（90ms）+ 加深；一个场景只有一个主按钮。</p>
      <div class="demo"><div class="row"><button class="btn btn-primary">确认添加</button><button class="btn btn-tonal">查看任务</button><button class="btn btn-text">暂不添加</button></div><div class="row" style="margin-top:10px"><button class="btn btn-primary" disabled>保存</button><button class="btn btn-primary"><span class="spinner"></span>保存中</button><button class="icon-btn" aria-label="新建">${I.plus}</button></div></div></section>
    <section class="panel"><h4>截止与状态芯片</h4><p class="spec">颜色 + 图标 + 文字三重表达；“未定日期”不补造截止。</p>
      <div class="demo"><div class="row"><span class="chip chip-danger">${I.clock}今天 23:59</span><span class="chip chip-warning">${I.flag}11月6日</span><span class="chip chip-neutral">11月10日</span><span class="chip chip-neutral">方便时</span><span class="chip chip-primary">${I.cal}已安排 13:20</span><span class="chip chip-success">活动</span></div>
      <div class="row" style="margin-top:12px"><button class="chip chip-outline" aria-pressed="true">全部</button><button class="chip chip-outline">课程</button><button class="chip chip-outline">考试</button><button class="chip chip-outline">学习安排</button></div></div></section>
    <section class="panel"><h4>分段控件（弹簧指示）</h4><p class="spec">指示块用 <code>snappy</code> 弹簧（k520 c38），可被打断并保留速度；切换有 selectionClick 触感。</p>
      <div class="demo"><div class="seg" data-seg="demo"><span class="seg-ind"></span><button aria-selected="true" data-act="seg" data-i="0">待处理</button><button aria-selected="false" data-act="seg" data-i="1">已完成</button><button aria-selected="false" data-act="seg" data-i="2">已取消</button></div></div></section>
    <section class="panel"><h4>任务行：完成 → 划线 → 收起</h4><p class="spec">点圆钮先进入“保存中”，服务端确认后才打勾（pop 弹簧）、划线 220ms、收起 260ms，并给出撤销。</p>
      <div class="demo" style="padding:0;background:#fff">${taskRow({ id: 'c1', title: '提交实验报告', chip: `<span class="chip chip-danger">${I.clock}今天 23:59</span>`, src: '大学物理', rem: '还需 1 小时' })}<div class="swipe-wrap peek"><div class="under">${I.check}完成</div>${taskRow({ id: 'c2', title: '助学金申请（右滑完成）', chip: `<span class="chip chip-warning">${I.flag}11月6日</span>`, src: '', rem: '' })}</div></div>
      <button class="btn btn-text replay" data-act="reset-c">重置</button></section>
    <section class="panel"><h4>下一节卡 / 正在上课</h4><p class="spec">与天空头部重叠 40px，raised 阴影；进行中显示品牌渐变进度条与剩余分钟（滚动数字）。</p>
      <div class="demo">${nextCard().replace('margin:-40px 16px 0', '')}<article class="card-raised" style="margin-top:12px;padding:16px 18px;border-radius:20px"><div class="lead t-label ink-500" style="display:flex;gap:8px;align-items:center"><span class="now-dot"></span>正在上课 · 还剩 <span class="num">32</span> 分钟</div><div class="t-title" style="margin-top:6px">大学物理</div><div class="progress"><i style="width:68%"></i></div></article></div></section>
    <section class="panel"><h4>空档卡（GapSlotBar）</h4><p class="spec">虚线框=空档，任务块按时长占比；点“安排这项”先就地预览，保存后填充（380ms reveal）+ 勾。</p><div class="demo" style="padding:0 0 12px">${gapCard().replace('margin: var(--gap) 16px 0', '')}</div></section>
    <section class="panel"><h4>导航坞 + 助手胶囊</h4><p class="spec">玻璃材质（白 74% + 模糊 20）；下滑内容时胶囊收成麦克风圆钮（gentle 弹簧），上滑展开；长按麦克风直接说话。</p>
      <div class="mini-phone" style="height:190px">${pill()}${dock('today')}</div><button class="btn btn-text replay" data-act="toggle-pill">切换收起 / 展开</button></section>
    <section class="panel"><h4>空状态</h4><p class="spec">插画 + 一句事实 + 一个动作；不写励志句。</p>
      <div class="demo" style="text-align:center"><img src="${ASSET}/illustrations/empty-today.svg" alt="" style="width:200px;margin:0 auto"><div class="t-title-s" style="margin-top:8px">今天没有安排</div><div class="t-body-s ink-500" style="margin-top:2px">明天 08:00 有高等数学</div><button class="btn btn-tonal btn-sm" style="margin-top:12px">添加日程</button></div></section>
    <section class="panel"><h4>骨架屏</h4><p class="spec">加载时按真实布局占位，单一共享 shimmer（1200ms 线性）；减少动画时静止。</p>
      <div class="demo"><div class="row" style="gap:12px;flex-wrap:nowrap"><div class="skel" style="width:48px;height:48px;border-radius:14px;flex:none"></div><div style="flex:1"><div class="skel" style="height:14px;width:70%"></div><div class="skel" style="height:12px;width:45%;margin-top:10px"></div></div></div><div class="skel" style="height:80px;margin-top:14px;border-radius:16px"></div></div></section>
    <section class="panel"><h4>回执与撤销</h4><p class="spec">保存成功后才出现；浮动 16 圆角，底部 170px 避开导航坞；3 秒自动消失。</p>
      <div class="demo" style="height:88px"><div class="toast show" style="bottom:18px"><span class="ok">${I.check.replace('currentColor', '#fff')}</span><span class="msg">已完成 · 提交实验报告</span><button>撤销</button></div></div></section>
  </div>`;
}
function motionBoard() {
  const m = (title, spec, demo, act) => `<section class="panel"><h4>${title}</h4><p class="spec">${spec}</p><div class="demo">${demo}</div>${act ? `<button class="btn btn-tonal btn-sm replay" data-act="${act}">播放</button>` : ''}</section>`;
  return `<div class="board">
    ${m('① 日出入场', '每次启动 App 一次：太阳从地平线升到当前时刻位置，<code>520ms decelerate</code>；减少动画时直接到位。', `<div class="mini-phone" style="height:220px">${sky().replace('class="sky ', 'style="height:220px" class="sky ')}</div>`, 'm-sunrise')}
    ${m('② 页面切换 fade-through', '旧页 90ms 淡出 → 新页 260ms 淡入并从 0.98 放大到 1（<code>decelerate</code>）。保留各页滚动位置。', `<div class="mini-phone" data-m-fade style="display:grid;place-items:center"><div class="t-title">今日</div></div>`, 'm-fade')}
    ${m('③ 列表交错进入', '每项上移 12px + 淡入，<code>260ms</code>、间隔 <code>36ms</code>、最多 8 项；回到已看过的页面不重播。', `<div data-m-stagger>${TASKS.map(taskRow).join('')}</div>`, 'm-stagger')}
    ${m('④ 完成任务', '保存中（转圈）→ 打勾 <code>pop 弹簧 k420 c20</code> → 划线 220ms → 收起 260ms → 回执可撤销。', `<div class="card" data-m-complete>${taskRow({ id: 'm1', title: '提交实验报告', chip: `<span class="chip chip-danger">${I.clock}今天 23:59</span>`, src: '大学物理', rem: '还需 1 小时' })}</div>`, 'm-complete')}
    ${m('⑤ 数字滚动', '数字变化时逐位上下滚动 <code>260ms standard</code>，等宽数字避免抖动。', `<div style="display:flex;gap:16px;align-items:baseline"><span class="t-num-xl" data-m-roll>42</span><span class="ink-500">分钟后上课</span></div>`, 'm-roll')}
    ${m('⑥ 空档填充', '任务块宽度 0 → 占比，<code>380ms reveal</code>，随后小勾 pop。', `<div class="slot" data-m-slot style="margin:6px 0"><div class="fill"><span class="ok">${I.check.replace('currentColor', '#2E6FE0')}</span>整理实验数据 · 20 分钟</div></div>`, 'm-slot')}
    ${m('⑦ 现在标记', '每到整分钟只脉冲一次（光晕 1→1.8，900ms），不做无限循环。', `<div style="display:flex;align-items:center;gap:12px;height:40px"><span class="now-dot" data-m-now style="transform:scale(1.4)"></span><span class="t-num-m">13:18</span></div>`, 'm-now')}
    ${m('⑧ 弹簧指示器', '导航坞指示块 / 周次选中块：<code>snappy k520 c38</code>，轻微过冲后落定。', `<div class="mini-phone" style="height:96px">${dock('today')}</div>`, 'm-dock')}
    ${m('⑨ 容器变换', '课程块 → 课程详情：从块的位置与圆角展开成整页 <code>380ms standard</code>，内容随后交错进入；返回时收回原位。到“全部页面”的日程里点任一课程块体验。', `<div class="row"><div class="blk k-course" style="position:relative;left:0;right:0;width:84px;height:96px;--bgc:${PAL.mint[0]};--acc:${PAL.mint[1]};--txt:${PAL.mint[2]}"><span class="bt">数据结构</span><span class="bl">A305</span></div>${I.arrow.replace('<svg', '<svg width="28" height="28" style="color:var(--ink-400)"')}<div style="width:84px;height:120px;border-radius:14px;background:linear-gradient(180deg,${PAL.mint[0]},#F3F7FC);box-shadow:var(--sh-card)"></div></div>`)}
    ${m('⑩ 按住说话', '按住麦克风：圆钮轻呼吸 + 波形；松开完成，上滑取消（沿用现有手势）。', `<div class="row"><div class="ask" style="position:relative;right:auto;bottom:auto;width:100%" data-m-hold>${pill().replace(/^<div class="ask" data-pill>|<\/div>$/g, '')}</div></div>`, 'm-hold')}
  </div>`;
}

/* =====================================================================
   挂载
   ===================================================================== */
function mount() {
  installSprings();
  const app = $('#app');
  if (SHOT) document.body.classList.add('shot');
  const cap = (b, t) => `<div class="cap"><b>${b}</b>${t}</div>`;
  let stage = '';
  if (SHOT) {
    const map = {
      today: () => phone('today'), dawn: () => phone('today', { h: 6, m: 40 }), dusk: () => phone('today', { h: 17, m: 50 }), night: () => phone('today', { h: 21, m: 10 }),
      schedule: () => phone('schedule'), list: () => phone('schedule', { view: 'list' }), tasks: () => phone('tasks'), semester: () => phone('semester'),
      assistant: () => phone('today', { assistant: true }), detail: () => phone('schedule', { detail: true }),
    };
    stage = `<div class="stage">${(map[SHOT] || map.today)()}</div>`;
  } else if (VIEW === 'components') stage = componentsBoard();
  else if (VIEW === 'motion') stage = motionBoard();
  else stage = `<div class="stage">
      <div class="stage-item">${cap('今日', '天空随时间变化 · 下一节 · 空档 · 时间线')}${phone('today')}</div>
      <div class="stage-item">${cap('今日 · 夜间', '21:10，夜空 + 月亮')}${phone('today', { h: 21, m: 10 })}</div>
      <div class="stage-item">${cap('日程', '周课表，点课程块看容器变换')}${phone('schedule')}</div>
      <div class="stage-item">${cap('任务', '分组 · 完成动效 · 学习安排')}${phone('tasks')}</div>
      <div class="stage-item">${cap('学期', '地平线进度 · 周次弹簧选择')}${phone('semester')}</div>
      <div class="stage-item">${cap('助手', '解析通知 → 确认 → 回执')}${phone('today', { assistant: true })}</div>
    </div>`;
  app.innerHTML = `<div class="viewer"><header class="viewer-head"><h1><img src="${ICON_FALLBACK}" alt="">拾日 · 晴日 v2</h1><span class="sub">可交互高保真原型 · 匿名演示数据</span>
      <div class="time-scrub" title="拖动查看今日头部在一天中的变化">今日时间<input type="range" min="0" max="1439" value="${NOW.h * 60 + NOW.m}" data-scrub><b class="num" data-scrub-v>13:18</b></div>
      <nav class="viewer-tabs">${[['screens', '全部页面'], ['components', '组件'], ['motion', '动效']].map(([v, l]) => `<button aria-pressed="${VIEW === v}" onclick="location.search='?view=${v}'">${l}</button>`).join('')}</nav></header>${stage}</div>`;

  // 打开状态
  $$('[data-phone]').forEach(p => {
    if ($('.sheet', p)) { requestAnimationFrame(() => { $('.scrim', p).classList.add('show'); $('.sheet', p).classList.add('open'); }); setTimeout(() => { const c = $('.convo', p); c.scrollTop = c.scrollHeight; }, 60); }
    if ($('[data-detail]', p)) requestAnimationFrame(() => $('[data-detail]', p).classList.add('open'));
  });
  layoutIndicators(document);
  bindScroll();
  scheduleMinutePulse();
}

/* 指示块位置（dock / segmented / weeks）*/
function layoutIndicators(root) {
  $$('.dock', root).forEach(d => {
    const cur = $('[aria-current="page"]', d) || $('button', d); const ind = $('.ind', d);
    const x = cur.offsetLeft + (cur.offsetWidth - 56) / 2; ind.style.transform = `translateX(${x}px)`;
  });
  $$('.seg', root).forEach(s => {
    const btns = $$('button', s); const i = Math.max(0, btns.findIndex(b => b.getAttribute('aria-selected') === 'true'));
    const pill = $('.seg-ind', s); const w = (s.clientWidth - 8) / btns.length; pill.style.width = `${w}px`; pill.style.transform = `translateX(${i * w}px)`;
  });
  $$('[data-weeks]', root).forEach(ws => {
    const sel = $('.wk.sel', ws); const pill = $('.selpill', ws); pill.style.transform = `translateX(${sel.offsetLeft}px)`;
    if (!SHOT || true) ws.scrollLeft = sel.offsetLeft - ws.clientWidth / 2 + 26;
  });
}

/* 滚动收起助手胶囊 */
function bindScroll() {
  $$('[data-phone]').forEach(p => {
    const sc = $('[data-scroll]', p); const pl = $('[data-pill]', p); if (!sc || !pl) return; let last = 0;
    sc.addEventListener('scroll', () => { const y = sc.scrollTop; if (y > last + 4 && y > 80) pl.classList.add('collapsed'); else if (y < last - 4) pl.classList.remove('collapsed'); last = y; }, { passive: true });
  });
}

/* 整分钟脉冲 */
function scheduleMinutePulse() {
  const fire = () => { $$('.now-dot').forEach(d => { d.classList.remove('pulse'); void d.offsetWidth; d.classList.add('pulse'); }); };
  const ms = 60000 - (Date.now() % 60000); setTimeout(() => { fire(); setInterval(fire, 60000); }, ms);
}

/* 数字滚动 */
function rollTo(el, value) {
  const str = String(value); el.setAttribute('aria-label', str);
  if (!el.dataset.built) { el.dataset.built = '1'; el.style.display = 'inline-flex'; el.style.overflow = 'hidden'; el.style.height = '1.15em'; el.style.lineHeight = '1.15em'; }
  const prev = el.textContent; el.innerHTML = str.split('').map((ch) => /\d/.test(ch) ? `<span style="display:inline-block;height:1.15em;overflow:hidden"><span style="display:flex;flex-direction:column;transition:transform var(--d-std) var(--ease-standard);transform:translateY(-${(+prev.slice(-1) || 0) * 1.15}em)">${'0123456789'.split('').map(d => `<span style="height:1.15em">${d}</span>`).join('')}</span></span>` : ch).join('');
  requestAnimationFrame(() => requestAnimationFrame(() => $$(':scope > span > span', el).forEach((col, i) => { col.style.transform = `translateY(-${(+str[i]) * 1.15}em)`; })));
}

/* =====================================================================
   交互
   ===================================================================== */
const undoStack = new WeakMap();
function toast(p, msg, onUndo) {
  const t = $('.toast', p); if (!t) return; $('.msg', t).textContent = msg; t.classList.add('show'); undoStack.set(t, onUndo);
  clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove('show'), 3200);
}
function completeRow(row) {
  const chk = $('.check', row); if (!chk || chk.classList.contains('pending') || chk.classList.contains('done')) return;
  chk.classList.add('pending');
  setTimeout(() => {                          // 模拟服务端确认
    chk.classList.remove('pending'); chk.classList.add('done'); row.classList.add('is-done');
    if (navigator.vibrate) navigator.vibrate(8);
    setTimeout(() => {
      const p = row.closest('[data-phone]'); const parent = row.parentNode; const next = row.nextSibling;
      row.classList.add('collapsing');
      setTimeout(() => {
        row.remove();
        if (p) toast(p, `已完成 · ${$('.strike', row).textContent}`, () => {
          row.classList.remove('collapsing', 'is-done'); chk.classList.remove('done'); row.style.animation = 'fadeUp var(--d-std) var(--ease-decel)'; parent.insertBefore(row, next);
        });
      }, 270);
    }, 620);
  }, 650);
}
function moveSeg(btn) {
  const s = btn.closest('.seg'); const btns = $$('button', s); const i = btns.indexOf(btn);
  btns.forEach(b => b.setAttribute('aria-selected', String(b === btn)));
  const w = (s.clientWidth - 8) / btns.length; $('.seg-ind', s).style.transform = `translateX(${i * w}px)`;
  if (s.dataset.seg === 'sched') { const body = btn.closest('[data-phone]').querySelector('[data-sched-body]'); body.classList.remove('enter'); void body.offsetWidth; body.innerHTML = i === 0 ? scheduleGrid() : agenda(); body.classList.add('enter'); }
}
function switchTab(btn) {
  const p = btn.closest('[data-phone]'); if (!p) { const d = btn.closest('.dock'); $$('button', d).forEach(b => b.toggleAttribute('aria-current', b === btn)); if (btn.hasAttribute('aria-current')) btn.setAttribute('aria-current', 'page'); layoutIndicators(d.parentNode); return; }
  const id = btn.dataset.tab; const sc = $('[data-scroll]', p);
  sc.style.transition = 'opacity 90ms var(--ease-accel)'; sc.style.opacity = '0';
  setTimeout(() => {
    sc.innerHTML = screenHTML(id); sc.scrollTop = 0; sc.style.transition = ''; sc.style.opacity = '';
    sc.classList.remove('enter'); void sc.offsetWidth; sc.classList.add('enter');
    p.dataset.screen = id; $('.dock', p).outerHTML = dock(id); $('[data-pill]', p).classList.remove('collapsed');
    layoutIndicators(p);
  }, 90);
}
function openDetail(blk) {
  const p = blk.closest('[data-phone]'); if (!p) return;
  const pr = p.getBoundingClientRect(), br = blk.getBoundingClientRect();
  const pal = PAL[blk.dataset.pal] || (blk.dataset.kind === 'exam' ? ['#FDECE8', '#F0705A', '#B03A26'] : blk.dataset.kind === 'plan' ? ['#EAF2FF', '#4A90F0', '#1D5BB5'] : ['#E4F6EF', '#3DBE8B', '#0F7656']);
  const mo = document.createElement('div'); mo.className = 'morph';
  Object.assign(mo.style, { left: `${br.left - pr.left}px`, top: `${br.top - pr.top}px`, width: `${br.width}px`, height: `${br.height}px`, background: pal[0] });
  p.appendChild(mo); blk.style.visibility = 'hidden';
  requestAnimationFrame(() => requestAnimationFrame(() => Object.assign(mo.style, { left: '0px', top: '0px', width: `${pr.width}px`, height: `${pr.height}px`, borderRadius: '0px' })));
  const old = $('[data-detail]', p); if (old) old.remove();
  p.insertAdjacentHTML('beforeend', detailView(blk.dataset.title, blk.dataset.room, blk.dataset.pal || 'mint'));
  const dv = $('[data-detail]', p); dv.style.setProperty('--bgc', pal[0]); dv.style.setProperty('--txt', pal[2]);
  setTimeout(() => { dv.classList.add('open'); setTimeout(() => mo.remove(), 260); }, 300);
  dv._from = { blk, br: { l: br.left - pr.left, t: br.top - pr.top, w: br.width, h: br.height }, bg: pal[0] };
}
function closeDetail(btn) {
  const p = btn.closest('[data-phone]'); const dv = $('[data-detail]', p); const f = dv._from;
  if (!f) { dv.classList.remove('open'); return; }
  const mo = document.createElement('div'); mo.className = 'morph'; const pr = p.getBoundingClientRect();
  Object.assign(mo.style, { left: '0px', top: '0px', width: `${pr.width}px`, height: `${pr.height}px`, borderRadius: '0px', background: f.bg, zIndex: 72 });
  p.appendChild(mo); dv.classList.remove('open');
  requestAnimationFrame(() => requestAnimationFrame(() => Object.assign(mo.style, { left: `${f.br.l}px`, top: `${f.br.t}px`, width: `${f.br.w}px`, height: `${f.br.h}px`, borderRadius: '11px' })));
  setTimeout(() => { mo.remove(); f.blk.style.visibility = ''; dv.remove(); }, 400);
}
function openAssistant(el) {
  const p = el.closest('[data-phone]'); if (!p) return;
  if (!$('.sheet', p)) p.insertAdjacentHTML('beforeend', assistantSheet());
  requestAnimationFrame(() => requestAnimationFrame(() => { $('.scrim', p).classList.add('show'); $('.sheet', p).classList.add('open'); }));
}
function closeAssistant(el) { const p = el.closest('[data-phone]'); $('.scrim', p).classList.remove('show'); $('.sheet', p).classList.remove('open'); }
function confirmAdd(btn) {
  const card = btn.closest('[data-parse]'); const h = card.offsetHeight; card.style.height = `${h}px`; card.style.overflow = 'hidden';
  btn.innerHTML = '<span class="spinner"></span>'; btn.disabled = true;
  setTimeout(() => {
    requestAnimationFrame(() => { card.style.height = '0px'; card.style.opacity = '0'; card.style.marginTop = '-12px'; });
    setTimeout(() => { card.insertAdjacentHTML('afterend', `<div class="receipt"><span class="ok">${I.check.replace('currentColor', '#fff')}</span>已添加 开会<span class="sp"></span><button>查看</button><button>撤销</button></div>`); card.remove(); }, 380);
  }, 520);
}
function weekSelect(btn) {
  const ws = btn.closest('[data-weeks]'); $$('.wk', ws).forEach(b => b.classList.toggle('sel', b === btn));
  $('.selpill', ws).style.transform = `translateX(${btn.offsetLeft}px)`;
  const body = ws.parentNode.querySelector('[data-wkbody]'); const w = +btn.dataset.w; const d0 = new Date(2026, 7, 31 + (w - 1) * 7), d1 = new Date(d0.getTime() + 6 * 864e5);
  body.style.transition = 'opacity 90ms'; body.style.opacity = '.0';
  setTimeout(() => { $('.range .t-title', body).textContent = `${d0.getMonth() + 1}月${d0.getDate()}日 – ${d1.getMonth() + 1}月${d1.getDate()}日`; body.style.transition = 'opacity var(--d-std) var(--ease-decel)'; body.style.opacity = '1'; }, 100);
}
function setSkyTime(mins) {
  const h = Math.floor(mins / 60), m = mins % 60; $('[data-scrub-v]').textContent = fmt(h, m);
  $$('[data-sky]').forEach(sk => {
    const p = sk.closest('[data-phone]'); if (p && p.dataset.h !== '') return; // 固定时间的展示屏不跟随
    const tmp = document.createElement('div'); tmp.innerHTML = sky(h, m); const n = tmp.firstElementChild; $('.sun', n).classList.remove('rise');
    sk.replaceWith(n); const sb = p && $('.statusbar', p); if (sb) sb.classList.toggle('on-dark', skyPhase(h, m) === 'night');
  });
}

document.addEventListener('click', (e) => {
  const a = e.target.closest('[data-act]'); if (!a) return; const act = a.dataset.act;
  if (act === 'complete') completeRow(a.closest('.task-row'));
  else if (act === 'seg') moveSeg(a);
  else if (act === 'tab') switchTab(a);
  else if (act === 'open-detail') openDetail(a);
  else if (act === 'close-detail') closeDetail(a);
  else if (act === 'open-assistant') openAssistant(a);
  else if (act === 'close-assistant') closeAssistant(a);
  else if (act === 'confirm-add') confirmAdd(a);
  else if (act === 'week') weekSelect(a);
  else if (act === 'arrange') a.closest('[data-gap]').classList.add('previewing');
  else if (act === 'save-plan') { const g = a.closest('[data-gap]'); g.classList.remove('previewing'); $('[data-slot]', g).classList.add('filled'); g.classList.add('done'); }
  else if (act === 'undo-plan') { const g = a.closest('[data-gap]'); g.classList.remove('done'); $('[data-slot]', g).classList.remove('filled'); }
  else if (act === 'undo') { const t = a.closest('.toast'); const fn = undoStack.get(t); if (fn) fn(); t.classList.remove('show'); }
  else if (act === 'toggle-pill') a.parentNode.querySelector('[data-pill]').classList.toggle('collapsed');
  else if (act === 'reset-c') location.reload();
  else if (act === 'm-sunrise') { const s = a.parentNode.querySelector('.sun'); s.classList.remove('rise'); void s.offsetWidth; s.classList.add('rise'); }
  else if (act === 'm-fade') { const b = a.parentNode.querySelector('[data-m-fade]'); const t = $('.t-title', b); b.style.transition = 'opacity 90ms var(--ease-accel)'; b.style.opacity = 0; setTimeout(() => { t.textContent = t.textContent === '今日' ? '日程' : '今日'; b.style.transition = ''; b.style.opacity = ''; b.classList.remove('enter'); void b.offsetWidth; b.classList.add('enter'); }, 90); }
  else if (act === 'm-stagger') { const b = a.parentNode.querySelector('[data-m-stagger]'); b.classList.remove('stagger'); $$('.task-row', b).forEach((r, i) => r.setAttribute('style', `animation-delay:${i * 36}ms`)); void b.offsetWidth; b.classList.add('stagger'); }
  else if (act === 'm-complete') { const b = a.parentNode.querySelector('[data-m-complete]'); b.innerHTML = taskRow({ id: 'm1', title: '提交实验报告', chip: `<span class="chip chip-danger">${I.clock}今天 23:59</span>`, src: '大学物理', rem: '还需 1 小时' }); setTimeout(() => completeRow($('.task-row', b)), 60); }
  else if (act === 'm-roll') { const el = a.parentNode.querySelector('[data-m-roll]'); const v = (+el.getAttribute('aria-label') || 42) - 1; rollTo(el, v < 10 ? 42 : v); }
  else if (act === 'm-slot') { const s = a.parentNode.querySelector('[data-m-slot]'); s.classList.remove('filled'); void s.offsetWidth; s.classList.add('filled'); }
  else if (act === 'm-now') { const d = a.parentNode.querySelector('[data-m-now]'); d.classList.remove('pulse'); void d.offsetWidth; d.classList.add('pulse'); }
  else if (act === 'm-dock') { const d = a.parentNode.querySelector('.dock'); const btns = $$('button', d); const cur = btns.findIndex(b => b.hasAttribute('aria-current')); const nx = btns[(cur + 1) % 4]; btns.forEach(b => b.removeAttribute('aria-current')); nx.setAttribute('aria-current', 'page'); layoutIndicators(d.parentNode); }
  else if (act === 'm-hold') { const h = a.parentNode.querySelector('[data-m-hold]'); h.classList.add('holding'); setTimeout(() => h.classList.remove('holding'), 1800); }
});
// 按住说话
document.addEventListener('pointerdown', (e) => { const h = e.target.closest('[data-hold]'); if (!h) return; const box = h.closest('.composer .box') || h.closest('.ask'); box && box.classList.add('holding'); h.closest('.composer') && h.closest('.composer').classList.add('holding'); });
document.addEventListener('pointerup', () => $$('.holding').forEach(x => x.classList.remove('holding')));
document.addEventListener('input', (e) => { if (e.target.matches('[data-scrub]')) setSkyTime(+e.target.value); });
window.addEventListener('resize', () => layoutIndicators(document));

mount();
// 每分钟让“下一节”倒计时真实滚动（演示）
setInterval(() => $$('.roll[data-roll="42"]').forEach(el => rollTo(el, Math.max(1, (+el.getAttribute('aria-label') || 42) - 1))), 60000);
window.__SHIRI__ = { completeRow, openDetail, openAssistant, setSkyTime };
})();
