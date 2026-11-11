alter table public.desk_prices add column original_quote numeric(14,2) not null,add column original_floor numeric(14,2) not null;
create function desk_private.price_baseline() returns trigger language plpgsql set search_path='' as $$
begin new.original_quote=new.quote;new.original_floor=new.floor;return new;end $$;
revoke all on function desk_private.price_baseline() from public;
create trigger desk_price_baseline before insert on public.desk_prices for each row execute function desk_private.price_baseline();
