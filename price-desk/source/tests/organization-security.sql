begin;
insert into public.price_members(email,role,store,team) values ('org-admin@example.test','hrbp',null,null),('org-old@example.test','team','TEST-OLD','一组'),('org-new@example.test','team','TEST-NEW','二组');
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","email":"org-admin@example.test","role":"authenticated"}',true);
set local role authenticated;
select public.price_import('[{"code":"ORG-QA","store":"TEST-OLD","team":"一组","estate":"旧楼盘","room":"001","quote":5000,"floor":4500}]','org.csv');
insert into public.price_org_units(store,team)values('TEST-NEW','二组');
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","email":"org-old@example.test","role":"authenticated"}',true);
do $$begin
 begin
  update public.price_properties set team='二组' where code='ORG-QA';
  raise exception '经理直接转组未被拦截';
 exception when others then if SQLERRM='经理直接转组未被拦截' then raise;end if;end;
 begin
  perform public.price_admin_edit('ORG-QA',1,'TEST-NEW','二组','新楼盘','002',5200,4600,'违规');
  raise exception '经理调用管理员接口未被拦截';
 exception when others then if SQLERRM='经理调用管理员接口未被拦截' then raise;end if;end;
end $$;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","email":"org-admin@example.test","role":"authenticated"}',true);
select public.price_admin_edit('ORG-QA',1,'TEST-NEW','二组','新楼盘','002',5200,4600,'HRBP调整归属与资料');
do $$begin
 if not exists(select 1 from public.price_properties where code='ORG-QA' and store='TEST-NEW' and team='二组' and status='pending' and version=2 and quote=5200)then raise exception '转组数据不符';end if;
 if not exists(select 1 from public.price_history where code='ORG-QA' and action='资料调整' and old_store='TEST-OLD' and store='TEST-NEW' and old_estate='旧楼盘' and new_estate='新楼盘')then raise exception '审计缺失';end if;
 begin
  perform public.price_admin_edit('ORG-QA',1,'TEST-NEW','二组','新楼盘','002',5200,4600,'过期版本');
  raise exception '过期版本未被拦截';
 exception when others then if SQLERRM='过期版本未被拦截' then raise;end if;end;
end $$;
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","email":"org-old@example.test","role":"authenticated"}',true);
do $$begin
 if (select count(*) from public.price_properties where code='ORG-QA')<>0 then raise exception '原组仍可查看房源';end if;
 if (select count(*) from public.price_history where code='ORG-QA')<>0 then raise exception '原组仍可查看该房源历史';end if;
end $$;
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","email":"org-new@example.test","role":"authenticated"}',true);
do $$begin if (select count(*) from public.price_properties where code='ORG-QA')<>1 then raise exception '新组不可读';end if;end $$;
reset role;
select jsonb_build_object('manager_edit_denied',true,'transfer_and_audit',true,'old_team_read_revoked',true,'new_team_read_granted',true,'stale_version_denied',true,'anonymous_admin_execute',has_function_privilege('anon','public.price_admin_edit(text,integer,text,text,text,text,numeric,numeric,text)','execute'))as checks;
rollback;
