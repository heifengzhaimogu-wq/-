create schema if not exists price_private;
create table public.price_members (
 email text primary key check(email=lower(email)), role text not null check(role in ('hrbp','store','team')),
 store text, team text, active boolean not null default true,
 check(role='hrbp' or nullif(trim(store),'') is not null),
 check(role<>'team' or nullif(trim(team),'') is not null)
);
alter table public.price_members enable row level security;
create function price_private.allowed(s text,t text) returns boolean language sql stable security definer set search_path='' as $$
select auth.uid() is not null and exists(select 1 from public.price_members m where m.email=lower(auth.jwt()->>'email') and m.active and (m.role='hrbp' or m.store=s and (m.role='store' or m.team=t))) $$;
create function price_private.hrbp() returns boolean language sql stable security definer set search_path='' as $$
select auth.uid() is not null and exists(select 1 from public.price_members m where m.email=lower(auth.jwt()->>'email') and m.active and m.role='hrbp') $$;
revoke all on function price_private.allowed(text,text),price_private.hrbp() from public;
grant usage on schema price_private to authenticated;
grant execute on function price_private.allowed(text,text),price_private.hrbp() to authenticated;
create policy member_read on public.price_members for select to authenticated using(email=lower(auth.jwt()->>'email') or price_private.hrbp());
create policy member_write on public.price_members for all to authenticated using(price_private.hrbp()) with check(price_private.hrbp());
create table public.price_properties (
 code text primary key check(length(trim(code))>0), store text not null check(length(trim(store))>0), team text not null check(length(trim(team))>0),
 estate text not null check(length(trim(estate))>0),room text not null check(length(trim(room))>0),
 quote numeric(14,2) not null check(quote>=0),floor numeric(14,2) not null check(floor>=0 and floor<=quote),
 status text not null default 'pending' check(status in ('pending','confirmed','corrected')),note text not null default '',
 version integer not null default 1,updated_at timestamptz not null default now()
);
create index on public.price_properties(store,team);
alter table public.price_properties enable row level security;
create policy property_read on public.price_properties for select to authenticated using(price_private.allowed(store,team));
create policy property_insert on public.price_properties for insert to authenticated with check(price_private.hrbp());
create policy property_update on public.price_properties for update to authenticated using(price_private.allowed(store,team)) with check(price_private.allowed(store,team));
create table public.price_history (
 id bigint generated always as identity primary key, code text not null, store text not null, team text not null,
 old_quote numeric, new_quote numeric, old_floor numeric,new_floor numeric, action text not null,
 actor uuid,created_at timestamptz not null default now(),note text
);
alter table public.price_history enable row level security;
create index on public.price_history(store,team,created_at desc);
create policy history_read on public.price_history for select to authenticated using(price_private.allowed(store,team));
create table public.price_imports (
 id uuid primary key default gen_random_uuid(),filename text not null,rows integer not null,actor uuid default auth.uid(),created_at timestamptz default now()
);
alter table public.price_imports enable row level security;
create policy imports_hrbp on public.price_imports for all to authenticated using(price_private.hrbp()) with check(price_private.hrbp());
revoke all on public.price_members,public.price_properties,public.price_history,public.price_imports from anon,authenticated;
grant select,insert,update,delete on public.price_members to authenticated;
grant select,insert on public.price_properties to authenticated;
grant update(quote,floor,status,note) on public.price_properties to authenticated;
grant select on public.price_history to authenticated;
grant select,insert on public.price_imports to authenticated;
create function price_private.audit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 if TG_OP='UPDATE' then
  if (new.store,new.team,new.estate,new.room,new.code) is distinct from (old.store,old.team,old.estate,old.room,old.code) then raise exception '房源归属或描述变更请联系管理员单独处理'; end if;
  new.version=old.version+1; new.updated_at=now();
 end if;
 insert into public.price_history(code,store,team,old_quote,new_quote,old_floor,new_floor,action,actor,note)
 values(new.code,new.store,new.team,case when TG_OP='UPDATE' then old.quote end,new.quote,case when TG_OP='UPDATE' then old.floor end,new.floor,case when TG_OP='INSERT' then '新增' when new.quote<>old.quote or new.floor<>old.floor then '价格变更' else '核对' end,auth.uid(),new.note);
 return new;
end $$;
revoke all on function price_private.audit() from public;
create trigger price_audit before insert or update on public.price_properties for each row execute function price_private.audit();
create function public.price_review(p_code text,p_version integer,p_quote numeric,p_floor numeric,p_note text,p_confirm boolean)
returns void language plpgsql security invoker set search_path='' as $$
declare n integer;
begin
 if not p_confirm and length(trim(p_note))=0 then raise exception '修正必须填写原因'; end if;
 update public.price_properties set quote=p_quote,floor=p_floor,note=p_note,status=case when p_confirm then 'confirmed' else 'corrected' end where code=p_code and version=p_version and (not p_confirm or (quote=p_quote and floor=p_floor));
 get diagnostics n=row_count;
 if n<>1 then raise exception '记录已变化或无权限，请刷新后重新核对'; end if;
end $$;
create function public.price_import(p_rows jsonb,p_filename text) returns void language plpgsql security invoker set search_path='' as $$
declare r jsonb; old public.price_properties%rowtype; n integer:=0;
begin
 if not price_private.hrbp() then raise exception '仅 HRBP 可以导入'; end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 or jsonb_array_length(p_rows)>5000 then raise exception '导入条数须为1至5000'; end if;
 perform pg_advisory_xact_lock(883124);
 if (select count(distinct x->>'code') from jsonb_array_elements(p_rows)x)<>jsonb_array_length(p_rows) then raise exception '房源编号重复'; end if;
 for r in select * from jsonb_array_elements(p_rows) loop
  select * into old from public.price_properties where code=r->>'code' for update;
  if found then
   if old.version is distinct from (r->>'expected_version')::integer then raise exception '数据已更新，请重新上传预览'; end if;
   if (old.store,old.team,old.estate,old.room) is distinct from (r->>'store',r->>'team',r->>'estate',r->>'room') then raise exception '房源 % 的归属或描述与系统不一致，已取消整批导入',old.code; end if;
   if old.quote<>(r->>'quote')::numeric or old.floor<>(r->>'floor')::numeric then
    update public.price_properties set quote=(r->>'quote')::numeric,floor=(r->>'floor')::numeric,status='pending',note='批次导入：'||p_filename where code=old.code;
   end if;
  else
   if r->>'expected_version' is not null then raise exception '数据已变化，请重新上传'; end if;
   insert into public.price_properties(code,store,team,estate,room,quote,floor)values(r->>'code',r->>'store',r->>'team',r->>'estate',r->>'room',(r->>'quote')::numeric,(r->>'floor')::numeric);
  end if;
  n=n+1;
 end loop;
 insert into public.price_imports(filename,rows)values(p_filename,n);
end $$;
revoke all on function public.price_review(text,integer,numeric,numeric,text,boolean),public.price_import(jsonb,text) from public,anon;
grant execute on function public.price_review(text,integer,numeric,numeric,text,boolean),public.price_import(jsonb,text) to authenticated;
alter table public.price_properties add constraint price_finite check(quote <> 'NaN'::numeric and floor <> 'NaN'::numeric);
