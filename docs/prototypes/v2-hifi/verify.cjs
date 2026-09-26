// Offline QA. Uses installed Chrome; opens no server and blocks network requests.
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const out=path.resolve(__dirname,'../../../output/v2-hifi');fs.mkdirSync(out,{recursive:true});
let html=fs.readFileSync(path.join(__dirname,'index.html'),'utf8');
html=html.replace('<link rel="stylesheet" href="style.css">',`<style>${fs.readFileSync(path.join(__dirname,'style.css'),'utf8')}</style>`);
for(const file of ['data.js','pages.js','app.js'])html=html.replace(`<script src="${file}"></script>`,`<script>${fs.readFileSync(path.join(__dirname,file),'utf8')}</script>`);
const checks=[];
async function openStats(page){
 if(await page.locator('#overlay').isVisible())await page.getByRole('button',{name:'关闭',exact:true}).click();
 await page.locator('#nav').getByRole('button',{name:'学期',exact:true}).click();
 await page.locator('#main').getByRole('button',{name:'统计分析',exact:true}).click();
}

async function shot(page,name){
 if(await page.locator('#animated-total').count())await page.waitForFunction(()=>{const el=document.querySelector('#animated-total');return !el||el.textContent===(document.querySelector('#metric')?.value==='actual'&&Number(el.dataset.known)===0?'—':Number((Number(el.dataset.minutes)/60).toFixed(1)).toString());});
 await page.screenshot({path:path.join(out,name+'.png'),animations:'disabled'});
}
(async()=>{const browser=await chromium.launch({headless:true,channel:'chrome'});try{
 const page=await browser.newPage({viewport:{width:1480,height:1050},deviceScaleFactor:1});const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.route('**/*',route=>route.abort());await page.setContent(html);
 await shot(page,'desktop');await page.setViewportSize({width:412,height:915});await shot(page,'today');
 assert(await page.getByRole('heading',{name:'今日安排',exact:true}).isVisible());
 const lastCourse=await page.locator('.schedule-row').filter({hasText:'软件工程'}).boundingBox();const dock=await page.locator('#dock').boundingBox();assert(lastCourse.y+lastCourse.height<dock.y);checks.push('Three courses appear before input dock');
 for(const tab of ['今日','日程','计划']){await page.locator('#nav').getByRole('button',{name:tab,exact:true}).click();assert.equal(await page.locator('#device [data-action="analytics"]').count(),0);}
 await page.locator('#nav').getByRole('button',{name:'学期',exact:true}).click();assert.equal(await page.locator('#device [data-action="analytics"]').count(),1);
 await openStats(page);await page.getByRole('button',{name:'返回',exact:true}).click();assert(await page.locator('#header').getByRole('heading',{name:'本学期',exact:true}).isVisible());
 await page.locator('#nav').getByRole('button',{name:'今日',exact:true}).click();checks.push('Statistics has one persistent entry under Semester and returns to its source');

 await page.getByRole('button',{name:'语音输入',exact:true}).click();assert(await page.getByText('这里展示录音交互。本原型没有调用麦克风。').isVisible());await shot(page,'voice');await page.getByRole('button',{name:'关闭',exact:true}).click();
 await page.getByRole('button',{name:'记录日程，或向AI提问',exact:true}).click();await shot(page,'assistant');
 await page.getByRole('textbox',{name:'输入内容'}).fill('并非预置的请求');await page.getByRole('button',{name:'发送',exact:true}).click();assert(await page.getByText('原型未接入真实AI，暂时不能处理这段输入。文字已保留。').isVisible());checks.push('Arbitrary input and voice are not faked');
 await page.getByRole('button',{name:'查看组会示例'}).click();await page.getByRole('button',{name:'加入日程',exact:true}).waitFor();
 await page.getByRole('button',{name:'修改分类',exact:true}).click();await page.getByRole('button',{name:'项目讨论',exact:true}).click();await page.getByRole('button',{name:'确认分类',exact:true}).click();
 assert(await page.locator('.tag-editor').getByText('项目讨论',{exact:true}).isVisible());await shot(page,'candidate');
 await page.getByRole('button',{name:'加入日程',exact:true}).click();assert(await page.getByText('组会已加入日程',{exact:true}).isVisible());
 await page.getByRole('button',{name:'查看调整方案',exact:true}).click();await shot(page,'proposal');await page.getByRole('button',{name:'应用调整',exact:true}).click();assert(await page.getByRole('heading',{name:'计划已调整'}).isVisible());await shot(page,'receipt');checks.push('Classification, save, separate replan and receipt');
 await openStats(page);await page.waitForFunction(()=>document.querySelector('#animated-total').textContent===hourLabel(Number(document.querySelector('#animated-total').dataset.minutes)));await shot(page,'analytics');
 const total=Number(await page.locator('#animated-total').getAttribute('data-minutes'));
 // 7 courses * 110 + review 60 + project 60 + material 30 + run 45 + Java 60 + new meeting 60.
 assert.equal(total,1085);checks.push('Week total equals its explicit fixture components');
 await page.getByRole('button',{name:'筛选科研'}).click();assert.equal(Number(await page.locator('#animated-total').getAttribute('data-minutes')),120);
 await page.locator('.tag-strip').getByRole('button',{name:'组会',exact:true}).click();await page.locator('.tag-strip').getByRole('button',{name:'项目讨论',exact:true}).click();assert.equal(Number(await page.locator('#animated-total').getAttribute('data-minutes')),120);assert.equal(await page.locator('.detail-entry').count(),2);await shot(page,'analytics-filtered');checks.push('Multi-label union counts each event once');
 await page.getByRole('button',{name:'9月23日 1小时',exact:true}).click();assert.equal(await page.locator('.detail-entry').count(),1);assert(await page.locator('.detail-entry').getByText('课题组组会',{exact:true}).isVisible());checks.push('Day selection filters the source list');
 await page.getByRole('button',{name:'清除筛选',exact:true}).click();await page.locator('#metric').selectOption('actual');assert.equal(Number(await page.locator('#animated-total').getAttribute('data-minutes')),100);checks.push('Actual records exclude unrecorded course attendance');
 await page.locator('.tag-strip').getByRole('button',{name:'课程',exact:true}).click();assert.equal(await page.locator('#animated-total').innerText(),'—');assert(await page.getByText('7条安排没有实际时长记录，未计入。',{exact:true}).isVisible());await page.getByRole('button',{name:'清除筛选',exact:true}).click();checks.push('Missing actual records do not appear as zero hours');
 await page.getByRole('button',{name:'本月',exact:true}).click();const month=Number(await page.locator('#animated-total').getAttribute('data-minutes'));assert(month>100);await page.getByRole('button',{name:'本周',exact:true}).click();assert.equal(Number(await page.locator('#animated-total').getAttribute('data-minutes')),100);checks.push('Range switch recomputes and returns consistently');
 await page.locator('#nav').getByRole('button',{name:'计划',exact:true}).click();await page.getByRole('button',{name:'撤销本次调整'}).click();assert(await page.getByText('组会与报告计划在周三17:00重叠',{exact:true}).isVisible());checks.push('Undo moves plan back but preserves meeting');
 await page.locator('#nav').getByRole('button',{name:'今日',exact:true}).click();await page.getByRole('button',{name:'9月24日 周四',exact:true}).click();assert(await page.getByRole('heading',{name:'9月24日的安排'}).isVisible());checks.push('Day control changes visible schedule');
 await openStats(page);await page.getByRole('button',{name:'账户与设置'}).click();await page.getByRole('button',{name:'体验离线状态',exact:true}).click();await page.getByRole('button',{name:'关闭',exact:true}).click();assert(await page.getByText('离线 · 正在查看本机保存的记录',{exact:true}).isVisible());checks.push('Offline state retains visible data');
 for(const width of [360,390,430]){await page.setViewportSize({width,height:850});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));}
 await page.emulateMedia({reducedMotion:'reduce'});await page.getByRole('button',{name:'本月',exact:true}).click();assert.equal(await page.locator('.bar-fill').first().evaluate(e=>getComputedStyle(e).animationName),'none');checks.push('Mobile widths and reduced motion');
 await page.setViewportSize({width:1480,height:1050});await page.getByRole('button',{name:'空数据状态',exact:true}).click();assert(await page.getByText('当前范围暂无记录',{exact:true}).isVisible());await shot(page,'empty');checks.push('Empty range is explicit');
 await page.getByRole('button',{name:'空数据状态',exact:true}).click();await page.emulateMedia({reducedMotion:'no-preference'});await page.locator('#metric').selectOption('scheduled');await page.getByRole('button',{name:'本周',exact:true}).click();await page.getByRole('button',{name:'筛选生活',exact:true}).click();await page.getByRole('button',{name:'筛选科研',exact:true}).click();assert.equal(Number(await page.locator('#animated-total').getAttribute('data-minutes')),120);await page.waitForFunction(()=>document.querySelector('#animated-total').textContent==='2');checks.push('Interrupted updates settle on the most recent filter');
 await page.locator('.review-tools').getByRole('button',{name:'离线状态',exact:true}).click();
 await page.locator('.review-tabs').getByRole('button',{name:/今日安排/}).click();await page.getByRole('button',{name:'记录日程，或向AI提问',exact:true}).click();await page.getByRole('button',{name:'添加组会并调整冲突计划',exact:false}).click();assert(await page.getByRole('heading',{name:'调整计划',exact:true}).isVisible());assert.equal(await page.getByRole('button',{name:'加入日程',exact:true}).count(),0);checks.push('Repeating an existing notice opens its result instead of duplicating it');
 // Complete page coverage, using the existing saved meeting and un-moved report.
 await page.getByRole('button',{name:'关闭',exact:true}).click();
 await page.setViewportSize({width:412,height:915});
 await page.locator('#nav').getByRole('button',{name:'日程',exact:true}).click();
 assert(await page.locator('.calendar-scroll').isVisible());await shot(page,'schedule-week');
 const reportGrid=page.locator('.calendar-event').filter({hasText:'Java报告'}),meetingGrid=page.locator('.calendar-event').filter({hasText:'组会'});
 const rg=await reportGrid.boundingBox(),mg=await meetingGrid.boundingBox();assert(rg&&mg&&rg.x+rg.width<=mg.x+1,'Overlapping events must be side by side');checks.push('Week grid assigns independent columns to overlapping events');
 await page.getByRole('button',{name:'按天查看',exact:true}).click();assert(await page.locator('.list-card').getByText('课题组组会',{exact:true}).isVisible());await shot(page,'schedule-day');
 await page.locator('.type-filters').getByRole('button',{name:'课程',exact:true}).click();assert.equal(await page.locator('.schedule-row').count(),3);checks.push('Day view and type filter share selected date');
 await page.locator('.type-filters').getByRole('button',{name:'全部',exact:true}).click();
 await page.getByRole('button',{name:'下一周',exact:true}).click();assert(await page.getByRole('button',{name:/第5周/}).isVisible());await page.getByRole('button',{name:'回本周',exact:true}).click();assert(await page.getByRole('button',{name:/第4周/}).isVisible());checks.push('Week navigation and return preserve a valid week');
 await page.getByRole('button',{name:'导入课表',exact:true}).click();await page.getByRole('textbox',{name:'搜索学校'}).fill('其他学校');assert(await page.getByText('暂未适配这所学校',{exact:true}).isVisible());await page.getByRole('textbox',{name:'搜索学校'}).fill('河南');await page.getByRole('button',{name:/河南工业大学/}).click();await page.getByRole('button',{name:'查看示例导入预览'}).click();await page.getByRole('button',{name:'确认示例导入'}).click();assert(await page.getByText('7门课程相同，没有重复添加。').isVisible());await page.getByRole('button',{name:'查看课表',exact:true}).click();checks.push('School search and duplicate import receipt');
 await page.locator('#nav').getByRole('button',{name:'计划',exact:true}).click();assert.equal(await page.locator('.task-tile').count(),3);await shot(page,'plans-full');
 await page.getByRole('button',{name:'记录Java实验报告进度',exact:true}).click();await page.locator('#spent-minutes').fill('-1');await page.getByRole('button',{name:'保存进度',exact:true}).click();assert(await page.getByText('请输入1至1440之间的整数分钟数。').isVisible());
 await page.locator('#spent-minutes').fill('40');await page.getByLabel('这个任务已经完成').check();await shot(page,'progress-entry');await page.getByRole('button',{name:'保存进度',exact:true}).click();assert.equal(await page.locator('.task-tile').count(),2);
 await page.locator('.plan-tabs').getByRole('button',{name:'已完成',exact:true}).click();assert.equal(await page.locator('.task-tile').count(),1);assert(await page.getByText('已记录40分钟',{exact:true}).isVisible());await shot(page,'plans-completed');checks.push('Progress validation, completion and completed list');
 await openStats(page);await page.getByRole('button',{name:'清除筛选',exact:true}).click();assert.equal(Number(await page.locator('#animated-total').getAttribute('data-minutes')),1025);await page.locator('#metric').selectOption('actual');assert.equal(Number(await page.locator('#animated-total').getAttribute('data-minutes')),140);checks.push('Completion removes 60 planned minutes; actual work adds only the entered 40 minutes');
 await page.locator('#nav').getByRole('button',{name:'计划',exact:true}).click();await page.getByRole('button',{name:'查看Java实验报告进度'}).click();await page.getByRole('button',{name:'撤销这条完成记录'}).click();await page.locator('.plan-tabs').getByRole('button',{name:'待完成',exact:true}).click();assert.equal(await page.locator('.task-tile').count(),3);assert(await page.getByText('组会与报告计划在周三17:00重叠',{exact:true}).isVisible());checks.push('Undo completion restores original plan and removes the progress record');
 await page.locator('#nav').getByRole('button',{name:'学期',exact:true}).click();await page.locator('#toast').evaluate(el=>el.classList.remove('show'));await shot(page,'semester-full');
 await page.getByRole('button',{name:/第14周，有1项事项/}).click();await page.locator('.type-filters').getByRole('button',{name:'考试',exact:true}).click();assert(await page.getByText('概率论考试',{exact:true}).isVisible());await shot(page,'semester-exam');await page.getByRole('button',{name:/暂定第14周 · 日期待确认/}).click();await page.getByRole('button',{name:'查看复习任务'}).click();assert(await page.getByRole('heading',{name:'概率论复习',exact:true}).isVisible());await page.getByRole('button',{name:'关闭',exact:true}).click();checks.push('Tentative exam remains undated and opens its review task');
 await page.getByRole('button',{name:'第20周',exact:true}).click();assert(await page.getByText('这一周暂无这类事项',{exact:true}).isVisible());checks.push('Empty semester week preserves the selected filter');
 await page.setViewportSize({width:1480,height:1050});await page.getByRole('button',{name:'加载失败',exact:true}).click();assert(await page.getByText('更新失败，正在显示已有记录',{exact:false}).isVisible());assert(await page.locator('.schedule-row').count()>0);await page.getByRole('button',{name:'重试',exact:true}).click();assert.equal(await page.locator('.retry-banner').count(),0);checks.push('Failed update retains records and retry restores the normal state');
 for(const v of ['日程','计划','学期']){await page.locator('#nav').getByRole('button',{name:v,exact:true}).click();for(const width of [360,390,430]){await page.setViewportSize({width,height:800});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));}}
 checks.push('All remaining pages fit 360/390/430 widths');
 assert.deepEqual(errors,[]);checks.push('No JavaScript runtime errors');
 fs.writeFileSync(path.join(out,'V2-high-fidelity.html'),html);fs.writeFileSync(path.join(out,'V2-complete-preview.html'),html);fs.writeFileSync(path.join(out,'verification.json'),JSON.stringify({checks,limits:'Offline HTML only, no model, Flutter or phone performance validation.'},null,2));console.log(JSON.stringify({passed:checks.length,out}));
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
