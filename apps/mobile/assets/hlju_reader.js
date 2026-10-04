// The extractor is deliberately self-contained: it can be invoked read-only in
// an already logged-in browser without looking at credentials or Vue state.
function hljuExtractDom(doc) {
  function text(node) {
    return String(node && (node.innerText || node.textContent) || '').replace(/\r/g, '').trim();
  }
  function nodes(root, selector) {
    return root && root.querySelectorAll ? root.querySelectorAll(selector) : [];
  }
  function cleanClock(value) {
    const match = /^(\d{1,2}):(\d{2})$/.exec(value);
    if (!match || +match[1] > 23 || +match[2] > 59) return null;
    return match[1].padStart(2, '0') + ':' + match[2];
  }
  const tables = nodes(doc, '.ivu-table');
  let table = null;
  let weekdays = null;
  const names = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  for (let i = 0; i < tables.length; i++) {
    const heads = nodes(tables[i], '.ivu-table-header th');
    const mapping = {};
    let count = 0;
    for (let j = 0; j < heads.length; j++) {
      const label = text(heads[j]).replace(/\s/g, '').replace('星期天', '星期日');
      for (let day = 0; day < names.length; day++) {
        if (label.includes(names[day])) { mapping[j] = day + 1; count++; break; }
      }
    }
    if (count === 7) { table = tables[i]; weekdays = mapping; break; }
  }
  if (!table) throw new Error('请打开个人课表，并选择要导入的学期');
  let title = '';
  const termNodes = nodes(doc, '.coursehead-xqkcblist-tit,.ivu-drawer-header-inner,.ivu-drawer-header,.ivu-modal-header-inner,.ivu-table-title,.ivu-card-head p,h1,h2,h3,h4,[class*="title"]');
  for (let i = 0; i < termNodes.length; i++) {
    const match = /(\d{4})\s*[-—–]\s*(\d{4})\s*(?:学年)?\s*第?([一二三123])学期(?:\s*课表)?/.exec(text(termNodes[i]));
    if (match) { title = match[0]; break; }
  }
  const selected = /(\d{4})\s*[-—–]\s*(\d{4})\s*(?:学年)?\s*第?([一二三123])学期/.exec(title);
  const termValues = {'一': '1', '二': '2', '三': '3', '1': '1', '2': '2', '3': '3'};
  const result = {
    sourceTerm: title,
    rows: [],
    metadata: {source: 'dom'},
    warnings: [],
  };
  if (selected && +selected[2] === +selected[1] + 1) {
    result.year = selected[1] + '-' + selected[2];
    result.term = termValues[selected[3]];
  } else {
    result.warnings.push('未读取到学年学期，请核对后保存');
  }
  const seen = new Set();
  const bodyRows = nodes(table, '.ivu-table-body tbody tr');
  for (let i = 0; i < bodyRows.length; i++) {
    const cells = nodes(bodyRows[i], 'td');
    const timeText = text(cells[0]);
    const timeMatches = timeText.match(/\d{1,2}:\d{2}/g) || [];
    for (let j = 0; j < cells.length; j++) {
      const day = weekdays[j];
      if (!day) continue;
      const cards = nodes(cells[j], '.codedd-wrap');
      for (let k = 0; k < cards.length; k++) {
        const raw = text(cards[k]);
        if (!raw) continue;
        const isRemark = /^备注\s*[:：]?$/.test(timeText);
        const identity = (isRemark ? 'bz' : day) + '\n' + raw;
        if (seen.has(identity)) continue;
        seen.add(identity);
        const row = isRemark ? {raw_text: raw, key: 'bz'} : {raw_text: raw, weekday: day};
        // This is a full displayed block. Do not fabricate intermediate periods.
        if (!isRemark && !/【[^】]*考试[^】]*】/.test(raw) && timeMatches.length >= 2) {
          const start = cleanClock(timeMatches[0]);
          const end = cleanClock(timeMatches[timeMatches.length - 1]);
          if (start && end && end > start) { row.start_time = start; row.end_time = end; }
        }
        result.rows.push(row);
      }
    }
  }
  const remarks = nodes(table, '.ivu-table-footer .codedd-wrap,.ivu-table-summary .codedd-wrap');
  for (let i = 0; i < remarks.length; i++) {
    const raw = text(remarks[i]);
    if (!raw || seen.has('bz\n' + raw)) continue;
    seen.add('bz\n' + raw);
    result.rows.push({key: 'bz', raw_text: raw});
  }
  if (!result.rows.length) throw new Error('没有读取到课表，请先查询个人课表；原课表保持不变');
  if (result.rows.length > 600) throw new Error('课程条目超过本次读取上限');
  return result;
}

async function hljuRead(nonce) {
  function send(kind, value) {
    SemesterImport.postMessage(JSON.stringify({nonce, kind, value}));
  }
  async function query(path, params) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 12000);
    try {
      const response = await fetch(new URL(path, location.origin), {
        method: params ? 'POST' : 'GET',
        credentials: 'same-origin',
        signal: controller.signal,
        headers: params ? {'Content-Type': 'application/x-www-form-urlencoded', 'X-Requested-With': 'XMLHttpRequest'} : {'X-Requested-With': 'XMLHttpRequest'},
        body: params ? new URLSearchParams(params).toString() : undefined,
      });
      if (!response.ok) throw new Error('教务查询未成功');
      return await response.json();
    } finally { clearTimeout(timer); }
  }
  function applyTimes(rows, data) {
    if (!Array.isArray(data)) return [];
    const periods = [];
    for (let i = 0; i < data.length; i++) {
      const p = data[i];
      if (!p || typeof p !== 'object') continue;
      const day = +p.XQJ, section = +p.XJ;
      const start = String(p.KSSJ || '').trim(), end = String(p.JSSJ || '').trim();
      if (!(day >= 1 && day <= 7 && section >= 1 && section <= 30) || !/^\d{1,2}:\d{2}$/.test(start) || !/^\d{1,2}:\d{2}$/.test(end)) continue;
      periods.push({weekday: day, section, start, end});
    }
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      if (!row.weekday || /【[^】]*考试[^】]*】/.test(row.raw_text)) continue;
      const section = /第\s*(\d+)(?:\s*-\s*(\d+))?\s*节/.exec(row.raw_text);
      const first = +(row.section_start || (section && section[1]));
      const last = +(row.section_end || (section && (section[2] || section[1])));
      let start = null, end = null;
      for (let j = 0; j < periods.length; j++) {
        if (periods[j].weekday !== row.weekday) continue;
        if (periods[j].section === first) start = periods[j].start;
        if (periods[j].section === last) end = periods[j].end;
      }
      if (start && end) {
        if (!row.start_time) row.start_time = start;
        if (!row.end_time) row.end_time = end;
      }
    }
    return periods;
  }
  try {
    if (window !== window.top || location.hostname !== 'xsxk.hlju.edu.cn') {
      throw new Error('请登录黑龙江大学本科教务，并打开个人课表');
    }
    const result = hljuExtractDom(document);
    if (result.year && result.term) {
      // Course API bodies have not been calibrated against this school. Keep
      // the verified visible table as primary data; auxiliary requests only
      // supplement its metadata, concurrently within one bounded wait.
      const metadata = await Promise.allSettled([
        query('/component/queryJieCiInfoXqj'),
        query('/component/queryRlZcSj', {xn: result.year, xq: result.term, djz: '1'}),
      ]);
      const periods = metadata[0].status === 'fulfilled'
        ? applyTimes(result.rows, metadata[0].value) : [];
      if (periods.length) {
        result.metadata.periods = periods;
        result.metadata.source = 'dom_with_metadata';
      } else {
        result.warnings.push('未读取到完整节次时间，请核对作息时间');
      }
      if (metadata[1].status === 'fulfilled') {
        const data = metadata[1].value;
        if (data && Array.isArray(data.content)) {
          for (let i = 0; i < data.content.length; i++) {
            const entry = data.content[i];
            if (entry && +entry.xqj === 1 && /^\d{4}-\d{2}-\d{2}$/.test(String(entry.rq))) {
              result.first_monday = String(entry.rq); break;
            }
          }
        }
      }
      if (result.first_monday) {
        result.metadata.source = 'dom_with_metadata';
      } else {
        result.warnings.push('未读取到第一周日期，请手动核对');
      }
    }
    send('courses', result);
  } catch (e) {
    send('error', e instanceof SyntaxError ? '教务会话可能已失效，请重新打开个人课表' : e.message || '课表读取未完成');
  }
}

async function semesterRead(nonce) { return hljuRead(nonce); }
