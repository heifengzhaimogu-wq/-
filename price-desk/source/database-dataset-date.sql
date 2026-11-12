alter table public.desk_batches add column dataset_date date;
create function desk_private.import_dated(p_name text,p_due date,p_rows jsonb,p_mode text,p_source text,p_date date)returns uuid language plpgsql security definer set search_path='' as $$
declare batch uuid;
begin
 if (desk_private.me()).role is distinct from 'coordinator' then raise exception '仅推进负责人可以导入数据';end if;
 batch=desk_private.import_managed(p_name,p_due,p_rows,p_mode,p_source);
 update public.desk_batches set dataset_date=coalesce(p_date,(now()at time zone 'Asia/Shanghai')::date)where id=batch;
 return batch;
end $$;
create function public.desk_import_dated(p_name text,p_due date,p_rows jsonb,p_mode text,p_source text,p_date date)returns uuid language sql security invoker set search_path='' as $$select desk_private.import_dated(p_name,p_due,p_rows,p_mode,p_source,p_date)$$;
revoke all on function desk_private.import_dated(text,date,jsonb,text,text,date),public.desk_import_dated(text,date,jsonb,text,text,date)from public,anon;
grant execute on function desk_private.import_dated(text,date,jsonb,text,text,date),public.desk_import_dated(text,date,jsonb,text,text,date)to authenticated;
