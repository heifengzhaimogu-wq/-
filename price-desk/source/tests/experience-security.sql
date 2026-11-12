begin;
insert into public.desk_members(email,name,role,staff_id,store,team,auth_user_id)values
('experience-admin@qa.invalid','验收总负责人','coordinator','QA-E-0761',null,null,'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
('experience-store@qa.invalid','验收店总','store','QA-E-0762','TEST-E',null,'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
('experience-manager@qa.invalid','验收经理','manager','QA-E-0763','TEST-E','1','cccccccc-cccc-cccc-cccc-cccccccccccc');
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","email":"experience-admin@qa.invalid"}',true);
set local role authenticated;
select public.desk_staff_profile_save('QA-E-0763','验收经理','manager','TEST-E','1',true,'手工登记的店负责人');
select public.desk_import_dated('历史所属日期验收',null,'[{"code":"DATE-E1","store":"TEST-E","team":"1","owner_staff":"QA-E-0764","owner_name":"验收顾问","estate":"测试盘","room":"001","quote":5000,"floor":4500}]','errors','dated.csv','2026-10-01');
do $$begin
 if not exists(select 1 from public.desk_batches where name='历史所属日期验收' and dataset_date='2026-10-01')then raise exception '数据所属日期未保存';end if;
 if(select count(*)from public.desk_prices)<>0 then raise exception '总负责人不应读取价格';end if;
end$$;
select set_config('request.jwt.claims','{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","email":"experience-store@qa.invalid"}',true);
do $$begin
 if public.desk_identity_context()->>'store_lead'<>'验收店总' then raise exception '店面负责人上下文不正确';end if;
 if(select count(*)from public.desk_prices)<>0 then raise exception '店总不应读取价格';end if;
end$$;
select set_config('request.jwt.claims','{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","email":"experience-manager@qa.invalid"}',true);
do $$begin
 if public.desk_identity_context()->>'store_lead'<>'手工登记的店负责人' then raise exception '登记负责人未返回';end if;
 begin perform public.desk_staff_profile_save('QA-E-0763','错误提权','coordinator','','',true,'');raise exception '经理不应修改档案权限';exception when others then if SQLERRM='经理不应修改档案权限' then raise;end if;end;
end$$;
reset role;
select jsonb_build_object('dataset_date_saved',true,'leader_context_scoped',true,'manager_profile_write_denied',true,'anon_identity_execute',has_function_privilege('anon','public.desk_identity_context()','execute'),'authenticated_limit_execute',has_function_privilege('authenticated','public.desk_access_attempt(text)','execute'))as checks;
rollback;
