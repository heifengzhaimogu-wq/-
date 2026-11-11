create table public.price_org_units (
 store text not null check(length(trim(store))>0),team text not null check(length(trim(team))>0),
 created_at timestamptz not null default now(),primary key(store,team)
);
insert into public.price_org_units(store,team) select distinct store,team from public.price_properties;
alter table public.price_org_units enable row level security;
revoke all on public.price_org_units from anon,authenticated;
grant select,insert,delete on public.price_org_units to authenticated;
create policy org_read on public.price_org_units for select to authenticated using(price_private.allowed(store,team));
create policy org_insert on public.price_org_units for insert to authenticated with check(price_private.hrbp());
create policy org_delete on public.price_org_units for delete to authenticated using(price_private.hrbp());
alter table public.price_properties add constraint price_property_org foreign key(store,team) references public.price_org_units(store,team);
alter table public.price_history add column old_store text,add column old_team text,add column old_estate text,add column old_room text,add column new_estate text,add column new_room text;
grant update(store,team,estate,room) on public.price_properties to authenticated;
create or replace function price_private.audit() returns trigger language plpgsql security definer set search_path='' as $$
declare base_changed boolean:=false;
begin
 if auth.uid() is null then raise exception 'Login required';end if;
 if TG_OP='UPDATE' then
  if new.code<>old.code then raise exception '不可更改房源编号';end if;
  base_changed=(new.store,new.team,new.estate,new.room) is distinct from (old.store,old.team,old.estate,old.room);
  if base_changed then
   if not price_private.hrbp() then raise exception '仅 HRBP 可以调整归属及基础资料';end if;
   if length(trim(new.note))=0 then raise exception '调整必须填写原因';end if;
   if not exists(select 1 from public.price_org_units where store=new.store and team=new.team) then raise exception '请先在店组管理中新增目标店组';end if;
   new.status='pending';
  end if;
  new.version=old.version+1;new.updated_at=now();
 else
  insert into public.price_org_units(store,team)values(new.store,new.team) on conflict do nothing;
 end if;
 insert into public.price_history(code,store,team,old_quote,new_quote,old_floor,new_floor,action,actor,note,old_store,old_team,old_estate,old_room,new_estate,new_room)
 values(new.code,new.store,new.team,case when TG_OP='UPDATE' then old.quote end,new.quote,case when TG_OP='UPDATE' then old.floor end,new.floor,
 case when TG_OP='INSERT' then '新增' when base_changed then '资料调整' when new.quote<>old.quote or new.floor<>old.floor then '价格变更' else '核对' end,
 auth.uid(),new.note,case when TG_OP='UPDATE' then old.store end,case when TG_OP='UPDATE' then old.team end,case when TG_OP='UPDATE' then old.estate end,case when TG_OP='UPDATE' then old.room end,new.estate,new.room);
 return new;
end $$;
create function price_private.org_delete_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not price_private.hrbp() then raise exception '仅 HRBP 可以维护店组';end if;
 if exists(select 1 from public.price_members where store=old.store and (team=old.team or role='store')) then raise exception '该店组仍有授权成员，请先调整成员权限';end if;
 return old;
end $$;
revoke all on function price_private.org_delete_guard() from public;
create trigger price_org_delete_guard before delete on public.price_org_units for each row execute function price_private.org_delete_guard();
create function public.price_admin_edit(p_code text,p_version integer,p_store text,p_team text,p_estate text,p_room text,p_quote numeric,p_floor numeric,p_note text)
returns void language plpgsql security invoker set search_path='' as $$
declare n integer;
begin
 if not price_private.hrbp() then raise exception '仅 HRBP 可以调整房源资料';end if;
 if length(trim(p_note))=0 then raise exception '请填写调整原因';end if;
 update public.price_properties set store=trim(p_store),team=trim(p_team),estate=trim(p_estate),room=trim(p_room),quote=p_quote,floor=p_floor,note=trim(p_note),status='pending'
 where code=p_code and version=p_version;
 get diagnostics n=row_count;
 if n<>1 then raise exception '房源已变化，请刷新后重试';end if;
end $$;
revoke all on function public.price_admin_edit(text,integer,text,text,text,text,numeric,numeric,text) from public,anon;
grant execute on function public.price_admin_edit(text,integer,text,text,text,text,numeric,numeric,text) to authenticated;
alter policy history_read on public.price_history to authenticated using(
 price_private.hrbp() or (action<>'资料调整' and price_private.allowed(store,team) and exists(select 1 from public.price_properties p where p.code=price_history.code and price_private.allowed(p.store,p.team)))
);
