import * as XLSX from 'xlsx';
import {createIcons,icons} from 'lucide';
import {storeProgress} from './organization.js';
export const workbenchName='全司房源价格管理核对工作台';
const $=s=>document.querySelector(s);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const statusNames={pending:'待核对',confirmed:'已确认',corrected:'已修正'};
export function selectExportRows(rows,profile,selection,filteredCodes=[]){
  if(!profile||profile.active===false||!['hrbp','store','team'].includes(profile.role))throw new Error('当前账号无导出权限');
  if(profile.role!=='hrbp'&&!profile.store||profile.role==='team'&&!profile.team)throw new Error('账号缺少店面或小组授权');
  if(!['all','store','filtered'].includes(selection.mode))throw new Error('请选择导出范围');
  if(selection.mode==='store'&&!selection.store)throw new Error('请选择店面');
  const codes=new Set(filteredCodes);
  return rows.filter(r=>(profile.role==='hrbp'||r.store===profile.store&&(profile.role==='store'||r.team===profile.team))&&(selection.mode!=='store'||r.store===selection.store)&&(selection.mode!=='filtered'||codes.has(r.code)));
}
export function buildExportWorkbook(rows){
  const details=XLSX.utils.aoa_to_sheet([['编号','店面','小组','楼盘','房间号','报价','底价','核对状态','核对备注','更新时间'],...rows.map(r=>[String(r.code),r.store,r.team,r.estate,String(r.room),Number(r.quote),Number(r.floor),statusNames[r.status]||r.status,r.note||'',r.updated_at?new Date(r.updated_at).toLocaleString('zh-CN',{timeZone:'Asia/Shanghai'}):''])]);
  details['!cols']=[{wch:18},{wch:20},{wch:18},{wch:28},{wch:22},{wch:16},{wch:16},{wch:14},{wch:45},{wch:24}];
  details['!autofilter']={ref:details['!ref']};
  for(let i=2;i<=rows.length+1;i++)for(const col of ['F','G'])details[col+i].z='#,##0.00';
  const progress=XLSX.utils.aoa_to_sheet([['店面','房源总数','待核对','已确认','已修正','完成率'],...storeProgress(rows).map(s=>[s.store,s.total,s.pending,s.confirmed,s.corrected,s.rate/100])]);
  progress['!cols']=[{wch:20},...Array.from({length:5},()=>({wch:14}))];
  for(let i=2;i<=storeProgress(rows).length+1;i++)progress['F'+i].z='0%';
  const wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,details,'房源明细');XLSX.utils.book_append_sheet(wb,progress,'店面核对进度');return wb;
}
async function latestAuthorizedRows(db){
  const {data:{user},error:authError}=await db.auth.getUser();if(authError||!user)throw new Error('登录已失效，请重新登录');
  const {data:profile,error}=await db.from('price_members').select('*').eq('email',user.email.toLowerCase()).eq('active',true).maybeSingle();
  if(error)throw error;if(!profile)throw new Error('当前邮箱没有有效授权');
  const rows=[];for(let from=0;;from+=1000){const {data,error}=await db.from('price_properties').select('*').order('code').range(from,from+999);if(error)throw error;rows.push(...data);if(data.length<1000)break;}
  return {profile,rows};
}
export function enhanceExport(ctx){
  if(!ctx.profile||ctx.view!=='overview')return;
  $('#image').insertAdjacentHTML('beforebegin','<button id="spreadsheet-export"><i data-lucide="file-down"></i><span>导出表格</span></button>');
  $('#spreadsheet-export').onclick=()=>{
    const label={hrbp:'全司房源',store:'本店房源',team:'本组房源'}[ctx.profile.role];
    const stores=[...new Set(selectExportRows(ctx.rows,ctx.profile,{mode:'all'}).map(r=>r.store))].sort();
    const initialStore=ctx.getStore();
    ctx.modal(`<h2>导出房源表格</h2><form id="spreadsheet-form"><label>导出范围<select id="export-mode" name="mode"><option value="all">${label}</option><option value="store">按店面${ctx.profile.role==='team'?'（本组范围）':''}</option><option value="filtered">当前筛选结果（全部页）</option></select></label><label id="export-store-label" hidden>店面<select id="export-store" name="store"><option value="">选择店面</option>${stores.map(s=>`<option value="${esc(s)}" ${s===initialStore?'selected':''}>${esc(s)}</option>`).join('')}</select></label><div id="export-count" class="muted"></div><button class="primary" type="submit"><i data-lucide="file-down"></i>导出 Excel</button><p id="export-error" role="alert"></p></form>`);
    $('#export-mode').value=initialStore?'store':'all';
    const update=()=>{const selection={mode:$('#export-mode').value,store:$('#export-store').value};$('#export-store-label').hidden=selection.mode!=='store';$('#export-store').required=selection.mode==='store';try{$('#export-count').textContent=`${selectExportRows(ctx.rows,ctx.profile,selection,ctx.getFiltered().map(r=>r.code)).length} 条房源 · Excel (.xlsx)`;}catch{$('#export-count').textContent='请选择店面';}};
    $('#export-mode').onchange=update;$('#export-store').onchange=update;update();createIcons({icons});
    $('#spreadsheet-form').onsubmit=async e=>{e.preventDefault();const b=e.target.querySelector('button');b.disabled=true;try{
      const selection={mode:$('#export-mode').value,store:$('#export-store').value},codes=ctx.getFiltered().map(r=>r.code);
      const source=ctx.demo?{profile:ctx.profile,rows:ctx.rows}:await latestAuthorizedRows(ctx.db);
      const rows=selectExportRows(source.rows,source.profile,selection,codes);if(!rows.length)throw new Error('当前范围没有可导出的房源');
      const scope=selection.mode==='store'?selection.store:selection.mode==='filtered'?'当前筛选':{hrbp:'全司',store:source.profile.store,team:source.profile.store+'-'+source.profile.team}[source.profile.role];
      const filename=`${workbenchName}-${scope}${ctx.demo?'-演示数据':''}-${new Date().toISOString().slice(0,10)}.xlsx`.replace(/[\\/:*?"<>|]/g,'_');
      XLSX.writeFile(buildExportWorkbook(rows),filename);$('#modal').close();ctx.toast(`已导出 ${rows.length} 条房源`);
    }catch(error){$('#export-error').textContent=error.message;}finally{b.disabled=false;}};
  };
  createIcons({icons});
}
