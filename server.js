'use strict';

const express = require('express');
const cors = require('cors');
require('dotenv').config();

const connectDb = require('./src/config/db');
const { requireAuth, requireRole } = require('./src/middleware/auth');

const authRoutes = require('./src/routes/auth');
const roomRoutes = require('./src/routes/rooms');
const memberRoutes = require('./src/routes/members');
const rentRoutes = require('./src/routes/rentPeriods');
const paymentRoutes = require('./src/routes/payments');
const reportRoutes = require('./src/routes/reports');
const settingsRoutes = require('./src/routes/settings');
const { ensureAdminFromEnv } = require('./src/services/adminService');

const app = express();

// Render (and most hosts) terminate TLS in front of the app.
if (process.env.NODE_ENV === 'production' || process.env.TRUST_PROXY === '1') {
  app.set('trust proxy', 1);
}

app.use(cors({ origin: (process.env.CORS_ORIGINS || '*').split(',').map((s) => s.trim()) }));
app.use(express.urlencoded({ extended: false, limit: '1mb' }));
app.use(express.json({ limit: '1mb' }));

app.get('/', (req, res) => {
  res.json({ name: 'rentmanage-api', version: '1.0.0', status: 'ok' });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

app.use('/api/auth', authRoutes);
app.use('/api/rooms', requireAuth, roomRoutes);
app.use('/api/members', requireAuth, memberRoutes);
app.use('/api/rent-periods', requireAuth, rentRoutes);
app.use('/api/payments', requireAuth, paymentRoutes);
app.use('/api/reports', requireAuth, reportRoutes);
app.use('/api/settings', requireAuth, requireRole('admin'), settingsRoutes);

app.use((req, res) => {
  res.status(404).json({ error: 'Not found.' });
});

app.use((err, req, res, _next) => {
  console.error(err);
  if (res.headersSent) return;
  res.status(err.status || 500).json({
    error: err.expose && err.message ? err.message : 'An unexpected error occurred.',
  });
});

const PORT = Number(process.env.PORT) || 3000;

async function start() {
  await connectDb();
  await ensureAdminFromEnv();
  return app.listen(PORT, () => {
    console.log(`Rent management API running on http://localhost:${PORT}`);
  });
}

if (require.main === module) {
  start().catch((err) => {
    console.error('Failed to start:', err.message);
    process.exit(1);
  });
}

module.exports = app;
module.exports.start = start;
