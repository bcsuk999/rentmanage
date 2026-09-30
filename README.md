# Room Rent Manager

Room-first rent management for a single property owner: **ROOM → MEMBERS → RENT PERIOD → PAYMENTS → PAYMENT HISTORY**.

Single Node.js application (Express + Mongoose + server-rendered EJS). No separate frontend project, no build step. Installable as a PWA and usable on mobile.

## Requirements

- Node.js 20+ (developed and verified on Node 25)
- A MongoDB database (MongoDB Atlas or local `mongod`)

Stack: Express 5, Mongoose 9, EJS 6, express-session + connect-mongo 6, bcryptjs 3.

## Setup

```bash
npm install
cp .env.example .env      # then fill in MONGODB_URI, SESSION_SECRET
npm run seed              # creates the admin account from .env
npm start                 # http://localhost:3000
```

Useful scripts:

| Script | What it does |
| --- | --- |
| `npm start` | Runs the server |
| `npm run dev` | Runs with `node --watch` |
| `npm run seed` | Creates the admin account from `.env` (skips an existing one) |
| `npm run seed -- --demo` | Also creates sample rooms, members and payments |
| `npm run seed -- --reset-password` | Sets the existing admin's password to `ADMIN_PASSWORD` |
| `npm run icons` | Regenerates the PWA icon set |
| `npm run lint` | ESLint |

### Environment

| Variable | Purpose |
| --- | --- |
| `MONGODB_URI` | MongoDB connection string, e.g. `mongodb+srv://user:pass@cluster.mongodb.net/?appName=rentmanage` |
| `SESSION_SECRET` | Long random string used to sign session cookies |
| `PORT` | HTTP port (default `3000`) |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | Admin credentials. Used by `npm run seed`, and on server start to create the admin if it is missing |
| `ADMIN_NAME` / `ADMIN_CONTACT` | Admin display name and contact |
| `ALLOW_REGISTRATION` | `false` hides `/register` and disables self-service sign-up |

`.env` is gitignored. Never commit credentials.

## Accounts and roles

Two roles live in the same accounts collection:

| Role | Access |
| --- | --- |
| `admin` | Everything: rooms, members, rent periods, payments, close/reopen cycles, settings, accounts |
| `user` | Read-only: rooms, members, payments, reports, own account. No create/edit/delete, no settings |

- Sign in at `/login`; self-service sign-up at `/register` always creates a **viewer** account
  (`ALLOW_REGISTRATION=false` turns it off).
- An admin promotes or demotes accounts under *Settings → Accounts*. The last admin cannot be
  demoted, and you cannot remove your own admin access.
- Every write route is guarded server-side by `requireRole('admin')`, so a viewer posting directly
  gets a `403` — the hidden buttons are only cosmetic.
- The seeded/env admin is never overwritten at startup; change its password from *My account*.

## Room capacity

- Every room stores `capacity`, the maximum number of **active** members, and it is required when
  creating a room.
- Adding a member to a full room is rejected server-side; the room list shows `4 / 4` plus a **Full**
  pill, and the room page hides *Add member*.
- Capacity cannot be lowered below the number of members already in the room.
- Rooms created before this feature existed get a capacity backfilled to their current occupancy by
  `npm run seed`.

## How rent works

- Rent is **never** represented as a calendar month. Every rental period is a date range
  (`startDate` → `endDate`), e.g. `15 Sep 2026 → 14 Oct 2026`.
- Each member has their own cycle anchored to their **rent start date**, so two members in the
  same room can be on different cycles.
- Cycles are generated automatically for active members up to the current cycle (plus one cycle
  ahead, so advance payments can be recorded early). Generation never creates overlapping cycles
  (`unique index` on `memberId + startDate`).
- `pending = rentAmount − sum(payments)`, computed on the server and written back to the
  `RentPeriod` document on every change.
- Status: `Paid` (pending 0) → `Overdue` (period ended with pending) → `Partial` (some payment
  made) → `Pending` (nothing paid yet).

## Business rules enforced server-side

1. A room can hold multiple members; a member has one active room at a time.
2. Payments cannot exceed the pending amount of a rent period.
3. A payment date must fall inside the rent period it is recorded against.
4. Closed rent periods reject new payments until reopened.
5. A room with members or rent history cannot be deleted.
6. Members are **vacated** (status `inactive` + `vacatingDate`), never deleted; historical rent
   and payment records remain.
7. Aadhaar is optional and always displayed masked (`XXXX XXXX 1234`).
8. Every calculation, validation and status change happens on the server.

## PWA

- `src/public/manifest.webmanifest` — installable app with shortcuts (Rooms, Payments, Reports).
- `src/public/sw.js` — precaches the app shell (CSS/JS/icons/offline page) and serves
  stale-while-revalidate for those assets. Authenticated HTML is **not** cached, so tenant data
  never lands in the device cache; when the network drops, navigations fall back to `/offline`.
- Icons: `src/public/icons/` (192, 512, maskable 512, apple-touch-icon, SVG favicon), generated by
  `scripts/generate-icons.js`.
- Install on Android/Chrome: menu → *Install app* (an **Install app** button appears in the header
  when the browser offers it). On iOS: Share → *Add to Home Screen*.

PWA install and service workers require HTTPS in production (`localhost` is exempt).

## Deploy to Render

`render.yaml` is a ready-made blueprint (Node runtime, `npm ci --omit=dev` build, `npm start`,
`/health` health check). Either:

- **Blueprint:** Render dashboard → *New* → *Blueprint* → select this repo, then set `MONGODB_URI`
  (`sync: false` means Render prompts for it). `SESSION_SECRET` is generated automatically.
- **Manual:** create a *Web Service* for this repo and set **Build Method = Node**, Build Command
  `npm ci --omit=dev`, Start Command `npm start`, then add `MONGODB_URI` and `SESSION_SECRET` under
  *Environment*. Delete any Elixir build command (`mix phx.digest`) left over from a template.

`NODE_ENV=production` is set by the blueprint; the app then trusts the proxy (so the `secure`
session cookie is issued over Render's HTTPS), and refuses to boot without `SESSION_SECRET`.

The database is Atlas, so the admin user and demo data must already exist — run `npm run seed`
locally (or `npm run seed -- --demo`) against the same `MONGODB_URI` once.

## Database indexes

Indexes live in the schemas and are reconciled with MongoDB on every boot
(`Model.syncIndexes()` in `src/config/db.js`), which builds anything new and drops anything the
schemas no longer declare. Current set:

| Collection | Indexes |
| --- | --- |
| `rooms` | `roomNumberKey` unique (lower-cased room number, so lookups and prefix search are index-backed instead of case-insensitive regex), `status + roomNumberKey` (filtered list, sorted by room number) |
| `members` | `roomId + status + rentStartDate` (room rollup, capacity count), `status + rentStartDate` (period generation), `name`, `mobile`, `aadhaarNumber` |
| `rentperiods` | `memberId + startDate` unique (one cycle per member), `roomId + startDate + endDate + status` (room rollup and period list), `startDate + endDate + status` (range reports, current cycle) |
| `payments` | `rentPeriodId + paymentDate` (per-period totals), `memberId + paymentDate`, `roomId + paymentDate`, `paymentMethod + paymentDate` |
| `admins` | `username` unique, `role`, `role + createdAt` (accounts list) |

Redundant single-field indexes that were prefixes of a compound index were dropped, and the unused
`members.name_text` text index was removed (search runs on regex; one text index per collection also
blocks compound text indexes). No `name: 'text'` remains.

## Structure

```
server.js                  Express app, session, routes, role guards, error handling
src/config/db.js           Mongoose connection + index sync
src/models/                Room, Member, RentPeriod, Payment, Admin (+ indexes)
src/services/              rentService, roomService, memberService, paymentService, reportService, adminService
src/routes/                auth, public, rooms, members, rentPeriods, payments, reports, settings
src/middleware/auth.js     session guards, role guards, password rules
src/utils/                 dates, money formatting, validation, Aadhaar masking
src/views/                 EJS views (layout, partials, one folder per module)
src/public/                CSS, JS, PWA manifest, service worker, icons
```

## Security notes

- Passwords are bcrypt hashed (cost 12) and never logged or displayed.
- Sessions are stored in MongoDB (`connect-mongo`), cookies are `httpOnly`, `sameSite=lax`, and
  `Secure` only when the request is really HTTPS (`secure: 'auto'` + `trust proxy`).
- The session is regenerated on login and destroyed on logout.
- Privileged routes are guarded by role server-side, not just hidden in the UI.
- All input is validated server-side; all money and status maths is server-side.
