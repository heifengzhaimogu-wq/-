const headers={'Access-Control-Allow-Origin':'https://heifengzhaimogu-wq.github.io','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Content-Type':'application/json'};
Deno.serve(req=>req.method==='OPTIONS'?new Response(null,{status:204,headers}):new Response(JSON.stringify({message:'当前无需密码或激活链接，请使用工号、店面关键词、职位匹配员工档案'}),{status:410,headers}));
