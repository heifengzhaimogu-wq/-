(() => {
  'use strict';
  const base='https://yiuwfnncqgfeoprrdpyf.supabase.co';
  const edge=base+'/functions/v1/gratitude-api';
  const key='sb_publishable_aNYLhQd8OTIHJtV_mMDyvg_JB4db5ed';
  const $=id=>document.getElementById(id);
  const make=(tag,text)=>{const el=document.createElement(tag);el.textContent=text??'';return el};
  let token=sessionStorage.getItem('gz-admin-token')||'',gifts=[];
  async function call(url,options={}){
    const headers={'content-type':'application/json',apikey:key,...(options.headers||{})};
    if(token)headers.authorization='Bearer '+token;
    const response=await fetch(url,{...options,headers});
    let body={};try{body=await response.json()}catch{}
    if(!response.ok)throw Error(body.error_description||body.msg||body.error||'操作失败');
    return body;
  }
  async function auth(action,password){
    const path=action==='signup'?'/auth/v1/signup':'/auth/v1/token?grant_type=password';
    const email=$('email').value.trim();
    if(!email)throw Error('请填写管理员邮箱');
    const result=await call(base+path,{method:'POST',body:JSON.stringify({email,password})});
    if(action==='signup'){$('status').textContent='账号申请已提交。请到邮箱完成验证，然后回来登录。';return}
    token=result.access_token||'';if(!token)throw Error('未取得登录凭证，请完成邮箱验证');
    sessionStorage.setItem('gz-admin-token',token);await refresh();
  }
  $('login-form').onsubmit=async e=>{e.preventDefault();try{await auth('login',$('password').value)}catch(err){$('status').textContent=err.message}};
  $('signup').onclick=async()=>{const password=$('password').value;if(password.length<8){$('status').textContent='请先填写至少 8 位密码';return}try{await auth('signup',password)}catch(err){$('status').textContent=err.message}};
  $('logout').onclick=()=>{token='';sessionStorage.removeItem('gz-admin-token');$('admin-panels').hidden=true;$('login-panel').hidden=false;$('status').textContent='已退出登录'};
  $('refresh').onclick=refresh;
  async function refresh(){
    if(!token)return;
    try{
      const [requests,feedback,catalog]=await Promise.all([
        call(edge+'/admin/requests'),call(edge+'/admin/feedback'),call(edge+'/admin/catalog')
      ]);
      $('login-panel').hidden=true;$('admin-panels').hidden=false;$('status').textContent='已同步最新数据';
      gifts=catalog.gifts||[];renderRequests(requests.requests||[]);renderFeedback(feedback.feedbacks||[]);renderCatalog();
    }catch(err){$('status').textContent=err.message;if(/登录|授权|身份/.test(err.message)){$('admin-panels').hidden=true;$('login-panel').hidden=false}}
  }
  function renderRequests(items){
    const root=$('requests');root.replaceChildren();
    if(!items.length){root.textContent='暂无需求登记';return}
    for(const item of items){const row=make('div','');row.className='row';row.append(make('strong',(gifts.find(g=>g.id===item.gift_id)?.name||item.gift_id)+' · '+item.quantity+'份'),make('small',item.store+' · '+item.name+' · '+new Date(item.created_at).toLocaleString('zh-CN')+' · 邮件：'+item.email_status));root.append(row)}
  }
  function renderFeedback(items){
    const root=$('feedback');root.replaceChildren();
    if(!items.length){root.textContent='暂无反馈';return}
    for(const item of items){const row=make('div','');row.className='row';row.append(make('strong',item.category+' · '+(item.author||'未署名')),make('small',new Date(item.createdAt).toLocaleString('zh-CN')),make('p',item.message));root.append(row)}
  }
  async function publish(items){
    const ids=new Set();
    for(let i=0;i<items.length;i++){
      const g=items[i];if(!g.id||!g.name)throw Error('第 '+(i+2)+' 行缺少 id 或 name');
      if(ids.has(g.id))throw Error('礼物编号重复：'+g.id);ids.add(g.id);
      if(g.purchaseUrl&&!/^https?:\/\//i.test(g.purchaseUrl))throw Error('采购链接格式不正确：'+g.id);
    }
    if(!items.length||items.length>200)throw Error('礼物数量须为 1—200 款');
    const result=await call(edge+'/admin/catalog',{method:'POST',body:JSON.stringify({gifts:items})});
    $('catalog-status').textContent='已发布 '+result.count+' 款礼物，伙伴刷新页面即可看到。';await refresh();
  }
  function renderCatalog(){
    const root=$('catalog-list');root.replaceChildren();
    for(const gift of gifts){const row=make('div','');row.className='row';row.append(make('strong',gift.name),make('small',[gift.category,gift.estimatedPriceRange,gift.purchaseUrl?'采购链接':'需求登记'].filter(Boolean).join(' · ')));
      const button=make('button','修改');button.type='button';button.className='button secondary';button.onclick=async()=>{
        const name=prompt('礼物名称',gift.name);if(name===null)return;
        const price=prompt('参考价格',gift.estimatedPriceRange||'');if(price===null)return;
        const scenario=prompt('推荐说明',gift.scenario||'');if(scenario===null)return;
        const purchaseUrl=prompt('采购链接；主推需求登记请留空',gift.purchaseUrl||'');if(purchaseUrl===null)return;
        try{await publish(gifts.map(g=>g.id===gift.id?{...g,name,estimatedPriceRange:price,scenario,purchaseUrl}:g))}catch(err){$('catalog-status').textContent=err.message}
      };row.append(button);root.append(row)}
  }
  function parseCsv(text){
    text=text.replace(/^\uFEFF/,'');const rows=[];let row=[],field='',quoted=false;
    for(let i=0;i<text.length;i++){const c=text[i];if(c==='"'){if(quoted&&text[i+1]==='"'){field+='"';i++}else quoted=!quoted}
      else if(c===','&&!quoted){row.push(field);field=''}
      else if((c==='\n'||c==='\r')&&!quoted){if(c==='\r'&&text[i+1]==='\n')i++;row.push(field);if(row.some(x=>x!==''))rows.push(row);row=[];field=''}
      else field+=c}
    if(quoted)throw Error('CSV 引号未闭合');row.push(field);if(row.some(x=>x!==''))rows.push(row);
    if(rows.length<2)throw Error('文件没有礼物数据');const keys=rows.shift().map(x=>x.trim());
    if(!keys.includes('id')||!keys.includes('name'))throw Error('表头必须包含 id 和 name');
    return rows.map(cells=>Object.fromEntries(keys.map((k,i)=>[k,cells[i]||''])));
  }
  function normalize(rows){
    return rows.map(row=>{const g={};for(const [k,v] of Object.entries(row)){if(!k)continue;g[k]=typeof v==='string'?v.trim():v}for(const k of ['requestOnly','priority','freshGift'])if(k in g)g[k]=g[k]===true||/^(true|1|是)$/i.test(String(g[k]));return g});
  }
  $('upload-form').onsubmit=async e=>{
    e.preventDefault();const file=$('catalog-file').files[0];if(!file)return;
    $('catalog-status').textContent='正在检查文件…';
    try{let rows;if(/\.csv$/i.test(file.name))rows=parseCsv(await file.text());
      else{if(!window.XLSX)throw Error('Excel 解析组件未载入，请重试或保存为 CSV 上传');const book=XLSX.read(await file.arrayBuffer(),{type:'array'});rows=XLSX.utils.sheet_to_json(book.Sheets[book.SheetNames[0]],{defval:''})}
      await publish(normalize(rows));
    }catch(err){$('catalog-status').textContent=err.message}
  };
  $('download').onclick=()=>{
    const columns=['id','name','category','budgetTier','estimatedPriceRange','scenario','purchaseUrl','priority','freshGift','requestOnly','image'];
    const esc=v=>'"'+String(v??'').replaceAll('"','""')+'"';
    const csv='\uFEFF'+[columns.join(','),...gifts.map(g=>columns.map(k=>esc(g[k])).join(','))].join('\r\n');
    const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download='广州感恩月礼物库.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)
  };
  refresh();
})();
