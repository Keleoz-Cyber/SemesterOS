async function semesterRead(nonce) {
  function send(kind, value) {
    SemesterImport.postMessage(JSON.stringify({nonce, kind, value}));
  }
  try {
    if (window !== window.top || location.origin !== 'https://jwglxt.haut.edu.cn' || !location.pathname.includes('/kbcx/')) {
      throw new Error('请先登录，并进入信息查询中的个人课表查询页面');
    }
    const year = document.querySelector('#xnm,[name="xnm"]')?.value;
    const term = document.querySelector('#xqm,[name="xqm"]')?.value;
    if (!year || !term) throw new Error('没有找到学年学期，请先在课表页选择学期并查询');
    const params = new URLSearchParams({xnm: year, xqm: term});
    const csrf = document.querySelector('[name="csrftoken"]')?.value;
    if (csrf) params.set('csrftoken', csrf);
    const target = new URL('/jwglxt/kbcx/xskbcx_cxXsKb.html', location.origin);
    const module = new URL(location.href).searchParams.get('gnmkdm');
    if (module) target.searchParams.set('gnmkdm', module);
    const response = await fetch(target, {method: 'POST', credentials: 'same-origin',
      headers: {'Content-Type': 'application/x-www-form-urlencoded', 'X-Requested-With': 'XMLHttpRequest'}, body: params.toString()});
    if (!response.ok) throw new Error('教务查询未成功，请在原页面重新查询后再试');
    const data = await response.json();
    if (!Array.isArray(data.kbList)) throw new Error('返回内容不是已适配的课表格式，请保留原页面核对');
    if (data.kbList.length > 300) throw new Error('课表条目超过本次读取上限，请核对所选范围');
    const allow = ['kcmc', 'xm', 'cdmc', 'xqj', 'zcd', 'jc', 'jcs', 'jxb_id', 'kch_id'];
    const rows = [];
    // The school replaces Array.prototype.filter with an index-first callback.
    // Use indexed loops instead of page-owned map/filter/fromEntries helpers.
    for (let i = 0; i < data.kbList.length; i++) {
      const source = data.kbList[i];
      if (source === null || typeof source !== 'object' || Array.isArray(source)) {
        throw new Error(`第${i + 1}条课程格式无法确认，未跳过该条课程`);
      }
      const row = {};
      for (let j = 0; j < allow.length; j++) {
        const key = allow[j];
        if (Object.prototype.hasOwnProperty.call(source, key) && source[key] != null) {
          const value = source[key];
          if (typeof value !== 'string' && typeof value !== 'number') {
            throw new Error(`第${i + 1}条课程字段格式无法确认，未跳过该条课程`);
          }
          row[key] = value;
        }
      }
      rows[rows.length] = row;
    }
    const yearLabel = document.querySelector('#xnm,[name="xnm"]')?.selectedOptions?.[0]?.textContent?.trim() || year;
    const termLabel = document.querySelector('#xqm,[name="xqm"]')?.selectedOptions?.[0]?.textContent?.trim() || term;
    send('courses', {year, term, sourceTerm: `${yearLabel} ${termLabel}`, rows});
  } catch (e) {
    send('error', e instanceof SyntaxError ? '教务会话可能已失效，请重新进入个人课表页' : e.message);
  }
}
