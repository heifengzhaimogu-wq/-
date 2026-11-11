import {createClient} from 'npm:@supabase/supabase-js@2.80.0';
const headers={'Access-Control-Allow-Origin':'https://heifengzhaimogu-wq.github.io','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{headers});
 const reply=(status:number,message:string)=>new Response(JSON.stringify({message}),{status,headers});
 if(req.method!=='POST')return reply(405,'仅支持 POST');
 let staff='',token='',password='';
 try{const raw=await req.text();if(raw.length>10000)return reply(400,'请求过长');const body=JSON.parse(raw);staff=String(body.staff||'').trim().toUpperCase();token=String(body.token||'');password=String(body.password||'');}catch{return reply(400,'请求格式错误');}
 if(!/^[a-f0-9]{64}$/.test(token)||!/^[A-Z0-9_-]{4,32}$/.test(staff)||password.length<12||password.length>128)return reply(400,'请使用有效激活链接，密码需为12至128位');
 const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(token)))).map(b=>b.toString(16).padStart(2,'0')).join('');
 const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:member}=await db.from('desk_members').select('email,active,auth_user_id').eq('staff_id',staff).maybeSingle();
 if(!member?.active||member.auth_user_id)return reply(400,'激活链接无效、已使用或账号已开通');
 const email=member.email;
 const claimedAt=new Date().toISOString();
 const {data:invite,error:claimError}=await db.from('desk_invites').update({used_at:claimedAt}).eq('email',email).eq('token_hash',hash).is('used_at',null).gt('expires_at',claimedAt).select('email').maybeSingle();
 if(claimError||!invite)return reply(400,'激活链接无效、已使用或已过期');
 const {data,error}=await db.auth.admin.createUser({email,password,email_confirm:true});
 if(error||!data.user){await db.from('desk_invites').update({used_at:null}).eq('email',email).eq('token_hash',hash).eq('used_at',claimedAt);return reply(400,'账号开通未完成，请联系推进负责人处理');}
 const {error:updateError}=await db.from('desk_members').update({auth_user_id:data.user.id}).eq('email',email).is('auth_user_id',null);
 if(updateError)return reply(500,'账号已创建，但权限绑定未完成，请联系推进负责人');
 return reply(200,'账号已开通');
});
