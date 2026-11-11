alter table public.desk_tasks add column issue_required boolean not null default false,add column issue_type text not null default '';
alter table public.desk_batches add column source_name text not null default '',add column import_mode text not null default 'full' check(import_mode in ('full','errors'));
create table public.desk_review_targets(
 period_type text not null check(period_type in ('week','month')),period_start date not null,store_scope text not null default '',
 target_rate numeric(5,2) not null check(target_rate between 0 and 100),target_count integer check(target_count>=0),updated_by uuid not null,updated_at timestamptz not null default now(),
 primary key(period_type,period_start,store_scope)
);
alter table public.desk_review_targets enable row level security;
revoke all on public.desk_review_targets from anon,authenticated;
grant select on public.desk_review_targets to authenticated;
create policy desk_target_read on public.desk_review_targets for select to authenticated using((desk_private.me()).email is not null and ((desk_private.me()).role='coordinator' or store_scope='' or store_scope=(desk_private.me()).store));
create function desk_private.target_save(p_type text,p_start date,p_store text,p_rate numeric,p_count integer) returns void language plpgsql security definer set search_path='' as $$
declare m public.desk_members;
begin
 m=desk_private.me();if m.email is null or m.role<>'coordinator' then raise exception '仅全司推进负责人可以设置目标';end if;
 if p_type not in ('week','month') or p_start is null or p_start<>date_trunc(p_type,p_start::timestamp)::date then raise exception '请选择有效的周一或月初作为目标期间';end if;
 insert into public.desk_review_targets(period_type,period_start,store_scope,target_rate,target_count,updated_by)values(p_type,p_start,coalesce(trim(p_store),''),p_rate,p_count,auth.uid())
 on conflict(period_type,period_start,store_scope)do update set target_rate=excluded.target_rate,target_count=excluded.target_count,updated_by=excluded.updated_by,updated_at=now();
end $$;
create function public.desk_target_save(p_type text,p_start date,p_store text,p_rate numeric,p_count integer default null) returns void language sql security invoker set search_path='' as $$select desk_private.target_save(p_type,p_start,p_store,p_rate,p_count)$$;
create function desk_private.import_managed(p_name text,p_due date,p_rows jsonb,p_mode text,p_source text) returns uuid language plpgsql security definer set search_path='' as $$
declare batch uuid;
begin
 if (desk_private.me()).role is distinct from 'coordinator' then raise exception '仅全司推进负责人可以导入';end if;
 if p_mode not in ('full','errors') then raise exception '未知导入类型';end if;
 batch=desk_private.import_tasks(p_name,p_due,p_rows);
 update public.desk_batches set source_name=left(coalesce(p_source,''),250),import_mode=p_mode where id=batch;
 update public.desk_tasks t set issue_required=(p_mode='errors' or coalesce((r->>'issue_required')::boolean,false)),
 issue_type=case when p_mode='errors' or coalesce((r->>'issue_required')::boolean,false) then case when r->>'issue_type' in ('报价异常','底价异常','价格不一致','信息待修正') then r->>'issue_type' else '来源标记异常' end else '' end
 from jsonb_array_elements(p_rows)r where t.batch_id=batch and t.code=trim(r->>'code');
 return batch;
end $$;
create function public.desk_import_managed(p_name text,p_due date,p_rows jsonb,p_mode text,p_source text) returns uuid language sql security invoker set search_path='' as $$select desk_private.import_managed(p_name,p_due,p_rows,p_mode,p_source)$$;
create function desk_private.issue_guard() returns trigger language plpgsql set search_path='' as $$
begin if new.issue_required and new.adjust_state='not_needed' then raise exception '来源已标记需整改，请提交调整并在处理后确认完成';end if;return new;end $$;
revoke all on function desk_private.issue_guard() from public;
create trigger desk_issue_guard before insert or update of issue_required,adjust_state on public.desk_tasks for each row execute function desk_private.issue_guard();
revoke all on function desk_private.target_save(text,date,text,numeric,integer),public.desk_target_save(text,date,text,numeric,integer),desk_private.import_managed(text,date,jsonb,text,text),public.desk_import_managed(text,date,jsonb,text,text) from public,anon;
grant execute on function desk_private.target_save(text,date,text,numeric,integer),public.desk_target_save(text,date,text,numeric,integer),desk_private.import_managed(text,date,jsonb,text,text),public.desk_import_managed(text,date,jsonb,text,text) to authenticated;
