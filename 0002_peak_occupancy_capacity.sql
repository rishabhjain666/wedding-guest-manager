-- Fix peak-overlap validation for room and guest allocations.
-- Allocation ranges are half-open [check-in, check-out): a guest checking out
-- on a date does not occupy that room on the same date another guest checks in.

create or replace function public.check_room_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cap int;
  used int;
begin
  -- Serialize allocations for the same room and guest before calculating peaks.
  perform 1 from public.rooms where id = new.room_id for update;
  perform 1 from public.guests where id = new.guest_id for update;

  select bed_capacity
    into cap
    from public.rooms
   where id = new.room_id
     and wedding_id = new.wedding_id
     and is_active = true;

  if cap is null then
    raise exception 'Room is unavailable';
  end if;

  -- Calculate the maximum simultaneous occupancy in the requested room
  -- during the proposed stay. Summing every overlapping booking is incorrect:
  -- two existing bookings may overlap the proposed stay but not each other.
  with relevant as (
    select greatest(start_date, new.start_date) as range_start,
           least(end_date, new.end_date) as range_end,
           persons_count
      from public.room_allocations
     where room_id = new.room_id
       and id is distinct from new.id
       and daterange(start_date, end_date, '[)') &&
           daterange(new.start_date, new.end_date, '[)')
  ),
  events as (
    select range_start as event_date, persons_count as delta from relevant
    union all
    select range_end as event_date, -persons_count as delta from relevant
  ),
  daily as (
    select event_date, sum(delta) as delta
      from events
     group by event_date
  ),
  running as (
    select sum(delta) over (order by event_date rows unbounded preceding) as occupied
      from daily
  )
  select coalesce(max(occupied), 0)
    into used
    from running;

  if used + new.persons_count > cap then
    raise exception 'Room capacity exceeded: % beds available',
      greatest(cap - used, 0);
  end if;

  if not exists (
    select 1
      from public.guests
     where id = new.guest_id
       and wedding_id = new.wedding_id
  ) then
    raise exception 'Guest does not belong to this wedding';
  end if;

  -- Enforce the guest party-size limit using peak simultaneous allocations,
  -- including intentional splits across multiple rooms.
  with relevant as (
    select greatest(start_date, new.start_date) as range_start,
           least(end_date, new.end_date) as range_end,
           persons_count
      from public.room_allocations
     where guest_id = new.guest_id
       and id is distinct from new.id
       and daterange(start_date, end_date, '[)') &&
           daterange(new.start_date, new.end_date, '[)')
  ),
  events as (
    select range_start as event_date, persons_count as delta from relevant
    union all
    select range_end as event_date, -persons_count as delta from relevant
  ),
  daily as (
    select event_date, sum(delta) as delta
      from events
     group by event_date
  ),
  running as (
    select sum(delta) over (order by event_date rows unbounded preceding) as occupied
      from daily
  )
  select coalesce(max(occupied), 0)
    into used
    from running;

  if used + new.persons_count >
     (select persons_count from public.guests where id = new.guest_id) then
    raise exception 'Allocated persons exceed this guest record person count';
  end if;

  return new;
end;
$$;
