alter table public.desk_members add column staff_id text not null unique check(staff_id=upper(trim(staff_id)) and staff_id ~ '^[A-Z0-9_-]{4,32}$');
alter table public.desk_members add column staff_suffix text generated always as (right(staff_id,4)) stored;
create index on public.desk_members(staff_suffix);
create or replace function desk_private.scope(s text,t text,e text,prices boolean default false) returns boolean language plpgsql stable security definer set search_path='' as $$
declare m public.desk_members;
begin
 m=desk_private.me();if m.email is null then return false;end if;
 if prices and m.role in ('coordinator','bp','store') then return false;end if;
 return m.role='coordinator' or (m.store=s and (m.role in ('bp','store') or (m.team=t and (m.role='manager' or (m.role='advisor' and m.email=e)))));
end $$;
create function desk_private.staff_save(p_staff text,p_name text,p_role text,p_store text,p_team text,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
declare m public.desk_members;
begin
 m=desk_private.me();if m.email is null or m.role<>'coordinator' then raise exception '仅全司推进负责人可以设置成员';end if;
 if upper(trim(p_staff))=m.staff_id then raise exception '不能修改本人权限';end if;
 if nullif(trim(p_name),'') is null then raise exception '姓名不能为空';end if;
 insert into public.desk_members(staff_id,email,name,role,store,team,active)values(upper(trim(p_staff)),gen_random_uuid()::text||'@staff.invalid',trim(p_name),p_role,nullif(trim(p_store),''),nullif(trim(p_team),''),p_active)
 on conflict(staff_id) do update set name=excluded.name,role=excluded.role,store=excluded.store,team=excluded.team,active=excluded.active;
end $$;
create function public.desk_staff_save(p_staff text,p_name text,p_role text,p_store text,p_team text,p_active boolean) returns void language sql security invoker set search_path='' as $$select desk_private.staff_save(p_staff,p_name,p_role,p_store,p_team,p_active)$$;
create function public.desk_staff_invite(p_staff text) returns text language sql security invoker set search_path='' as $$select desk_private.invite((select email from public.desk_members where staff_id=upper(trim(p_staff))))$$;
revoke all on function public.desk_member_save(text,text,text,text,text,boolean),desk_private.member_save(text,text,text,text,text,boolean) from authenticated;
revoke all on function desk_private.staff_save(text,text,text,text,text,boolean),public.desk_staff_save(text,text,text,text,text,boolean),public.desk_staff_invite(text) from public,anon;
grant execute on function desk_private.staff_save(text,text,text,text,text,boolean),public.desk_staff_save(text,text,text,text,text,boolean),public.desk_staff_invite(text) to authenticated;
create or replace function desk_private.import_tasks(p_name text,p_due date,p_rows jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare m public.desk_members;r jsonb;batch uuid;task uuid;owner public.desk_members;
begin
 m=desk_private.me();if m.email is null or m.role<>'coordinator' then raise exception '仅全司推进负责人可以下发任务';end if;
 if nullif(trim(p_name),'') is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>5000 then raise exception '请输入批次名称，每次1至5000条';end if;
 insert into public.desk_batches(name,due_date)values(trim(p_name),p_due)returning id into batch;
 for r in select * from jsonb_array_elements(p_rows) loop
  if nullif(trim(r->>'code'),'') is null or nullif(trim(r->>'store'),'') is null or nullif(trim(r->>'team'),'') is null or nullif(trim(r->>'owner_name'),'') is null or nullif(trim(r->>'estate'),'') is null or nullif(trim(r->>'room'),'') is null or coalesce(r->>'owner_staff','')!~'^[A-Z0-9_-]{4,32}$' then raise exception '房源、店组、顾问姓名和工号等字段不能为空';end if;
  select * into owner from public.desk_members where staff_id=upper(trim(r->>'owner_staff')) for update;
  if found then
   if not owner.active or owner.role<>'advisor' or owner.store<>trim(r->>'store') or owner.team<>trim(r->>'team') then raise exception '顾问 % 的角色或店组与任务不一致',r->>'owner_staff';end if;
  else
   insert into public.desk_members(staff_id,email,name,role,store,team)values(upper(trim(r->>'owner_staff')),gen_random_uuid()::text||'@staff.invalid',trim(r->>'owner_name'),'advisor',trim(r->>'store'),trim(r->>'team')) returning * into owner;
  end if;
  insert into public.desk_tasks(batch_id,code,store,team,owner_email,owner_name,estate,room)values(batch,trim(r->>'code'),trim(r->>'store'),trim(r->>'team'),owner.email,trim(r->>'owner_name'),trim(r->>'estate'),trim(r->>'room'))returning id into task;
  if r->>'quote' is null or r->>'floor' is null then raise exception '报价、底价不能为空';end if;
  insert into public.desk_prices(task_id,quote,floor)values(task,(r->>'quote')::numeric,(r->>'floor')::numeric);
 end loop;
 return batch;
end $$;
