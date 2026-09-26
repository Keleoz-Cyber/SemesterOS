'use strict';
const CATEGORY = {
  study: {name:'学业',color:'#7061d9',pale:'#eeeafb',icon:'book'},
  research: {name:'科研',color:'#248f79',pale:'#e0f3eb',icon:'research'},
  affairs: {name:'校园事务',color:'#d28b42',pale:'#fbefdf',icon:'folder'},
  life: {name:'生活',color:'#d2748b',pale:'#fae8ec',icon:'heart'}
};
const TODAY = '2026-09-23';
const TAG_NAMES = {course:'课程',review:'复习',report:'报告',meeting:'组会',project:'项目讨论',material:'材料办理',sport:'运动'};
const dateAdd=(date,days)=>new Date(Date.parse(date+'T00:00:00Z')+days*86400000).toISOString().slice(0,10);
const timeNumber=time=>Number(time.slice(0,2))*60+Number(time.slice(3,5));
const dateLabel=date=>`${Number(date.slice(5,7))}月${Number(date.slice(8,10))}日`;
const shortDate=date=>`${Number(date.slice(5,7))}/${Number(date.slice(8,10))}`;
const weekday=date=>'日一二三四五六'[new Date(date+'T00:00:00Z').getUTCDay()];
const duration=row=>row.start&&row.end?timeNumber(row.end)-timeNumber(row.start):null;
const hourLabel=minutes=>Number((minutes/60).toFixed(1)).toString();
function seedData(){
 const rows=[];
 const add=(id,date,title,start,end,category,tags,kind,place='')=>{
   const isPast=date<TODAY||(date===TODAY&&end&&end<='11:40');
   rows.push({id,date,title,start,end,category,tags,kind,place,actual:kind==='course'?null:isPast?Math.max(15,duration({start,end})-10):null});
 };
 for(let week=0;week<8;week++){
  const monday=dateAdd('2026-08-31',week*7);
  add(`db-${week}`,monday,'数据库原理','08:00','09:50','study',['course'],'course','莲6号楼 201');
  add(`eng-${week}`,dateAdd(monday,1),'大学英语','10:00','11:50','study',['course'],'course','莲4号楼 205');
  add(`graphics-${week}`,dateAdd(monday,2),'计算机图形学','08:00','09:50','study',['course'],'course','莲7号楼 309');
  add(`prob-${week}`,dateAdd(monday,2),'概率论','10:00','11:50','study',['course'],'course','莲4号楼 208');
  add(`software-${week}`,dateAdd(monday,2),'软件工程','14:00','15:50','study',['course'],'course','莲7号楼 402');
  add(`os-${week}`,dateAdd(monday,3),'操作系统','10:00','11:50','study',['course'],'course','莲6号楼 405');
  add(`python-${week}`,dateAdd(monday,4),'Python程序设计','14:00','15:50','study',['course'],'course','文科楼 302');
  add(`review-${week}`,monday,'概率论复习','19:00','20:00','study',['review'],'plan');
  add(`research-${week}`,dateAdd(monday,1),'项目讨论','15:00','16:00','research',['project','meeting'],'activity','会议室 6302');
  add(`office-${week}`,dateAdd(monday,4),'材料办理','12:30','13:00','affairs',['material'],'activity','学生事务大厅');
  add(`run-${week}`,dateAdd(monday,5),'跑步','17:00','17:45','life',['sport'],'plan','操场');
 }
 rows.push({id:'java',date:TODAY,title:'Java实验报告',start:'17:00',end:'18:00',category:'study',tags:['report'],kind:'plan',place:'图书馆',actual:null});
 rows.push({id:'deadline',date:'2026-09-25',title:'提交Java实验报告',start:null,end:null,due:'18:00',category:'study',tags:['report'],kind:'deadline',place:'课程平台',actual:null});
 return rows;
}
const RANGE={week:['2026-09-21','2026-09-27'],month:['2026-09-01','2026-09-30'],semester:['2026-08-31','2027-01-17']};
function summarize(rows,{range='week',metric='scheduled',category=null,tags=[],day=null,empty=false}={}){
 const [from,to]=RANGE[range];
 const inRange=empty?[]:rows.filter(r=>r.date>=from&&r.date<=to&&(metric!=='scheduled'||r.kind!=='progress'));
 // A label filter is a union of matching records. Each record is counted once.
 const filtered=inRange.filter(r=>(!category||r.category===category)&&(!tags.length||tags.some(t=>r.tags.includes(t))));
 const value=r=>metric==='actual'?r.actual:duration(r);
 const totals=Object.fromEntries(Object.keys(CATEGORY).map(k=>[k,0]));
 const knownByCategory=Object.fromEntries(Object.keys(CATEGORY).map(k=>[k,0]));
 const days={};let total=0,known=0;
 for(const r of filtered){const n=value(r);if(n==null)continue;totals[r.category]+=n;total+=n;known++;knownByCategory[r.category]++;days[r.date]=(days[r.date]||0)+n;}
 const details=filtered.filter(r=>!day||r.date===day).sort((a,b)=>a.date.localeCompare(b.date)||(a.start||a.due||'').localeCompare(b.start||b.due||''));
 return {from,to,inRange,filtered,totals,knownByCategory,days,total,known,missing:filtered.filter(r=>r.kind!=='deadline'&&value(r)==null).length,details};
}
