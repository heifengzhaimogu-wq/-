alter table public.desk_members add column store_lead text not null default '';
create table public.desk_access_limits(key_hash text primary key,window_start timestamptz not null default now(),attempts integer not null default 1);
alter table public.desk_access_limits enable row level security;
revoke all on public.desk_access_limits from public,anon,authenticated;
grant all on public.desk_access_limits to service_role;
create policy desk_access_private on public.desk_access_limits for all to authenticated using(false) with check(false);
create function public.desk_access_attempt(p_key text) returns boolean language plpgsql security invoker set search_path='' as $$
declare n integer;
begin
 insert into public.desk_access_limits(key_hash)values(p_key)on conflict(key_hash)do update set
 attempts=case when desk_access_limits.window_start<now()-interval '15 minutes' then 1 else desk_access_limits.attempts+1 end,
 window_start=case when desk_access_limits.window_start<now()-interval '15 minutes' then now() else desk_access_limits.window_start end returning attempts into n;
 return n<=15;
end $$;
revoke all on function public.desk_access_attempt(text) from public,anon,authenticated;
grant execute on function public.desk_access_attempt(text) to service_role;
create function desk_private.identity_context() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m public.desk_members;lead text;
begin
 m=desk_private.me();if m.email is null then raise exception '员工身份无效';end if;
 select string_agg(name,'、' order by name)into lead from public.desk_members where active and role='store' and store=m.store;
 return jsonb_build_object('store_lead',coalesce(nullif(m.store_lead,''),lead,''));
end $$;
create function public.desk_identity_context()returns jsonb language sql stable security invoker set search_path='' as $$select desk_private.identity_context()$$;
create function desk_private.staff_profile_save(p_staff text,p_name text,p_role text,p_store text,p_team text,p_active boolean,p_lead text)returns void language plpgsql security definer set search_path='' as $$
begin
 if (desk_private.me()).role is distinct from 'coordinator' then raise exception '仅推进负责人可设置员工档案';end if;
 perform desk_private.staff_save(p_staff,p_name,p_role,p_store,p_team,p_active);
 update public.desk_members set store_lead=left(trim(coalesce(p_lead,'')),100)where staff_id=upper(trim(p_staff));
end $$;
create function public.desk_staff_profile_save(p_staff text,p_name text,p_role text,p_store text,p_team text,p_active boolean,p_lead text)returns void language sql security invoker set search_path='' as $$select desk_private.staff_profile_save(p_staff,p_name,p_role,p_store,p_team,p_active,p_lead)$$;
revoke all on function desk_private.identity_context(),public.desk_identity_context(),desk_private.staff_profile_save(text,text,text,text,text,boolean,text),public.desk_staff_profile_save(text,text,text,text,text,boolean,text)from public,anon;
grant execute on function desk_private.identity_context(),public.desk_identity_context(),desk_private.staff_profile_save(text,text,text,text,text,boolean,text),public.desk_staff_profile_save(text,text,text,text,text,boolean,text)to authenticated;
revoke execute on function public.desk_staff_invite(text),public.desk_invite(text),desk_private.invite(text)from authenticated;
