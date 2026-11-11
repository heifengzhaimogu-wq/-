(() => {
  'use strict';
  const endpoint='https://yiuwfnncqgfeoprrdpyf.supabase.co/functions/v1/gratitude-api/content';
  const $=id=>document.getElementById(id);
  const audience={
    '在售业主':{opening:'感谢您一直以来把重要的房产事宜交给我，也感谢您在沟通中的理解与配合。您的信任，我一直记在心里。',closing:'接下来我会继续认真跟进每一步，及时向您反馈，让您更安心。',poster:'感谢您一直以来的信任与托付。'},
    '已成交业主':{opening:'从相识到顺利完成交易，谢谢您把这段重要的旅程交给我。能陪您走过这一程，我很珍惜。',closing:'交易完成，关心不会止步。往后有需要，您依然可以随时联系我。',poster:'感谢您曾把重要的一程托付给我。'},
    '老顾客':{opening:'一直想找个机会，认真感谢您过去给予我的信任与支持。能和您保持联系，是我很珍惜的缘分。',closing:'愿我们继续常联系；无论是房产相关的事，还是一次近况问候，我都很乐意听您分享。',poster:'感谢一路相伴，也感谢每一次真诚的交流。'},
    '首次面见客户':{opening:'谢谢您愿意抽出时间和我见面。第一次交流，我更希望先认真听懂您的想法与需求。',closing:'期待这次见面能让您感受到清楚、真诚的服务；后续我也会根据您的实际需求准备合适的信息。',poster:'感谢您愿意与我见面，愿我们从真诚的交流开始。'},
    '转介绍客户':{opening:'谢谢您因为朋友的推荐愿意与我交流。这份信任的连接对我很珍贵，我会认真对待。',closing:'期待见面时多了解您的想法，用细致的服务回应您和朋友的信任。',poster:'感谢这份信任的连接，期待与您真诚相识。'}
  };
  const giftCopy={
    'gz-feature-1':{offer:'这次面见，我准备了一份贝贝南瓜与脐橙的秋日礼盒，想把丰收与鲜甜的心意送给您和家人。',wish:'愿这份南瓜与脐橙的秋日心意，为您和家人添一份鲜甜。'},
    'gz-feature-2':{offer:'这次面见，我准备了带有花环和稻草人公仔的秋日感恩心意礼，想为您的日常添一点轻松的节日气息。',wish:'愿这份秋日小礼，为您的生活添一点温暖与好心情。'},
    'gz-feature-3':{offer:'如果您方便且愿意，我想为家里添一点感恩节的装饰。具体布置会先征求您的意见，再按家中的环境安排。',wish:'愿一点恰到好处的节日装饰，为家里带来温暖。'},
    'gz-feature-4':{offer:'这次面见，我准备了一份贝贝南瓜与秋月梨的礼盒，愿这份清甜与丰收的心意适合您和家人分享。',wish:'愿这份南瓜与秋月梨的秋日心意，陪您和家人共享清甜。'},
    'gz-feature-5':{offer:'这次面见，我准备了一份板栗与红薯的暖心礼盒。简单、实在，希望为您的秋日添一份暖意。',wish:'愿板栗与红薯的朴实暖意，陪您度过美好的秋日。'}
  };
  let gifts=[],selectedId='gz-feature-1',scriptCustomized=false,wishCustomized=false,renderTimer=0,renderVersion=0;
  const imageCache=new Map();
  const canvas=$('meeting-canvas'),ctx=canvas.getContext('2d');
  const selected=()=>gifts.find(g=>g.id===selectedId);
  function loadImage(path){
    if(!imageCache.has(path))imageCache.set(path,new Promise((resolve,reject)=>{const image=new Image();image.onload=()=>resolve(image);image.onerror=reject;image.src=path}));
    return imageCache.get(path);
  }
  function drawCover(image,x,y,w,h){
    const scale=Math.max(w/image.width,h/image.height),sw=w/scale,sh=h/scale;
    ctx.drawImage(image,(image.width-sw)/2,(image.height-sh)/2,sw,sh,x,y,w,h);
  }
  function wrap(text,maxWidth){
    const lines=[];
    for(const paragraph of text.split(/\r?\n/)){
      let line='';
      for(const char of paragraph){
        if(line&&ctx.measureText(line+char).width>maxWidth){lines.push(line);line=char}else line+=char;
      }
      lines.push(line);
    }
    return lines;
  }
  function applyTemplate(force=false){
    const gift=giftCopy[selectedId],type=audience[$('meeting-audience').value];
    if(!gift||!type)return;
    const to=$('meeting-to').value.trim();
    if(force||!scriptCustomized){$('meeting-script').value=`${to?to+'，':''}您好！\n\n${type.opening}\n\n${gift.offer}\n\n${type.closing}`;scriptCustomized=false}
    if(force||!wishCustomized){$('meeting-wish').value=type.poster+gift.wish;wishCustomized=false}
    schedulePreview();
  }
  function renderChoices(){
    const root=$('meeting-gift-options');root.replaceChildren();
    for(const gift of gifts){
      const button=document.createElement('button');button.type='button';button.className='meeting-choice';
      button.setAttribute('aria-pressed',String(gift.id===selectedId));
      const image=document.createElement('img');image.src=gift.image;image.alt='';image.loading='lazy';
      const label=document.createElement('span');label.textContent=gift.name;
      button.append(image,label);button.onclick=()=>{selectedId=gift.id;renderChoices();applyTemplate(true)};root.append(button);
    }
  }
  function schedulePreview(){
    clearTimeout(renderTimer);$('meeting-image').hidden=true;canvas.hidden=false;$('meeting-download').hidden=true;
    renderTimer=setTimeout(()=>drawPoster().catch(()=>{$('meeting-status').textContent='图片预览暂时无法生成，请重试。'}),120);
  }
  async function drawPoster(){
    const gift=selected();if(!gift)return;
    const version=++renderVersion;
    const [photo,logo]=await Promise.all([
      loadImage(gift.image).catch(()=>null),
      loadImage('media/guangzhou/landz-logo.png').catch(()=>null)
    ]);
    if(version!==renderVersion)return;
    const w=canvas.width,h=canvas.height;
    ctx.fillStyle='#fbf8f6';ctx.fillRect(0,0,w,h);
    ctx.fillStyle='#34213d';ctx.fillRect(0,0,w,170);
    if(logo){const width=265,height=width*logo.height/logo.width;ctx.drawImage(logo,66,(170-height)/2,width,height)}
    else{ctx.fillStyle='#f4df9b';ctx.font='bold 74px Georgia,serif';ctx.fillText('LANDZ',66,110)}
    ctx.textAlign='right';ctx.fillStyle='#f4dfd2';ctx.font='28px "Songti SC",serif';ctx.fillText('广州 · 11月感恩月',1010,102);
    ctx.fillStyle='#eaddf0';ctx.fillRect(58,200,964,540);
    if(photo)drawCover(photo,70,212,940,516);
    else{ctx.fillStyle='#654580';ctx.font='44px "Songti SC",serif';ctx.textAlign='center';ctx.fillText('礼物图片待补充',540,485)}
    ctx.textAlign='left';ctx.fillStyle='#8d6a40';ctx.font='bold 25px "Songti SC",serif';ctx.fillText('一 份 面 见 心 意',78,792);
    ctx.fillStyle='#34213d';ctx.font='bold 44px "Songti SC",serif';
    wrap(gift.name,920).slice(0,2).forEach((line,i)=>ctx.fillText(line,78,852+i*58));
    ctx.fillStyle='#654580';ctx.fillRect(78,936,924,3);
    ctx.fillStyle='#34213d';ctx.font='38px "Songti SC",serif';
    ctx.fillText('致 '+($('meeting-to').value.trim()||'亲爱的您')+'：',82,1008);
    ctx.font='34px "Songti SC",serif';
    const lines=wrap($('meeting-wish').value.trim(),910).slice(0,5);
    lines.forEach((line,i)=>ctx.fillText(line,82,1080+i*48));
    ctx.textAlign='right';ctx.font='32px "Songti SC",serif';
    ctx.fillText($('meeting-from').value.trim()||'丽兹行广州团队',1000,1340);
    ctx.fillStyle='#8d6a40';ctx.font='23px "Songti SC",serif';ctx.fillText('感谢相遇 · 珍惜信任',1000,1390);
  }
  $('meeting-audience').onchange=()=>applyTemplate(true);
  $('meeting-to').oninput=()=>applyTemplate(false);
  $('meeting-script').oninput=()=>{scriptCustomized=true};
  $('meeting-wish').oninput=()=>{wishCustomized=true;schedulePreview()};
  $('meeting-from').oninput=schedulePreview;
  $('meeting-copy').onclick=async()=>{
    try{await navigator.clipboard.writeText($('meeting-script').value);$('meeting-status').textContent='面见话术已复制。'}
    catch{$('meeting-status').textContent='复制失败，请长按或选中话术手动复制。'}
  };
  $('meeting-form').onsubmit=async event=>{
    event.preventDefault();
    try{
      await drawPoster();
      canvas.toBlob(blob=>{
        if(!blob){$('meeting-status').textContent='海报生成失败，请重试。';return}
        const old=$('meeting-download').href;if(old?.startsWith('blob:'))URL.revokeObjectURL(old);
        const url=URL.createObjectURL(blob);$('meeting-download').href=url;
        $('meeting-download').download=(selected()?.name||'广州面见礼物')+'海报.jpg';
        $('meeting-image').src=url;$('meeting-image').hidden=false;canvas.hidden=true;
        $('meeting-download').hidden=false;$('meeting-status').textContent='海报 JPG 已生成，可下载或长按保存。';
      },'image/jpeg',.94);
    }catch{$('meeting-status').textContent='海报生成失败，请重试。'}
  };
  (async()=>{
    try{const response=await fetch(endpoint);if(!response.ok)throw Error('礼物服务暂不可用');gifts=(await response.json()).gifts||[]}
    catch{try{gifts=await (await fetch('public-gifts.json')).json()}catch{}}
    gifts=gifts.filter(g=>giftCopy[g.id]);
    if(!gifts.length){$('meeting-gift-options').textContent='礼物数据暂时无法加载，请刷新页面。';return}
    selectedId=gifts[0].id;renderChoices();applyTemplate(true);
  })();
})();
