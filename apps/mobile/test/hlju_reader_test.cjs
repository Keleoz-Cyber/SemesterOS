const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../assets/hlju_reader.js'), 'utf8');

function timetable() {
  const course = '（免听）课程甲【004】\n[教师甲]\n[1-13周][教学楼-436]\n第5-6节';
  const exam = '【26秋随堂结课考试（120分钟）考试】\n课程乙\n10月25日\n15:40-17:40';
  const node = text => ({innerText: text, textContent: text});
  function row(raw, day, time = '') {
    const cells = Array.from({length: 8}, (_, i) => ({
      ...node(i === 0 ? time : ''),
      querySelectorAll: selector => selector === '.codedd-wrap' && i === day ? [node(raw)] : [],
    }));
    return {querySelectorAll: selector => selector === 'td' ? cells : []};
  }
  const table = {
    querySelectorAll(selector) {
      if (selector === '.ivu-table-header th') return [node('时间'), ...'一二三四五六日'.split('').map(d => node('星期' + d))];
      if (selector === '.ivu-table-body tbody tr') return [row(course, 2, '第5-6节\n13:30-15:05'), row(course, 2, '第5-6节\n13:30-15:05'), row(exam, 7), row('实践甲 [1-16周] 教师甲 备注:无', 1, '备注')];
      return [];
    },
  };
  return {
    querySelectorAll(selector) {
      if (selector === '.ivu-table') return [table];
      if (selector.includes('.coursehead-xqkcblist-tit')) return [node('2026-2027第一学期 课表')];
      return [];
    },
    createElement() {
      return {set innerHTML(value) {this.textContent = value.replace(/<[^>]*>/g, '');}};
    },
  };
}

function context(extra = {}) {
  const ctx = vm.createContext({document: timetable(), URL, URLSearchParams, AbortController, setTimeout, clearTimeout, ...extra});
  vm.runInContext('window = globalThis; window.top = window;', ctx);
  vm.runInContext(source, ctx);
  return ctx;
}

test('read-only DOM extractor handles exempt cards, mirrors and exams separately', () => {
  const result = JSON.parse(JSON.stringify(vm.runInContext('hljuExtractDom(document)', context())));
  assert.equal(result.rows.length, 3);
  assert.equal(result.sourceTerm, '2026-2027第一学期 课表');
  assert.equal(result.term, '1');
  assert.equal(result.rows[0].weekday, 2);
  assert.equal(result.rows[0].start_time, '13:30');
  assert.equal(result.rows[0].end_time, '15:05');
  assert.equal(result.rows[1].start_time, undefined);
  assert.equal(result.rows[2].key, 'bz');
  assert.equal(result.rows[2].weekday, undefined);
});

test('metadata queries retain verified DOM content and restrict exported fields', async () => {
  const messages = [];
  const calls = [];
  const ctx = context({
    location: {hostname: 'xsxk.hlju.edu.cn', origin: 'http://xsxk.hlju.edu.cn'},
    SemesterImport: {postMessage: v => messages.push(JSON.parse(v))},
    fetch: async (url, options) => {
      calls.push({path: url.pathname, body: options.body});
      let data;
      if (url.pathname.endsWith('queryKbjg')) {
        assert.equal(options.body, 'xn=2026-2027&xq=1&pylx=1');
        data = {code: 200, content: [{xj:'5',kssj:'13:35',jssj:'14:20',djms:'第5-6节',password:'private',student_id:'private'}, {xj:'6',kssj:'14:30',jssj:'15:15'}, {xj:'14',kssj:'11:56',jssj:'13:29'}]};
      } else {
        assert.equal(url.pathname, '/component/queryRlZcSj');
        data = {content: [{xqj: 1, rq: '2026-08-24'}]};
      }
      return {ok: true, json: async () => data};
    },
  });
  await vm.runInContext("semesterRead('test-nonce')", ctx);
  const packet = messages[0];
  assert.equal(packet.kind, 'courses');
  assert.equal(packet.nonce, 'test-nonce');
  assert.equal(calls.length, 2);
  assert.equal(calls[1].body, 'xn=2026-2027&xq=1&djz=1');
  assert.equal(packet.value.rows[0].start_time, '13:30');
  assert.equal(packet.value.rows[0].end_time, '15:05');
  assert.equal(packet.value.rows[0].password, undefined);
  assert.equal(packet.value.rows[0].student_id, undefined);
  assert.equal(packet.value.first_monday, '2026-08-24');
  assert.match(packet.value.rows[0].raw_text, /^（免听）/);
  assert.equal(packet.value.metadata.source, 'dom_with_metadata');
  assert.equal(packet.value.metadata.periods[0].start, '13:35');
  assert.equal(packet.value.metadata.periods_scope, 'shared_week');
  assert.equal(packet.value.metadata.periods[2].section, 14);
  assert.equal(packet.value.metadata.periods[0].weekday, undefined);
  assert.equal(packet.value.metadata.periods[0].password, undefined);
  assert.equal(JSON.stringify(packet).includes('private'), false);
  assert.equal(packet.value.rows.length, 3);
  assert.match(packet.value.rows[1].raw_text, /考试/);
  assert.equal(packet.value.rows[2].key, 'bz');
});

test('failed metadata queries preserve visible timetable with a calendar warning', async () => {
  const messages = [];
  const ctx = context({
    location: {hostname: 'xsxk.hlju.edu.cn', origin: 'http://xsxk.hlju.edu.cn'},
    SemesterImport: {postMessage: v => messages.push(JSON.parse(v))},
    fetch: async () => ({ok: false}),
  });
  await vm.runInContext("semesterRead('test-nonce')", ctx);
  assert.equal(messages[0].kind, 'courses');
  assert.equal(messages[0].value.rows.length, 3);
  assert.equal(messages[0].value.metadata.source, 'dom');
  assert.equal(messages[0].value.rows[0].start_time, '13:30');
  assert.equal(messages[0].value.rows[0].end_time, '15:05');
  assert.ok(messages[0].value.warnings.includes('未读取到第一周日期，请手动核对'));
});
