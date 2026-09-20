const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../assets/haut_reader.js'), 'utf8');
const sample = {
  kcmc: 'Synthetic course', xm: 'Synthetic teacher', cdmc: 'Room A',
  xqj: '3', zcd: '1-5周(单)', jc: '1-2节', jcs: '0102', jxb_id: 'synthetic-class',
  student_id: 'must-not-cross-bridge', password: 'must-not-cross-bridge',
};

async function read({ legacyFilter = false, rows = [sample] } = {}) {
  const messages = [];
  const context = vm.createContext({
    URL, URLSearchParams,
    location: { origin: 'https://jwglxt.haut.edu.cn', pathname: '/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html', href: 'https://jwglxt.haut.edu.cn/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151' },
    document: { querySelector(selector) {
      if (selector.startsWith('#xnm')) return { value: '2026', selectedOptions: [{ textContent: '2026-2027' }] };
      if (selector.startsWith('#xqm')) return { value: '3', selectedOptions: [{ textContent: '1' }] };
      return null;
    } },
    fetch: async () => ({ ok: true, json: async () => ({ kbList: rows }) }),
    SemesterImport: { postMessage(message) { messages.push(JSON.parse(message)); } },
  });
  vm.runInContext('window = globalThis; window.top = window;', context);
  if (legacyFilter) {
    // Reproduce the observed legacy callback order: (index, value, array).
    vm.runInContext(`Array.prototype.filter = function (callback, thisArg) {
      const result = [];
      for (let i = 0; i < this.length; i++) {
        if (callback.call(thisArg, i, this[i], this)) result.push(this[i]);
      }
      return result;
    };`, context);
  }
  await vm.runInContext(`${source}\nsemesterRead('synthetic-nonce');`, context);
  assert.equal(messages.length, 1);
  return messages[0];
}

test('normal page returns approved fields and selected term', async () => {
  const result = await read();
  assert.equal(result.kind, 'courses');
  assert.equal(result.value.sourceTerm, '2026-2027 1');
  assert.equal(result.value.rows[0].kcmc, sample.kcmc);
  assert.equal(result.value.rows[0].xqj, '3');
  assert.equal(result.value.rows[0].student_id, undefined);
  assert.equal(result.value.rows[0].password, undefined);
});

test('school override of Array.filter must not strip course fields', async () => {
  const result = await read({ legacyFilter: true });
  assert.equal(result.kind, 'courses');
  assert.equal(result.value.rows[0].kcmc, sample.kcmc);
  assert.equal(result.value.rows[0].xqj, '3');
  assert.equal(result.value.rows[0].zcd, '1-5周(单)');
  assert.equal(result.value.rows[0].jc, '1-2节');
  assert.equal(result.value.rows[0].student_id, undefined);
});

test('malformed course rows produce an explicit error instead of empty records', async () => {
  const result = await read({ rows: [null] });
  assert.equal(result.kind, 'error');
  assert.match(result.value, /第1条/);
});
