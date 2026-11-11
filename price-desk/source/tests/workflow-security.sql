begin;
insert into public.desk_members(email,name,role,staff_id,store,team,auth_user_id) values
('coord@qa.invalid','总负责','coordinator','QA8761',null,null,'11111111-1111-1111-1111-111111111111'),
('coord2@qa.invalid','第二总负责','coordinator','QA8762',null,null,'11111111-1111-1111-1111-111111111112'),
('bp@qa.invalid','BP','bp','QA2001','QA-A',null,'22222222-2222-2222-2222-222222222222'),
('store@qa.invalid','店总','store','QA3001','QA-A',null,'33333333-3333-3333-3333-333333333333'),
('mgr@qa.invalid','经理','manager','QA4001','QA-A','1','44444444-4444-4444-4444-444444444444');
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","email":"coord@qa.invalid"}',true);
set local role authenticated;
select public.desk_import('QA任务',null,'[{"code":"QA1","store":"QA-A","team":"1","owner_staff":"QA1001","owner_name":"顾问1","estate":"测试盘","room":"01","quote":5000,"floor":4500},{"code":"QA2","store":"QA-A","team":"1","owner_staff":"QA1002","owner_name":"顾问2","estate":"测试盘","room":"02","quote":6000,"floor":5500},{"code":"QA3","store":"QA-A","team":"2","owner_staff":"QA1003","owner_name":"顾问3","estate":"测试盘","room":"03","quote":7000,"floor":6500},{"code":"QA4","store":"QA-B","team":"1","owner_staff":"QA1004","owner_name":"顾问4","estate":"测试盘","room":"04","quote":8000,"floor":7500}]');
do $$begin if(select count(*)from public.desk_tasks)<>4 or(select count(*)from public.desk_prices)<>0 then raise exception '总负责人范围或价格隔离错误';end if;end$$;
reset role;
update public.desk_members set auth_user_id='55555555-5555-5555-5555-555555555555' where staff_id='QA1001';
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","email":"bp@qa.invalid"}',true);
set local role authenticated;
do $$begin if(select count(*)from public.desk_tasks)<>3 or(select count(*)from public.desk_prices)<>0 then raise exception 'BP范围或价格隔离错误';end if;end$$;
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","email":"store@qa.invalid"}',true);
do $$begin if(select count(*)from public.desk_tasks)<>3 or(select count(*)from public.desk_prices)<>0 then raise exception '店总范围或价格隔离错误';end if;end$$;
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","email":"mgr@qa.invalid"}',true);
do $$begin if(select count(*)from public.desk_tasks)<>2 or(select count(*)from public.desk_prices)<>2 then raise exception '经理范围错误';end if;
begin perform public.desk_act((select id from public.desk_tasks where code='QA1'),1,'confirm');raise exception '经理不应操作顾问任务';exception when others then if SQLERRM='经理不应操作顾问任务' then raise;end if;end;
end$$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub','55555555-5555-5555-5555-555555555555','email',(select email from public.desk_members where staff_id='QA1001'))::text,true);
set local role authenticated;
do $$declare task uuid;begin
if(select count(*)from public.desk_tasks)<>1 or(select count(*)from public.desk_prices)<>1 then raise exception '顾问范围错误';end if;
select id into task from public.desk_tasks where code='QA1';
perform public.desk_act(task,1,'propose',5100,4600,'测试调价');
if not exists(select 1 from public.desk_tasks where id=task and check_state='checked' and adjust_state='pending')then raise exception '核对与调价状态未分离';end if;
begin perform public.desk_act(task,1,'complete');raise exception '过期版本未拦截';exception when others then if SQLERRM='过期版本未拦截' then raise;end if;end;
perform public.desk_act(task,2,'complete');
if not exists(select 1 from public.desk_tasks where id=task and adjust_state='done' and version=3)then raise exception '顾问完成调整失败';end if;
if not exists(select 1 from public.desk_prices where task_id=task and original_quote=5000 and original_floor=4500 and quote=5100)then raise exception '原价快照未保留';end if;
begin perform public.desk_staff_save('QA1001','提权','coordinator','','',true);raise exception '顾问提权未拦截';exception when others then if SQLERRM='顾问提权未拦截' then raise;end if;end;
end$$;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111112","email":"coord2@qa.invalid"}',true);
do $$begin if(select count(*)from public.desk_tasks)<>4 or(select count(*)from public.desk_prices)<>0 then raise exception '第二位总负责人范围错误';end if;end$$;
reset role;
select jsonb_build_object('coordinators',4,'bp_and_store',3,'manager',2,'advisor',1,'price_rows_for_coordinator_bp_store',0,'independent_workflow',true,'anon_read',has_table_privilege('anon','public.desk_tasks','select'),'anon_operation',has_function_privilege('anon','public.desk_act(uuid,integer,text,numeric,numeric,text)','execute'))as checks;
rollback;
