-- Guest check-in ledger with partial family arrivals and departures.
-- Apply after 0001_initial_schema.sql and 0002_peak_occupancy_capacity.sql.

create table if not exists public.guest_checkins (
  guest_id uuid primary key references public.guests(id) on delete cascade,
  wedding_id uuid not null references public.weddings(id) on delete cascade,
  persons_arrived int not null default 0 check (persons_arrived >= 0),
  persons_departed int not null default 0 check (persons_departed >= 0 and persons_departed <= persons_arrived),
  first_arrived_at timestamptz,
  last_departed_at timestamptz,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

create index if not exists guest_checkins_wedding_idx
  on public.guest_checkins(wedding_id);

alter table public.guest_checkins enable row level security;

drop policy if exists guest_checkins_read on public.guest_checkins;
create policy guest_checkins_read on public.guest_checkins
  for select to authenticated
  using (wedding_id = public.current_wedding_id());

create or replace function public.record_guest_checkin(
  p_guest_id uuid,
  p_action text,
  p_count integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  guest_row public.guests%rowtype;
  checkin_row public.guest_checkins%rowtype;
  current_present integer;
begin
  if auth.uid() is null or not public.can_manage() then
    raise exception 'Not authorized';
  end if;

  if p_count is null or p_count < 1 then
    raise exception 'Person count must be at least one';
  end if;

  if p_action is null or p_action not in ('check_in', 'check_out') then
    raise exception 'Unsupported check-in action';
  end if;

  select * into guest_row
    from public.guests
   where id = p_guest_id
     and wedding_id = public.current_wedding_id()
   for update;

  if not found then
    raise exception 'Guest not found in this wedding';
  end if;

  insert into public.guest_checkins (guest_id, wedding_id, updated_by)
  values (guest_row.id, guest_row.wedding_id, auth.uid())
  on conflict (guest_id) do nothing;

  select * into checkin_row
    from public.guest_checkins
   where guest_id = guest_row.id
   for update;

  current_present := checkin_row.persons_arrived - checkin_row.persons_departed;

  if p_action = 'check_in' then
    if checkin_row.persons_arrived + p_count > guest_row.persons_count then
      raise exception 'Cannot check in more people than the registered party size (%)', guest_row.persons_count;
    end if;

    update public.guest_checkins
       set persons_arrived = persons_arrived + p_count,
           first_arrived_at = coalesce(first_arrived_at, now()),
           updated_by = auth.uid(),
           updated_at = now()
     where guest_id = guest_row.id
     returning * into checkin_row;
  else
    if p_count > current_present then
      raise exception 'Cannot check out more people than are currently present (%)', current_present;
    end if;

    update public.guest_checkins
       set persons_departed = persons_departed + p_count,
           last_departed_at = now(),
           updated_by = auth.uid(),
           updated_at = now()
     where guest_id = guest_row.id
     returning * into checkin_row;
  end if;

  return jsonb_build_object(
    'guest_id', checkin_row.guest_id,
    'persons_arrived', checkin_row.persons_arrived,
    'persons_departed', checkin_row.persons_departed,
    'persons_present', checkin_row.persons_arrived - checkin_row.persons_departed,
    'first_arrived_at', checkin_row.first_arrived_at,
    'last_departed_at', checkin_row.last_departed_at,
    'updated_at', checkin_row.updated_at
  );
end;
$$;

revoke all on function public.record_guest_checkin(uuid, text, integer) from public, anon;
grant execute on function public.record_guest_checkin(uuid, text, integer) to authenticated;
