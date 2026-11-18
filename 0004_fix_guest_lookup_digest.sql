-- Fix guest pass verification when pgcrypto is installed in the Supabase extensions schema.
-- Replaces the lookup function only; existing guest tokens remain valid.

create or replace function public.lookup_guest(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return null;
  end if;

  select jsonb_build_object(
    'guest',
    jsonb_build_object(
      'name', g.name,
      'arrival_date', g.arrival_date,
      'departure_date', g.departure_date,
      'family', fg.name
    ),
    'allocations',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'room_number', r.room_number,
            'hotel', h.name,
            'floor', f.name,
            'start_date', a.start_date,
            'end_date', a.end_date
          )
        )
        from public.room_allocations a
        join public.rooms r on r.id = a.room_id
        join public.hotels h on h.id = r.hotel_id
        left join public.floors f on f.id = r.floor_id
        where a.guest_id = g.id
      ),
      '[]'::jsonb
    )
  )
  into result
  from public.lookup_tokens t
  join public.guests g on g.id = t.guest_id
  left join public.family_groups fg on fg.id = g.family_group_id
  where t.token_hash = encode(
    extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'::text),
    'hex'
  )
    and t.revoked_at is null
    and (t.expires_at is null or t.expires_at > now());

  return result;
end;
$$;

revoke all on function public.lookup_guest(text) from public;
grant execute on function public.lookup_guest(text) to anon, authenticated;
