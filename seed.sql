-- Optional demo seed. Run only in a dedicated development Supabase project.
-- Create the wedding first, then create an auth user and add their user_profiles row manually.
insert into public.weddings(id,name,event_location,starts_on,ends_on)
values('a0000000-0000-4000-8000-000000000001','Jain Family Wedding','Narnaul, Haryana','2026-12-02','2026-12-03')
on conflict(id) do nothing;
insert into public.hotels(id,wedding_id,name,address) values
('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','Demo Hotel','Narnaul, Haryana') on conflict(id) do nothing;
insert into public.floors(id,wedding_id,hotel_id,name,floor_number) values
('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','Ground Floor',0) on conflict(id) do nothing;
insert into public.rooms(id,wedding_id,hotel_id,floor_id,room_number,room_type,bed_capacity,facilities) values
('d0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','G-01','Family',4,array['AC','Attached bathroom']),
('d0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','G-02','Double',2,array['AC']) on conflict(id) do nothing;

insert into public.family_groups(id,wedding_id,parent_id,name,relationship_label,sort_order) values
('e0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001',null,'Deepesh Mama Family','Main family',1),
('e0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','Children','Subgroup',1)
on conflict(id) do nothing;
insert into public.guests(id,wedding_id,family_group_id,name,phone,age_category,relationship,arrival_date,departure_date,persons_count) values
('f0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','Deepesh Mama','', 'adult','Mama','2026-12-02','2026-12-04',1),
('f0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','Mami','', 'adult','Mami','2026-12-02','2026-12-04',1)
on conflict(id) do nothing;
