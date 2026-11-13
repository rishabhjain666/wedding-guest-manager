export type Role = 'super_admin' | 'room_manager' | 'viewer';

export type FamilyGroup = {
  id: string;
  name: string;
  parent_id: string | null;
  relationship_label: string | null;
  sort_order: number;
};

export type Guest = {
  id: string;
  family_group_id: string | null;
  name: string;
  phone: string | null;
  age_category: 'adult' | 'child' | 'infant';
  gender: string | null;
  relationship: string | null;
  arrival_date: string | null;
  departure_date: string | null;
  persons_count: number;
  special_notes: string | null;
};

export type Room = {
  id: string;
  hotel_id: string;
  floor_id: string | null;
  room_number: string;
  room_type: string;
  bed_capacity: number;
  facilities: string[];
  is_active: boolean;
  hotel?: { name: string };
  floor?: { name: string };
};

export type Allocation = {
  id: string;
  guest_id: string;
  room_id: string;
  persons_count: number;
  start_date: string;
  end_date: string;
  guest?: Guest;
  room?: Room;
};
