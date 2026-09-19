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
    const allow = ['kcmc', 'xm', 'cdmc', 'xqj', 'zcd', 'jc', 'jcs', 'jxb_id', 'kch_id'];
    const rows = data.kbList.map(row => Object.fromEntries(allow.filter(k => row[k] != null).map(k => [k, row[k]])));
    const yearLabel = document.querySelector('#xnm,[name="xnm"]')?.selectedOptions?.[0]?.textContent?.trim() || year;
    const termLabel = document.querySelector('#xqm,[name="xqm"]')?.selectedOptions?.[0]?.textContent?.trim() || term;
    send('courses', {year, term, sourceTerm: `${yearLabel} ${termLabel}`, rows});
  } catch (e) {
    send('error', e instanceof SyntaxError ? '教务会话可能已失效，请重新进入个人课表页' : e.message);
  }
}
