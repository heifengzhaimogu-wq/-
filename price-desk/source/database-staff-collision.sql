create function desk_private.staff_collision_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.desk_members m where m.email<>new.email and m.staff_suffix=right(new.staff_id,4) and (length(m.staff_id)=4 or length(new.staff_id)=4)) then
  raise exception '工号后四位与已登记员工重复，请先补全双方完整工号';
 end if;
 return new;
end $$;
revoke all on function desk_private.staff_collision_guard() from public;
create trigger desk_staff_collision before insert or update of staff_id on public.desk_members for each row execute function desk_private.staff_collision_guard();
