import { z } from 'zod';

export const guestSchema = z.object({
  name: z.string().trim().min(1, 'Name is required').max(120),
  phone: z.string().trim().max(20).optional().or(z.literal('')),
  age_category: z.enum(['adult', 'child', 'infant']),
  gender: z.string().optional(),
  relationship: z.string().max(100).optional(),
  arrival_date: z.string().nullable().optional(),
  departure_date: z.string().nullable().optional(),
  persons_count: z.coerce.number().int().min(1).max(20),
  special_notes: z.string().max(1000).optional(),
  family_group_id: z.string().uuid().nullable().optional(),
}).refine(
  (v) => !v.arrival_date || !v.departure_date || v.departure_date >= v.arrival_date,
  { message: 'Departure must be on or after arrival', path: ['departure_date'] },
);

export const groupSchema = z.object({
  name: z.string().trim().min(1).max(120),
  parent_id: z.string().uuid().nullable(),
  relationship_label: z.string().max(100).optional(),
});

export const roomSchema = z.object({
  room_number: z.string().trim().min(1).max(30),
  room_type: z.string().min(1),
  bed_capacity: z.coerce.number().int().min(1).max(30),
  hotel_id: z.string().uuid(),
  floor_id: z.string().uuid().nullable(),
  facilities: z.array(z.string()).default([]),
});
