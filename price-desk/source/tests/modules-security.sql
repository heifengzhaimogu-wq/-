begin;
insert into public.desk_members(email,name,role,staff_id,store,auth_user_id)values('modules-admin@qa.invalid','模块验收负责人','coordinator','QA6761',null,'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),('modules-bp@qa.invalid','模块验收BP','bp','QA6762','TEST-M-A','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","email":"modules-admin@qa.invalid"}',true);
set local role authenticated;
select public.desk_import_managed('模块联动验收',null,'[{"code":"MOD-1","store":"TEST-M-A","team":"1","owner_staff":"QA6763","owner_name":"验收顾问","estate":"测试盘","room":"001","quote":5000,"floor":4500},{"code":"MOD-2","store":"TEST-M-B","team":"1","owner_staff":"QA6764","owner_name":"验收顾问2","estate":"测试盘","room":"002","quote":6000,"floor":5500}]','errors','issues.csv');
select public.desk_target_save('month','2039-11-01','',90,2);
select public.desk_target_save('month','2039-11-01','TEST-M-A',80,1);
select public.desk_target_save('month','2039-11-01','TEST-M-B',95,1);
do $$begin
 if(select count(*)from public.desk_tasks where code in('MOD-1','MOD-2') and issue_required and check_state='todo')<>2 then raise exception '导入后需整改量未生成';end if;
 if not exists(select 1 from public.desk_batches where name='模块联动验收' and source_name='issues.csv' and import_mode='errors')then raise exception '来源批次信息缺失';end if;
 if(select count(*)from public.desk_prices)<>0 then raise exception '负责人不应读取价格';end if;
end$$;
select set_config('request.jwt.claims','{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","email":"modules-bp@qa.invalid"}',true);
do $$begin
 if(select count(*)from public.desk_review_targets where period_start='2039-11-01')<>2 then raise exception 'BP目标范围错误';end if;
 begin perform public.desk_target_save('month','2039-11-01','TEST-M-A',100,10);raise exception 'BP不应设置目标';exception when others then if SQLERRM='BP不应设置目标' then raise;end if;end;
end$$;
reset role;
update public.desk_members set auth_user_id='cccccccc-cccc-cccc-cccc-cccccccccccc' where staff_id='QA6763';
select set_config('request.jwt.claims',jsonb_build_object('sub','cccccccc-cccc-cccc-cccc-cccccccccccc','email',(select email from public.desk_members where staff_id='QA6763'))::text,true);
set local role authenticated;
do $$declare task uuid;begin
 select id into task from public.desk_tasks where code='MOD-1';
 begin perform public.desk_act(task,1,'confirm');raise exception '已知错误不能直接忽略';exception when others then if SQLERRM='已知错误不能直接忽略' then raise;end if;end;
 perform public.desk_act(task,1,'propose',5100,4500,'来源已确认错误');perform public.desk_act(task,2,'complete');
end$$;
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","email":"modules-admin@qa.invalid"}',true);
do $$begin if(select count(*)from public.desk_tasks where code in('MOD-1','MOD-2') and issue_required and adjust_state='done')<>1 then raise exception '完成回写未同步';end if;end$$;
reset role;
select jsonb_build_object('known_errors',2,'completed',1,'rectification_rate',50,'target_scope_isolated',true,'bp_target_write_denied',true,'false_no_change_denied',true,'anon_target_read',has_table_privilege('anon','public.desk_review_targets','select'))as checks;
rollback;
