-- Vivah: secure multi-tenant wedding guest and room management
create extension if not exists pgcrypto;
create extension if not exists btree_gist;
create type public.app_role as enum ('super_admin','room_manager','viewer');
create type public.guest_age_category as enum ('adult','child','infant');

create table public.weddings (
 id uuid primary key default gen_random_uuid(), name text not null, event_location text not null default 'Narnaul, Haryana',
 starts_on date not null default '2026-12-02', ends_on date not null default '2026-12-03', created_at timestamptz not null default now()
);
create table public.user_profiles (
 id uuid primary key references auth.users(id) on delete cascade, wedding_id uuid not null references public.weddings(id) on delete cascade,
 full_name text not null, role public.app_role not null default 'viewer', created_at timestamptz not null default now()
);
create table public.family_groups (
 id uuid primary key default gen_random_uuid(), wedding_id uuid not null references public.weddings(id) on delete cascade,
 parent_id uuid null references public.family_groups(id) on delete set null, name text not null check(length(trim(name)) between 1 and 120),
 relationship_label text, sort_order int not null default 0, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index family_groups_parent_idx on public.family_groups(parent_id);
create table public.guests (
 id uuid primary key default gen_random_uuid(), wedding_id uuid not null references public.weddings(id) on delete cascade,
 family_group_id uuid null references public.family_groups(id) on delete set null, name text not null check(length(trim(name)) between 1 and 120),
 phone text, age_category public.guest_age_category not null default 'adult', gender text, relationship text,
 arrival_date date, departure_date date, persons_count int not null default 1 check(persons_count between 1 and 20), special_notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(arrival_date is null or departure_date is null or departure_date >= arrival_date)
);
create index guests_wedding_name_idx on public.guests(wedding_id, lower(name));
create index guests_phone_idx on public.guests(wedding_id, phone);
create table public.hotels (
 id uuid primary key default gen_random_uuid(), wedding_id uuid not null references public.weddings(id) on delete cascade,
 name text not null, address text, contact_name text, contact_phone text, created_at timestamptz not null default now()
);
create table public.floors (
 id uuid primary key default gen_random_uuid(), wedding_id uuid not null references public.weddings(id) on delete cascade,
 hotel_id uuid not null references public.hotels(id) on delete cascade, name text not null, floor_number int
);
create table public.rooms (
 id uuid primary key default gen_random_uuid(), wedding_id uuid not null references public.weddings(id) on delete cascade,
 hotel_id uuid not null references public.hotels(id) on delete cascade, floor_id uuid references public.floors(id) on delete set null,
 room_number text not null, room_type text not null default 'Standard', bed_capacity int not null check(bed_capacity between 1 and 30),
 facilities text[] not null default '{}', is_active boolean not null default true, created_at timestamptz not null default now(),
 unique(hotel_id, room_number)
);
create table public.room_allocations (
 id uuid primary key default gen_random_uuid(), wedding_id uuid not null references public.weddings(id) on delete cascade,
 guest_id uuid not null references public.guests(id) on delete cascade, room_id uuid not null references public.rooms(id) on delete restrict,
 persons_count int not null check(persons_count between 1 and 20), start_date date not null, end_date date not null,
 created_by uuid references auth.users(id) default auth.uid(), created_at timestamptz not null default now(), check(end_date > start_date)
);
create index allocations_room_dates_idx on public.room_allocations(room_id,start_date,end_date);
create index allocations_guest_dates_idx on public.room_allocations(guest_id,start_date,end_date);
create table public.lookup_tokens (
 id uuid primary key default gen_random_uuid(), wedding_id uuid not null references public.weddings(id) on delete cascade,
 guest_id uuid not null references public.guests(id) on delete cascade, token_hash text not null unique,
 expires_at timestamptz, revoked_at timestamptz, created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table public.activity_logs (
 id bigint generated always as identity primary key, wedding_id uuid not null references public.weddings(id) on delete cascade,
 actor_id uuid references auth.users(id), action text not null, table_name text not null, record_id text,
 old_data jsonb, new_data jsonb, created_at timestamptz not null default now()
);

-- Prevent cross-wedding foreign-key references and cyclic family trees.
create or replace function public.validate_wedding_links() returns trigger
language plpgsql security definer set search_path=public as $$
declare
  linked_wedding uuid;
  cycle_found boolean;
begin
  -- Keep NEW field references inside table-specific branches. PostgreSQL trigger
  -- records have different fields for each table.
  if tg_table_name = 'family_groups' then
    if new.parent_id is not null then
      select wedding_id into linked_wedding
      from public.family_groups where id = new.parent_id;
      if linked_wedding is distinct from new.wedding_id then
        raise exception 'Parent family group must belong to the same wedding';
      end if;

      with recursive ancestors(id, parent_id) as (
        select id, parent_id from public.family_groups where id = new.parent_id
        union all
        select f.id, f.parent_id
        from public.family_groups f join ancestors a on f.id = a.parent_id
      )
      select exists(select 1 from ancestors where id = new.id)
      into cycle_found;

      if cycle_found then
        raise exception 'Family hierarchy cannot contain a cycle';
      end if;
    end if;

  elsif tg_table_name = 'guests' then
    if new.family_group_id is not null then
      select wedding_id into linked_wedding
      from public.family_groups where id = new.family_group_id;
      if linked_wedding is distinct from new.wedding_id then
        raise exception 'Family group must belong to the same wedding';
      end if;
    end if;

  elsif tg_table_name = 'floors' then
    select wedding_id into linked_wedding
    from public.hotels where id = new.hotel_id;
    if linked_wedding is distinct from new.wedding_id then
      raise exception 'Hotel must belong to the same wedding';
    end if;

  elsif tg_table_name = 'rooms' then
    select wedding_id into linked_wedding
    from public.hotels where id = new.hotel_id;
    if linked_wedding is distinct from new.wedding_id then
      raise exception 'Hotel must belong to the same wedding';
    end if;

    if new.floor_id is not null and not exists (
      select 1 from public.floors
      where id = new.floor_id and hotel_id = new.hotel_id
        and wedding_id = new.wedding_id
    ) then
      raise exception 'Floor must belong to the selected hotel and wedding';
    end if;
  end if;

  return new;
end
$$;

create trigger family_group_tenant_guard before insert or update on public.family_groups for each row execute function public.validate_wedding_links();
create trigger guest_tenant_guard before insert or update on public.guests for each row execute function public.validate_wedding_links();
create trigger floor_tenant_guard before insert or update on public.floors for each row execute function public.validate_wedding_links();
create trigger room_tenant_guard before insert or update on public.rooms for each row execute function public.validate_wedding_links();

create or replace function public.current_wedding_id() returns uuid language sql stable security definer set search_path=public as $$ select wedding_id from public.user_profiles where id=auth.uid() $$;
create or replace function public.current_role() returns public.app_role language sql stable security definer set search_path=public as $$ select role from public.user_profiles where id=auth.uid() $$;
create or replace function public.can_manage() returns boolean language sql stable security definer set search_path=public as $$ select coalesce(public.current_role() in ('super_admin','room_manager'),false) $$;

-- Enforce capacity under a row lock, including concurrent allocation requests.
create or replace function public.check_room_capacity() returns trigger language plpgsql security definer set search_path=public as $$
declare cap int; used int;
begin
 perform 1 from public.rooms where id=new.room_id for update;
 perform 1 from public.guests where id=new.guest_id for update;
 select bed_capacity into cap from public.rooms where id=new.room_id and wedding_id=new.wedding_id and is_active=true;
 if cap is null then raise exception 'Room is unavailable'; end if;
 select coalesce(sum(persons_count),0) into used from public.room_allocations
 where room_id=new.room_id and id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
 and daterange(start_date,end_date,'[)') && daterange(new.start_date,new.end_date,'[)');
 if used + new.persons_count > cap then raise exception 'Room capacity exceeded: % beds available', greatest(cap-used,0); end if;
 select coalesce(sum(persons_count),0) into used from public.room_allocations where guest_id=new.guest_id and id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid) and daterange(start_date,end_date,'[)') && daterange(new.start_date,new.end_date,'[)');
 if used + new.persons_count > (select persons_count from public.guests where id=new.guest_id) then raise exception 'Allocated persons exceed this guest record person count'; end if;
 if not exists(select 1 from public.guests where id=new.guest_id and wedding_id=new.wedding_id) then raise exception 'Guest does not belong to this wedding'; end if;
 return new;
end $$;
create trigger room_capacity_guard before insert or update on public.room_allocations for each row execute function public.check_room_capacity();

create or replace function public.audit_row_change() returns trigger language plpgsql security definer set search_path=public as $$
declare wid uuid; rid text; oldj jsonb; newj jsonb;
begin
 if tg_op='DELETE' then oldj=to_jsonb(old); wid=(oldj->>'wedding_id')::uuid; rid=oldj->>'id';
 elsif tg_op='UPDATE' then oldj=to_jsonb(old); newj=to_jsonb(new); wid=(newj->>'wedding_id')::uuid; rid=newj->>'id';
 else newj=to_jsonb(new); wid=(newj->>'wedding_id')::uuid; rid=newj->>'id'; end if;
 insert into public.activity_logs(wedding_id,actor_id,action,table_name,record_id,old_data,new_data)
 values(wid,auth.uid(),tg_op,tg_table_name,rid,oldj,newj);
 if tg_op='DELETE' then return old; else return new; end if;
end $$;
do $$ declare t text; begin foreach t in array array['family_groups','guests','hotels','floors','rooms','room_allocations','lookup_tokens'] loop
 execute format('create trigger audit_%I after insert or update or delete on public.%I for each row execute function public.audit_row_change()',t,t); end loop; end $$;

-- Create private lookup credentials. Only the token hash is stored; raw token is returned once.
create or replace function public.create_guest_lookup(p_guest_id uuid,p_expires_at timestamptz default null)
returns text language plpgsql security definer set search_path=public as $$
declare raw_token text; wid uuid;
begin
 if not public.can_manage() then raise exception 'Not authorized'; end if;
 select wedding_id into wid from public.guests where id=p_guest_id and wedding_id=public.current_wedding_id();
 if wid is null then raise exception 'Guest not found'; end if;
 raw_token=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.lookup_tokens(wedding_id,guest_id,token_hash,expires_at,created_by)
 values(wid,p_guest_id,encode(extensions.digest(raw_token,'sha256'),'hex'),p_expires_at,auth.uid());
 return raw_token;
end $$;
create or replace function public.lookup_guest(p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
 select jsonb_build_object('guest',jsonb_build_object('name',g.name,'arrival_date',g.arrival_date,'departure_date',g.departure_date,'family',fg.name),
 'allocations',coalesce((select jsonb_agg(jsonb_build_object('room_number',r.room_number,'hotel',h.name,'floor',f.name,'start_date',a.start_date,'end_date',a.end_date))
 from public.room_allocations a join public.rooms r on r.id=a.room_id join public.hotels h on h.id=r.hotel_id left join public.floors f on f.id=r.floor_id
 where a.guest_id=g.id), '[]'::jsonb)) into result
 from public.lookup_tokens t join public.guests g on g.id=t.guest_id left join public.family_groups fg on fg.id=g.family_group_id
 where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and (t.expires_at is null or t.expires_at>now());
 return result;
end $$;

-- Prevent reducing a party or room below its already-booked concurrent occupancy.
create or replace function public.guard_guest_party_size() returns trigger language plpgsql security definer set search_path=public as $$
declare peak int;
begin
 if new.persons_count < old.persons_count then
  perform 1 from public.guests where id=new.id for update;
  select coalesce(max(used),0) into peak from (select d.day, sum(a.persons_count) as used from
   (select start_date as day from public.room_allocations where guest_id=new.id union select (end_date-1) as day from public.room_allocations where guest_id=new.id) d
   join public.room_allocations a on a.guest_id=new.id and a.start_date<=d.day and a.end_date>d.day group by d.day) occupancy;
  if peak>new.persons_count then raise exception 'Cannot reduce party size below already allocated persons (%)',peak; end if;
 end if;
 return new;
end $$;
create trigger guest_party_size_guard before update of persons_count on public.guests for each row execute function public.guard_guest_party_size();

create or replace function public.guard_room_bed_capacity() returns trigger language plpgsql security definer set search_path=public as $$
declare peak int;
begin
 if new.bed_capacity < old.bed_capacity then
  select coalesce(max(used),0) into peak from (select d.day, sum(a.persons_count) as used from
   (select start_date as day from public.room_allocations where room_id=new.id union select (end_date-1) as day from public.room_allocations where room_id=new.id) d
   join public.room_allocations a on a.room_id=new.id and a.start_date<=d.day and a.end_date>d.day group by d.day) occupancy;
  if peak>new.bed_capacity then raise exception 'Cannot reduce room capacity below already allocated occupancy (%)',peak; end if;
 end if;
 return new;
end $$;
create trigger room_bed_capacity_guard before update of bed_capacity on public.rooms for each row execute function public.guard_room_bed_capacity();

-- RLS: all administrative data is private to authenticated members of the same wedding.
alter table public.weddings enable row level security; alter table public.user_profiles enable row level security;
alter table public.family_groups enable row level security; alter table public.guests enable row level security;
alter table public.hotels enable row level security; alter table public.floors enable row level security;
alter table public.rooms enable row level security; alter table public.room_allocations enable row level security;
alter table public.lookup_tokens enable row level security; alter table public.activity_logs enable row level security;
create policy wedding_member_read on public.weddings for select using(id=public.current_wedding_id());
create policy profile_read on public.user_profiles for select using(id=auth.uid() or wedding_id=public.current_wedding_id() and public.current_role()='super_admin');
create policy groups_read on public.family_groups for select using(wedding_id=public.current_wedding_id());
create policy groups_write on public.family_groups for all using(wedding_id=public.current_wedding_id() and public.can_manage()) with check(wedding_id=public.current_wedding_id() and public.can_manage());
create policy guests_read on public.guests for select using(wedding_id=public.current_wedding_id());
create policy guests_write on public.guests for all using(wedding_id=public.current_wedding_id() and public.can_manage()) with check(wedding_id=public.current_wedding_id() and public.can_manage());
create policy hotels_read on public.hotels for select using(wedding_id=public.current_wedding_id());
create policy hotels_write on public.hotels for all using(wedding_id=public.current_wedding_id() and public.current_role()='super_admin') with check(wedding_id=public.current_wedding_id() and public.current_role()='super_admin');
create policy floors_read on public.floors for select using(wedding_id=public.current_wedding_id());
create policy floors_write on public.floors for all using(wedding_id=public.current_wedding_id() and public.current_role()='super_admin') with check(wedding_id=public.current_wedding_id() and public.current_role()='super_admin');
create policy rooms_read on public.rooms for select using(wedding_id=public.current_wedding_id());
create policy rooms_write on public.rooms for all using(wedding_id=public.current_wedding_id() and public.current_role()='super_admin') with check(wedding_id=public.current_wedding_id() and public.current_role()='super_admin');
create policy allocations_read on public.room_allocations for select using(wedding_id=public.current_wedding_id());
create policy allocations_write on public.room_allocations for all using(wedding_id=public.current_wedding_id() and public.can_manage()) with check(wedding_id=public.current_wedding_id() and public.can_manage());
create policy tokens_read on public.lookup_tokens for select using(wedding_id=public.current_wedding_id() and public.current_role()='super_admin');
create policy tokens_write on public.lookup_tokens for all using(wedding_id=public.current_wedding_id() and public.current_role()='super_admin') with check(wedding_id=public.current_wedding_id() and public.current_role()='super_admin');
create policy logs_read on public.activity_logs for select using(wedding_id=public.current_wedding_id() and public.current_role()='super_admin');

-- Restrict the public token lookup function to an explicit token-only interface.
revoke all on function public.create_guest_lookup(uuid,timestamptz) from public, anon;
grant execute on function public.create_guest_lookup(uuid,timestamptz) to authenticated;
revoke all on function public.lookup_guest(text) from public;
grant execute on function public.lookup_guest(text) to anon, authenticated;

-- Realtime publication. Supabase creates this publication by default.
alter publication supabase_realtime add table public.family_groups, public.guests, public.hotels, public.floors, public.rooms, public.room_allocations;
