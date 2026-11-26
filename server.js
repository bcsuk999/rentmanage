'use strict';

require('./src/config/timezone');

const express = require('express');
const cors = require('cors');
require('dotenv').config();

const connectDb = require('./src/config/db');
const { requireAuth } = require('./src/middleware/auth');

const authRoutes = require('./src/routes/auth');
const roomRoutes = require('./src/routes/rooms');
const memberRoutes = require('./src/routes/members');
const rentRoutes = require('./src/routes/rentPeriods');
const paymentRoutes = require('./src/routes/payments');
const landlordRoutes = require('./src/routes/landlord');
const overdueRoutes = require('./src/routes/overdue');
const settingsRoutes = require('./src/routes/settings');
const { ensureAdminFromEnv, ensureLandlordFromEnv } = require('./src/services/landlordService');
const { runPeriodMaintenance } = require('./src/services/rentService');

const app = express();

// Render (and most hosts) terminate TLS in front of the app.
if (process.env.NODE_ENV === 'production' || process.env.TRUST_PROXY === '1') {
  app.set('trust proxy', 1);
}

// CORS_ORIGINS="*" (default) opens the API to every origin, e.g. a Flutter
// web app on a random localhost port. NOTE: the `cors` package only treats
// the plain string '*' as a wildcard — an array like ['*'] matches nothing,
// so resolve it explicitly here.
const allowedOrigins = (process.env.CORS_ORIGINS || '*')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
app.use(cors({ origin: allowedOrigins.includes('*') ? '*' : allowedOrigins }));
app.use(express.urlencoded({ extended: false, limit: '1mb' }));
app.use(express.json({ limit: '1mb' }));

app.get('/', (req, res) => {
  res.json({ name: 'rentmanage-api', version: '1.0.0', status: 'ok' });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

app.use('/api/auth', authRoutes);
app.use('/api/landlord', requireAuth, landlordRoutes);
app.use('/api/rooms', requireAuth, roomRoutes);
app.use('/api/members', requireAuth, memberRoutes);
app.use('/api/rent-periods', requireAuth, rentRoutes);
app.use('/api/payments', requireAuth, paymentRoutes);
app.use('/api/overdue', requireAuth, overdueRoutes);
app.use('/api/settings', requireAuth, settingsRoutes);

app.use((req, res) => {
  const message = `Route ${req.method} ${req.originalUrl} not found.`;
  res.status(404).json({ error: message, message });
});

app.use((err, req, res, _next) => {
  console.error(err);
  if (res.headersSent) return;
  res.status(err.status || 500).json({
    error: err.expose && err.message ? err.message : 'An unexpected error occurred.',
  });
});

const PORT = Number(process.env.PORT) || 3000;
const IST_OFFSET_MS = 330 * 60 * 1000; // UTC+5:30, no DST

function msUntilNextIstTime(hour, minute) {
  const now = Date.now();
  const istNow = now + IST_OFFSET_MS;
  const d = new Date(istNow);
  const next = new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), hour, minute, 0, 0)
  );
  if (next.getTime() <= istNow) next.setUTCDate(next.getUTCDate() + 1);
  return next.getTime() - istNow;
}

function scheduleDailyPeriodMaintenance(hour = 0, minute = 30) {
  const delay = msUntilNextIstTime(hour, minute);
  setTimeout(async () => {
    try {
      const r = await runPeriodMaintenance();
      console.log(
        `Scheduled period maintenance: ${r.landlords} landlord(s), ${r.created} period(s) created, ${r.overdueRefreshed} overdue flip(s)`
      );
    } catch (err) {
      console.error('Scheduled period maintenance failed:', err.message);
    } finally {
      scheduleDailyPeriodMaintenance(hour, minute);
    }
  }, delay).unref();
  console.log(
    `Next period maintenance scheduled in ${Math.round(delay / 60000)} min (IST ${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')})`
  );
}

async function start() {
  await connectDb();
  await ensureLandlordFromEnv();
  await ensureAdminFromEnv();
  const server = app.listen(PORT, () => {
    console.log(`Rent management API running on http://localhost:${PORT}`);
  });
  // Catch up if a scheduled run was missed (e.g. Render free tier spin-down).
  runPeriodMaintenance()
    .then((r) =>
      console.log(
        `Startup period maintenance: ${r.landlords} landlord(s), ${r.created} period(s) created, ${r.overdueRefreshed} overdue flip(s)`
      )
    )
    .catch((err) => console.error('Startup period maintenance failed:', err.message));
  // In-process daily schedule (no external cron service needed).
  scheduleDailyPeriodMaintenance(0, 30);
  return server;
}

if (require.main === module) {
  start().catch((err) => {
    console.error('Failed to start:', err.message);
    process.exit(1);
  });
}

module.exports = app;
module.exports.start = start;
