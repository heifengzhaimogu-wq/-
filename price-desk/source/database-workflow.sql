create schema desk_private;
create table public.desk_members (
 email text primary key check(email=lower(trim(email))),name text not null,
 role text not null check(role in ('coordinator','bp','store','manager','advisor')),
 store text,team text,active boolean not null default true,auth_user_id uuid unique,
 check(role='coordinator' or nullif(trim(store),'') is not null),
 check(role not in ('manager','advisor') or nullif(trim(team),'') is not null)
);
create table public.desk_batches(id uuid primary key default gen_random_uuid(),name text not null, due_date date,created_at timestamptz not null default now());
create table public.desk_tasks(
 id uuid primary key default gen_random_uuid(),batch_id uuid not null references public.desk_batches,
 code text not null,store text not null,team text not null,owner_email text not null references public.desk_members(email),owner_name text not null,
 estate text not null,room text not null,check_state text not null default 'todo' check(check_state in ('todo','checked')),
 adjust_state text not null default 'undecided' check(adjust_state in ('undecided','not_needed','pending','done')),
 version integer not null default 1,updated_at timestamptz not null default now(),
 unique(batch_id,code),check((check_state='todo' and adjust_state='undecided') or (check_state='checked' and adjust_state<>'undecided'))
);
create index on public.desk_tasks(store,team,owner_email,batch_id);
create table public.desk_prices(task_id uuid primary key references public.desk_tasks on delete cascade,
 quote numeric(14,2) not null,floor numeric(14,2) not null,proposed_quote numeric(14,2),proposed_floor numeric(14,2),reason text,
 check(quote>=0 and floor>=0 and floor<=quote and quote<>'NaN'::numeric and floor<>'NaN'::numeric),
 check((proposed_quote is null and proposed_floor is null) or (proposed_quote>=0 and proposed_floor>=0 and proposed_floor<=proposed_quote and proposed_quote<>'NaN'::numeric and proposed_floor<>'NaN'::numeric))
);
create table public.desk_events(id bigint generated always as identity primary key,task_id uuid not null references public.desk_tasks,action text not null,actor uuid not null,created_at timestamptz not null default now());
create table public.desk_invites(email text primary key references public.desk_members,token_hash text not null,expires_at timestamptz not null,used_at timestamptz);
alter table public.desk_members enable row level security;
alter table public.desk_batches enable row level security;
alter table public.desk_tasks enable row level security;
alter table public.desk_prices enable row level security;
alter table public.desk_events enable row level security;
alter table public.desk_invites enable row level security;
revoke all on public.desk_members,public.desk_batches,public.desk_tasks,public.desk_prices,public.desk_events,public.desk_invites from anon,authenticated;
grant select on public.desk_members,public.desk_batches,public.desk_tasks,public.desk_prices,public.desk_events to authenticated;
grant all on public.desk_members,public.desk_invites to service_role;
create function desk_private.me() returns public.desk_members language sql stable security definer set search_path='' as $$
 select m from public.desk_members m where auth.uid() is not null and m.auth_user_id=auth.uid() and m.email=lower(auth.jwt()->>'email') and m.active
$$;
create function desk_private.scope(s text,t text,e text,prices boolean default false) returns boolean language plpgsql stable security definer set search_path='' as $$
declare m public.desk_members;
begin
 m=desk_private.me();if m.email is null then return false;end if;
 if prices and m.role in ('coordinator','bp') then return false;end if;
 return m.role='coordinator' or (m.store=s and (m.role in ('bp','store') or (m.team=t and (m.role='manager' or (m.role='advisor' and m.email=e)))));
end $$;
revoke all on function desk_private.me(),desk_private.scope(text,text,text,boolean) from public;
grant usage on schema desk_private to authenticated;
grant execute on function desk_private.me(),desk_private.scope(text,text,text,boolean) to authenticated;
create policy desk_member_read on public.desk_members for select to authenticated using(email=(desk_private.me()).email or (desk_private.me()).role='coordinator');
create policy desk_batch_read on public.desk_batches for select to authenticated using((desk_private.me()).role='coordinator' or exists(select 1 from public.desk_tasks t where t.batch_id=desk_batches.id));
create policy desk_task_read on public.desk_tasks for select to authenticated using(desk_private.scope(store,team,owner_email,false));
create policy desk_price_read on public.desk_prices for select to authenticated using(exists(select 1 from public.desk_tasks t where t.id=task_id and desk_private.scope(t.store,t.team,t.owner_email,true)));
create policy desk_event_read on public.desk_events for select to authenticated using(exists(select 1 from public.desk_tasks t where t.id=task_id));
create policy desk_invite_deny on public.desk_invites for all to authenticated using(false) with check(false);

create function desk_private.act(p_id uuid,p_version integer,p_action text,p_quote numeric,p_floor numeric,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare m public.desk_members;t public.desk_tasks;
begin
 m=desk_private.me();if m.email is null or m.role<>'advisor' then raise exception '仅负责该房源的顾问可以操作';end if;
 select * into t from public.desk_tasks where id=p_id for update;
 if not found or not desk_private.scope(t.store,t.team,t.owner_email,true) then raise exception '无权操作该房源';end if;
 if t.version<>p_version then raise exception '任务已更新，请刷新后重试';end if;
 if p_action='confirm' then
  if t.check_state<>'todo' then raise exception '此房源已核对';end if;
  update public.desk_tasks set check_state='checked',adjust_state='not_needed' where id=t.id;
 elsif p_action='propose' then
  if t.adjust_state='done' then raise exception '本轮已完成调整';end if;
  if nullif(trim(p_reason),'') is null or p_quote is null or p_floor is null then raise exception '请填写目标价格和调整原因';end if;
  update public.desk_prices set proposed_quote=p_quote,proposed_floor=p_floor,reason=trim(p_reason) where task_id=t.id;
  update public.desk_tasks set check_state='checked',adjust_state='pending' where id=t.id;
 elsif p_action='complete' then
  if t.adjust_state<>'pending' then raise exception '仅待调整任务可确认完成';end if;
  update public.desk_prices set quote=proposed_quote,floor=proposed_floor where task_id=t.id;
  update public.desk_tasks set adjust_state='done' where id=t.id;
 else raise exception '未知操作';end if;
 update public.desk_tasks set version=version+1,updated_at=now() where id=t.id;
 insert into public.desk_events(task_id,action,actor)values(t.id,case p_action when 'confirm' then '核对完成，无需调价' when 'propose' then '核对完成，待完成调价' else '顾问确认已完成调价' end,auth.uid());
end $$;
create function public.desk_act(p_id uuid,p_version integer,p_action text,p_quote numeric default null,p_floor numeric default null,p_reason text default '') returns void language sql security invoker set search_path='' as $$select desk_private.act(p_id,p_version,p_action,p_quote,p_floor,p_reason)$$;

create function desk_private.member_save(p_email text,p_name text,p_role text,p_store text,p_team text,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
declare m public.desk_members;
begin
 m=desk_private.me();if m.email is null or m.role<>'coordinator' then raise exception '仅全司推进负责人可以设置成员';end if;
 if lower(trim(p_email))=m.email then raise exception '不能修改本人权限';end if;
 if nullif(trim(p_name),'') is null then raise exception '姓名不能为空';end if;
 insert into public.desk_members(email,name,role,store,team,active)values(lower(trim(p_email)),trim(p_name),p_role,nullif(trim(p_store),''),nullif(trim(p_team),''),p_active)
 on conflict(email) do update set name=excluded.name,role=excluded.role,store=excluded.store,team=excluded.team,active=excluded.active;
end $$;
create function public.desk_member_save(p_email text,p_name text,p_role text,p_store text,p_team text,p_active boolean) returns void language sql security invoker set search_path='' as $$select desk_private.member_save(p_email,p_name,p_role,p_store,p_team,p_active)$$;
create function desk_private.invite(p_email text) returns text language plpgsql security definer set search_path='' as $$
declare m public.desk_members;token text;
begin
 m=desk_private.me();if m.email is null or m.role<>'coordinator' then raise exception '仅全司推进负责人可以开通账号';end if;
 if not exists(select 1 from public.desk_members where email=p_email and active and auth_user_id is null) then raise exception '账号已开通、已停用或不存在';end if;
 token=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 insert into public.desk_invites(email,token_hash,expires_at)values(p_email,encode(sha256(convert_to(token,'UTF8')),'hex'),now()+interval '7 days')on conflict(email)do update set token_hash=excluded.token_hash,expires_at=excluded.expires_at,used_at=null;
 return token;
end $$;
create function public.desk_invite(p_email text) returns text language sql security invoker set search_path='' as $$select desk_private.invite(p_email)$$;

create function desk_private.import_tasks(p_name text,p_due date,p_rows jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare m public.desk_members;r jsonb;batch uuid;task uuid;owner public.desk_members;
begin
 m=desk_private.me();if m.email is null or m.role<>'coordinator' then raise exception '仅全司推进负责人可以下发任务';end if;
 if nullif(trim(p_name),'') is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>5000 then raise exception '请输入批次名称，每次1至5000条';end if;
 insert into public.desk_batches(name,due_date)values(trim(p_name),p_due)returning id into batch;
 for r in select * from jsonb_array_elements(p_rows) loop
  if nullif(trim(r->>'code'),'') is null or nullif(trim(r->>'store'),'') is null or nullif(trim(r->>'team'),'') is null or nullif(trim(r->>'owner_name'),'') is null or nullif(trim(r->>'estate'),'') is null or nullif(trim(r->>'room'),'') is null or coalesce(r->>'owner_email','')!~'^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception '房源、店组、顾问姓名和邮箱等字段不能为空';end if;
  select * into owner from public.desk_members where email=lower(trim(r->>'owner_email')) for update;
  if found then
   if not owner.active or owner.role<>'advisor' or owner.store<>trim(r->>'store') or owner.team<>trim(r->>'team') then raise exception '顾问 % 的角色或店组与任务不一致',r->>'owner_email';end if;
  else
   insert into public.desk_members(email,name,role,store,team)values(lower(trim(r->>'owner_email')),trim(r->>'owner_name'),'advisor',trim(r->>'store'),trim(r->>'team'));
  end if;
  insert into public.desk_tasks(batch_id,code,store,team,owner_email,owner_name,estate,room)values(batch,trim(r->>'code'),trim(r->>'store'),trim(r->>'team'),lower(trim(r->>'owner_email')),trim(r->>'owner_name'),trim(r->>'estate'),trim(r->>'room'))returning id into task;
  if r->>'quote' is null or r->>'floor' is null then raise exception '报价、底价不能为空';end if;
  insert into public.desk_prices(task_id,quote,floor)values(task,(r->>'quote')::numeric,(r->>'floor')::numeric);
 end loop;
 return batch;
end $$;
create function public.desk_import(p_name text,p_due date,p_rows jsonb) returns uuid language sql security invoker set search_path='' as $$select desk_private.import_tasks(p_name,p_due,p_rows)$$;

revoke all on function desk_private.act(uuid,integer,text,numeric,numeric,text),desk_private.member_save(text,text,text,text,text,boolean),desk_private.invite(text),desk_private.import_tasks(text,date,jsonb),public.desk_act(uuid,integer,text,numeric,numeric,text),public.desk_member_save(text,text,text,text,text,boolean),public.desk_invite(text),public.desk_import(text,date,jsonb) from public,anon;
grant execute on function desk_private.act(uuid,integer,text,numeric,numeric,text),desk_private.member_save(text,text,text,text,text,boolean),desk_private.invite(text),desk_private.import_tasks(text,date,jsonb),public.desk_act(uuid,integer,text,numeric,numeric,text),public.desk_member_save(text,text,text,text,text,boolean),public.desk_invite(text),public.desk_import(text,date,jsonb) to authenticated;
