import {createClient} from 'npm:@supabase/supabase-js@2.80.0';
const headers={'Access-Control-Allow-Origin':'https://heifengzhaimogu-wq.github.io','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
Deno.serve(async req=>{
 const reply=(status:number,data:unknown)=>new Response(JSON.stringify(data),{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{headers});
 if(req.method!=='POST')return reply(405,{message:'仅支持 POST'});
 let staff='',password='';try{const raw=await req.text();if(raw.length>10000)throw new Error();const input=JSON.parse(raw);staff=String(input.staff||'').trim().toUpperCase();password=String(input.password||'');}catch{return reply(400,{message:'请求格式错误'});}
 if(!/^[A-Z0-9_-]{4,32}$/.test(staff)||!password||password.length>128)return reply(400,{message:'请输入工号和工作台密码'});
 const url=Deno.env.get('SUPABASE_URL')!;
 const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:matches,error}=await admin.from('desk_members').select('email,auth_user_id').eq(staff.length===4?'staff_suffix':'staff_id',staff).eq('active',true).limit(2);
 if(error||!matches?.length)return reply(401,{message:'工号或工作台密码不正确，或账号尚未开通'});
 if(matches.length>1)return reply(400,{message:'工号后四位重复，请输入完整工号'});
 if(!matches[0].auth_user_id)return reply(401,{message:'账号尚未激活，请使用负责人提供的专属激活链接'});
 const client=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data,error:authError}=await client.auth.signInWithPassword({email:matches[0].email,password});
 if(authError||!data.session)return reply(401,{message:'工号或工作台密码不正确'});
 return reply(200,{session:data.session});
});
