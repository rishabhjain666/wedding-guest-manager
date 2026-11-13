# Vivah — Wedding Guest & Room Allocation Manager

A responsive React + TypeScript PWA backed by Supabase/PostgreSQL for private wedding guest management, recursive family grouping and room allocation. Target event configuration: Jain family wedding, Narnaul, Haryana, 2–3 December 2026.

## Important deployment boundary

This repository contains the application source, SQL migration, optional development seed and deployment instructions. It is **not connected to a Supabase project**, and it has not been deployed to a public URL. No real guest data or credentials are included. A Supabase project, environment variables, an initial super-admin profile and a successful production build are required before it can be used for the wedding.

## Implemented application areas

- Supabase email/password authentication and invitation-only sign-in.
- Profile-to-wedding membership lookup and role-aware database access.
- Recursive family groups (`parent_id`) and individual guest records.
- Guest create, edit, delete, search, family filtering and CSV export.
- Hotel, floor and room hierarchy; room capacity cards and facilities.
- Room allocation create/remove, date ranges, guest/room search, hotel filter, PDF export and print view.
- Database-side room-capacity enforcement under a row lock; overlapping bookings are evaluated with half-open date ranges `[check-in, check-out)`.
- Guest-scoped private lookup links and QR generation; lookup function returns only one guest's room information, never the guest directory.
- Database audit triggers and Realtime refresh subscriptions.
- Installable PWA manifest and service-worker configuration.

## Prerequisites

- Node.js 20.19+ or 22.12+
- npm
- A Supabase project
- A deployment account on Vercel or Netlify

## Local setup

```bash
npm install
cp .env.example .env.local
```

Set the two values in `.env.local`:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

Apply the migration using Supabase CLI:

```bash
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
```

Alternatively, paste `supabase/migrations/0001_initial_schema.sql` into the Supabase SQL Editor and run it once. Do not run it twice without resetting the schema.

Start the app:

```bash
npm run dev
```

Production build and type check:

```bash
npm run typecheck
npm run build
npm run preview
```

## First-time Supabase provisioning

1. In Supabase Authentication, enable Email provider. Disable public signups after the initial administrator has been created; invite additional users from the dashboard or an admin-only provisioning workflow.
2. Create the first administrator in Authentication → Users.
3. Insert the corresponding profile row using the SQL Editor (replace the auth UUID):

```sql
insert into public.user_profiles(id, wedding_id, full_name, role)
select 'AUTH-USER-UUID', id, 'Wedding Super Admin', 'super_admin'
from public.weddings
where name = 'Jain Family Wedding';
```

4. Create the wedding workspace if not already present:

```sql
insert into public.weddings(name,event_location,starts_on,ends_on)
values ('Jain Family Wedding','Narnaul, Haryana','2026-12-02','2026-12-03');
```

5. Add hotel and floor records from the Rooms screen. The super admin role is required by the database policies for hotel/floor/room administration.
6. Invite each room manager/viewer as a Supabase Auth user, then insert a `user_profiles` row with the same `wedding_id` and the required role (`room_manager` or `viewer`). Never expose the service-role key in the browser.

## Optional development seed

Run `supabase/seed/seed.sql` only in a separate development Supabase project. It creates a demo wedding, hotel, floor, rooms, family groups and sample guests. It does not create an auth user or profile. Do not run it in the live wedding project.

## Roles and access

- `super_admin`: full wedding administration, hotel/room setup, private lookup link creation and audit log access.
- `room_manager`: guest/family management and room allocation operations.
- `viewer`: read-only access.

The database policies are the security boundary. UI visibility is not treated as authorization. All rows are scoped by `current_wedding_id()` and protected with RLS. Lookup access is a separate high-entropy bearer token: only a SHA-256 token hash is stored; revoke a link by setting `revoked_at` on its `lookup_tokens` row, or let it expire. The current UI creates links expiring on 5 December 2026.

## Data model and allocation semantics

- A family tree is represented by `family_groups.parent_id`; nesting is recursive and not limited to a fixed depth.
- A guest row represents a person or a party using `persons_count`. Use separate individual guest rows where different names/relationships/phones are needed.
- An allocation records a number of persons for one guest record in one room for a date range. A family can be split by making multiple guest records or partial allocations against a party record.
- Check-out is exclusive: a stay from 2 Dec to 4 Dec occupies the room for nights 2 and 3.
- A trigger locks the room and guest rows and rejects concurrent room overbooking and allocation of more persons than the guest party contains.

## Deployment

### Vercel

1. Push this repository to a private GitHub repository.
2. Import it into Vercel.
3. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in Project Settings → Environment Variables.
4. Build command: `npm run build`; output directory: `dist`.
5. Deploy and add the production domain to Supabase Auth → URL Configuration (Site URL and Redirect URLs).
6. Enforce HTTPS (Vercel provides it) and test sign-in, RLS and private lookup on a real phone.

### Netlify

- Build command: `npm run build`
- Publish directory: `dist`
- Add the same two environment variables.
- Add a single-page-app rewrite (`/* /index.html 200`) and configure the deployed domain in Supabase Auth URL settings.

## Backups and operations

- Enable Supabase automated backups / point-in-time recovery according to the selected plan.
- Export a periodic database backup before the event; CSV/PDF exports from the UI are operational reports, not database backups.
- Use a dedicated development project for seed data and testing.
- Rotate compromised user credentials and revoke lookup tokens immediately.
- Review Supabase Auth users and `user_profiles` before granting access.

## Verification status / known gaps

The source has been authored, but package installation timed out in the build environment. Therefore a successful TypeScript check, production build, database migration execution, browser test, multi-user Realtime test, RLS penetration test, concurrent allocation test and live deployment have **not** been verified here. Do not treat this source as production-approved until those checks pass against a real Supabase project.

Current UI limitations to resolve before production: hotel/floor creation uses browser prompts; viewer/room-manager interface is not fully role-tailored; no in-app team invitation flow or lookup-token revocation screen exists; guest PDF export is not yet implemented; service-worker offline mode caches the app shell only and does not queue writes offline. The SQL migration should be reviewed by a database engineer before production, especially RLS, function grants and operational backup settings.
