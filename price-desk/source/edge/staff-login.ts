import {createClient} from 'npm:@supabase/supabase-js@2.80.0';
const headers={'Access-Control-Allow-Origin':'https://heifengzhaimogu-wq.github.io','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
const aliases:Record<string,string>={'全司推进负责人':'coordinator','推进负责人':'coordinator','全司负责人':'coordinator','全司BP':'coordinator','负责人':'coordinator','门店BP':'bp','BP':'bp','店总':'store','店长':'store','店经理':'manager','经理':'manager','组经理':'manager','顾问':'advisor','经纪人':'advisor'};
Deno.serve(async req=>{
 const reply=(status:number,data:unknown)=>new Response(JSON.stringify(data),{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{headers});if(req.method!=='POST')return reply(405,{message:'仅支持 POST'});
 let staff='',store='',position='';try{const raw=await req.text();if(raw.length>5000)throw new Error();const input=JSON.parse(raw);staff=String(input.staff||'').trim().toUpperCase();store=String(input.store||'').trim();position=String(input.position||'').trim().replace(/\s/g,'').toUpperCase();}catch{return reply(400,{message:'请求格式错误'});}
 const role=aliases[position];
 if(!/^[A-Z0-9_-]{4,32}$/.test(staff)||store.length<2||store.length>60||!role)return reply(400,{message:'请填写工号、至少两字的店面关键词，以及登记职位'});
 const url=Deno.env.get('SUPABASE_URL')!,admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 const ip=req.headers.get('cf-connecting-ip')||req.headers.get('x-forwarded-for')?.split(',')[0]||'unknown';
 const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(ip+'|'+staff)))).map(b=>b.toString(16).padStart(2,'0')).join('');
 const {data:allowed,error:limitError}=await admin.rpc('desk_access_attempt',{p_key:digest});if(limitError||!allowed)return reply(429,{message:'尝试过于频繁，请15分钟后再试'});
 const {data:rows,error}=await admin.from('desk_members').select('email,auth_user_id,store,role').eq(staff.length===4?'staff_suffix':'staff_id',staff).eq('role',role).eq('active',true).limit(50);
 const matches=rows?.filter(m=>role==='coordinator'?['全司','全公司','公司','总部'].includes(store):m.store?.toLowerCase().includes(store.toLowerCase()));
 if(error||!matches?.length)return reply(401,{message:'未匹配员工档案，请核对工号、店面与职位，或联系推进负责人'});
 if(matches.length!==1)return reply(409,{message:'匹配到多位员工，请输入完整工号及更精确的店名'});
 const member=matches[0];
 const {data:link,error:linkError}=await admin.auth.admin.generateLink({type:'magiclink',email:member.email});
 if(linkError||!link.user||!link.properties?.hashed_token)return reply(503,{message:'身份服务暂不可用，请稍后重试'});
 if(member.auth_user_id&&member.auth_user_id!==link.user.id)return reply(403,{message:'员工档案身份不一致，请联系推进负责人'});
 if(!member.auth_user_id){const {error:bindError}=await admin.from('desk_members').update({auth_user_id:link.user.id}).eq('email',member.email).is('auth_user_id',null);if(bindError)return reply(503,{message:'身份绑定未完成，请稍后重试'});}
 const client=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data,error:verifyError}=await client.auth.verifyOtp({token_hash:link.properties.hashed_token,type:link.properties.verification_type as 'magiclink'|'signup'});
 if(verifyError||!data.session)return reply(503,{message:'身份确认未完成，请稍后重试'});
 return reply(200,{session:data.session});
});
