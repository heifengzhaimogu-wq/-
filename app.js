(() => {
  'use strict';
  const endpoint='https://yiuwfnncqgfeoprrdpyf.supabase.co/functions/v1/gratitude-api';
  const $=id=>document.getElementById(id);
  const giftNames={'gz-feature-1':'岭南秋实礼盒一','gz-feature-2':'秋日感恩心意礼','gz-feature-3':'感恩节暖心行动','gz-feature-4':'岭南秋实礼盒二','gz-feature-5':'超神蛋挞'};
  let gifts=[],filter='all',selectedGift=null;
  const filters=[['all','全部'],['fruit','时令水果'],['20—30元','20—30元'],['30—60元','30—60元'],['>60元','60元以上']];
  const safeUrl=s=>{try{const u=new URL(s);return ['https:','http:'].includes(u.protocol)?u.href:null}catch{return null}};
  const line=(tag,cls,value)=>{const e=document.createElement(tag);if(cls)e.className=cls;e.textContent=value??'';return e};
  async function api(path,options={}){const res=await fetch(endpoint+path,options);let body={};try{body=await res.json()}catch{}if(!res.ok)throw Error(body.error||'服务暂时无法连接');return body}
  function giftCard(g){
    const card=line('article','gift');
    if(g.image){const img=document.createElement('img');img.src=g.image;img.alt=g.name+'参考图片';img.loading='lazy';card.append(img)}
    else card.append(line('div','placeholder',g.name||'图片待补充'));
    const content=line('div','gift-content');
    content.append(line('span','tag',g.category||'伴手礼'),line('h4','',g.name),line('p','price',g.estimatedPriceRange||g.budgetTier||'价格待确认'),line('p','description',g.scenario||''));
    if(g.requestOnly){const button=line('button','button primary','我想要这个');button.type='button';button.onclick=()=>{selectedGift=g;$('request-title').textContent=g.name;$('request-status').textContent='';$('request-dialog').showModal()};content.append(button)}
    else{const href=safeUrl(g.purchaseUrl);if(href){const a=line('a','button','查看采购链接 ↗');a.href=href;a.target='_blank';a.rel='noopener noreferrer';content.append(a)}}
    card.append(content);return card;
  }
  function drawGifts(){
    $('featured').replaceChildren(...gifts.filter(g=>g.requestOnly).slice(0,5).map(giftCard));
    const list=gifts.filter(g=>!g.requestOnly&& (filter==='all'||(filter==='fruit'?g.freshGift:g.budgetTier===filter)));
    $('more').replaceChildren(...list.map(giftCard));
    if(!list.length)$('more').append(line('p','','当前筛选下暂无礼物。'));
    $('filters').replaceChildren(...filters.map(([id,label])=>{const b=line('button',filter===id?'active':'',label);b.type='button';b.setAttribute('aria-pressed',String(filter===id));b.onclick=()=>{filter=id;drawGifts()};return b}));
  }
  async function loadGifts(){
    try{const result=await api('/content');gifts=result.gifts||[]}
    catch{const response=await fetch('public-gifts.json');gifts=await response.json()}
    drawGifts();
  }
  $('request-close').onclick=()=>$('request-dialog').close();
  $('request-form').onsubmit=async e=>{
    e.preventDefault();const form=e.currentTarget,button=form.querySelector('button[type=submit],button.button');
    const field=name=>form.elements.namedItem(name).value;
    const payload={giftId:selectedGift?.id,store:field('store').trim(),name:field('name').trim(),quantity:Number(field('quantity'))};
    button.disabled=true;$('request-status').textContent='正在提交…';
    try{await api('/requests',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(payload)});$('request-status').textContent='提交成功，项目组会在后台看到您的需求。';form.reset()}
    catch(err){$('request-status').textContent=err.message;$('request-status').className='error'}
    finally{button.disabled=false}
  };
  let owner=localStorage.getItem('gz-gratitude-feedback-owner');
  if(!owner){owner=Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join('');localStorage.setItem('gz-gratitude-feedback-owner',owner)}
  const feedbackHeaders={'x-feedback-key':owner,'content-type':'application/json'};
  async function loadFeedback(){
    try{const result=await api('/feedback',{headers:feedbackHeaders});$('my-feedback').replaceChildren(...(result.feedbacks||[]).map(item=>{const a=line('article','');a.append(line('small','',new Date(item.createdAt).toLocaleString('zh-CN')+' · '+item.category),line('p','',item.message));return a}))}catch{$('my-feedback').textContent='留言记录暂时无法读取。'}
  }
  $('feedback-form').onsubmit=async e=>{
    e.preventDefault();const form=e.currentTarget,button=form.querySelector('button');
    const field=name=>form.elements.namedItem(name).value;
    const payload={id:crypto.randomUUID(),category:field('category'),author:field('author').trim(),message:field('message').trim()};
    button.disabled=true;$('feedback-status').textContent='正在提交…';
    try{await api('/feedback',{method:'POST',headers:feedbackHeaders,body:JSON.stringify(payload)});$('feedback-status').textContent='反馈已提交。';form.reset();await loadFeedback()}
    catch(err){$('feedback-status').textContent=err.message;$('feedback-status').className='error'}
    finally{button.disabled=false}
  };
  const palettes=[['#fff8eb','#9b7239','#e7c47c'],['#f7effb','#74458c','#c995d4'],['#fff2ea','#b85e43','#e9a473'],['#eff8f0','#39725b','#a6c7a7'],['#edf5fa','#315e84','#a8c4dc']];
  const canvas=$('card-canvas'),ctx=canvas.getContext('2d');
  function wrapped(text,maxWidth){
    const lines=[];for(const para of text.split(/\n|\r/)){let row='';for(const char of para){if(ctx.measureText(row+char).width>maxWidth&&row){lines.push(row);row=char}else row+=char}lines.push(row)}return lines;
  }
  function drawCard(){
    const index=$('theme').selectedIndex,[bg,ink,accent]=palettes[index],w=canvas.width,h=canvas.height;
    ctx.fillStyle=bg;ctx.fillRect(0,0,w,h);ctx.strokeStyle=accent;ctx.lineWidth=5;ctx.strokeRect(54,54,w-108,h-108);
    ctx.globalAlpha=.15;ctx.fillStyle=accent;
    for(let i=0;i<8;i++){ctx.beginPath();ctx.ellipse(860+i*22,220+i*18,210,45,-.7,0,Math.PI*2);ctx.fill()}
    ctx.globalAlpha=1;ctx.textAlign='center';ctx.fillStyle=ink;ctx.font='bold 74px Georgia,serif';ctx.fillText('LANDZ',w/2,190);
    ctx.font='30px "Songti SC",serif';ctx.fillText('丽 兹 行 · 广 州',w/2,250);
    ctx.strokeStyle=accent;ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(270,295);ctx.lineTo(810,295);ctx.stroke();
    ctx.font='46px "Songti SC",serif';ctx.fillText('感 恩 · 有 你',w/2,420);
    ctx.textAlign='left';ctx.font='40px "Songti SC",serif';ctx.fillText('致 '+($('card-to').value.trim()||'亲爱的您')+'：',140,550);
    ctx.font='32px "Songti SC",serif';const lines=wrapped($('card-body').value.trim(),800);
    lines.slice(0,10).forEach((s,i)=>ctx.fillText(s,140,645+i*50));
    ctx.textAlign='right';ctx.font='36px "Songti SC",serif';ctx.fillText($('card-from').value.trim()||'丽兹行广州团队',930,1240);
    ctx.font='26px "Songti SC",serif';ctx.fillText('2026年11月',930,1300);
  }
  $('card-form').onsubmit=e=>{e.preventDefault();drawCard();canvas.toBlob(blob=>{if(!blob){$('card-status').textContent='图片生成失败，请重试。';return}const old=$('card-download').href;if(old?.startsWith('blob:'))URL.revokeObjectURL(old);const url=URL.createObjectURL(blob);$('card-download').href=url;$('card-download').hidden=false;$('card-image').src=url;$('card-image').hidden=false;canvas.hidden=true;$('card-status').textContent='JPG 已生成，可下载或长按图片保存。'},'image/jpeg',.94)};
  ['theme','card-to','card-body','card-from'].forEach(id=>$(id).addEventListener('input',()=>{drawCard();canvas.hidden=false;$('card-image').hidden=true;$('card-download').hidden=true}));
  drawCard();loadGifts();loadFeedback();
})();
