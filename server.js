'use strict';

const path = require('path');
const express = require('express');
const session = require('express-session');
const { MongoStore } = require('connect-mongo');
const methodOverride = require('method-override');
const expressLayouts = require('express-ejs-layouts');
require('dotenv').config();

const connectDb = require('./src/config/db');
const { attachUser, requireAuth } = require('./src/middleware/auth');
const { flash, flashFor } = require('./src/utils/flash');

const authRoutes = require('./src/routes/auth');
const publicRoutes = require('./src/routes/public');
const dashboardRoutes = require('./src/routes/dashboard');
const roomRoutes = require('./src/routes/rooms');
const memberRoutes = require('./src/routes/members');
const rentRoutes = require('./src/routes/rentPeriods');
const paymentRoutes = require('./src/routes/payments');
const reportRoutes = require('./src/routes/reports');
const settingsRoutes = require('./src/routes/settings');
const { currency } = require('./src/utils/format');
const dates = require('./src/utils/dates');
const { maskAadhaar } = require('./src/utils/mask');

const app = express();
const viewsDir = path.join(__dirname, 'src', 'views');

app.set('view engine', 'ejs');
app.set('views', viewsDir);
app.set('layout', 'layouts/main');
app.use(expressLayouts);

app.use(express.urlencoded({ extended: false, limit: '1mb' }));
app.use(express.json({ limit: '1mb' }));
app.use(methodOverride('_method'));
app.use(express.static(path.join(__dirname, 'src', 'public')));

app.use(
  session({
    name: 'rentmanage.sid',
    secret: process.env.SESSION_SECRET || 'dev-only-insecure-secret',
    resave: false,
    saveUninitialized: false,
    rolling: true,
    store: MongoStore.create({
      mongoUrl: process.env.MONGODB_URI,
      collectionName: 'sessions',
      ttl: 60 * 60 * 8,
    }),
    cookie: {
      httpOnly: true,
      sameSite: 'lax',
      secure: process.env.NODE_ENV === 'production',
      maxAge: 1000 * 60 * 60 * 8,
    },
  })
);

app.use(attachUser);

app.use((req, res, next) => {
  req.flash = flash.bind(null, req);
  res.locals.currentPath = req.path;
  res.locals.currentUser = req.session.admin || null;
  res.locals.flash = req.session.flash || null;
  res.locals.currency = currency;
  res.locals.formatDate = dates.formatDate;
  res.locals.formatDateShort = dates.formatDateShort;
  res.locals.formatDateRange = dates.formatDateRange;
  res.locals.toDateInput = dates.toDateInput;
  res.locals.maskAadhaar = maskAadhaar;
  res.locals.query = req.query || {};
  res.locals.statusClass = flashFor;
  delete req.session.flash;
  next();
});

app.use(publicRoutes);
app.use(authRoutes);
app.use('/', requireAuth, dashboardRoutes);
app.use('/rooms', requireAuth, roomRoutes);
app.use('/members', requireAuth, memberRoutes);
app.use('/rent-periods', requireAuth, rentRoutes);
app.use('/payments', requireAuth, paymentRoutes);
app.use('/reports', requireAuth, reportRoutes);
app.use('/settings', requireAuth, settingsRoutes);

app.use((req, res) => {
  res.status(404).render('error', {
    title: 'Not found',
    message: 'The page you requested does not exist.',
  });
});

app.use((err, req, res, _next) => {
  console.error(err);
  if (res.headersSent) return;
  res.status(err.status || 500).render('error', {
    title: 'Something went wrong',
    message: err.expose ? err.message : 'An unexpected error occurred.',
  });
});

const PORT = Number(process.env.PORT) || 3000;

async function start() {
  await connectDb();
  return app.listen(PORT, () => {
    console.log(`Rent management app running on http://localhost:${PORT}`);
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
