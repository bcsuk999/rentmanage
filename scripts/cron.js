'use strict';

require('dotenv').config();
require('../src/config/timezone');

/**
 * Background job: generate missing rent periods and sweep overdue statuses
 * for every landlord. Runs outside API requests so page loads never block on
 * database writes.
 *
 * Usage:
 *   node scripts/cron.js
 *
 * Render Cron Job (recommended): daily after midnight IST.
 * Example crontab (UTC server): 30 18 * * *  (00:00 IST)
 */

const mongoose = require('mongoose');
const connectDb = require('../src/config/db');
const { runPeriodMaintenance } = require('../src/services/rentService');

async function run() {
  await connectDb();
  const result = await runPeriodMaintenance();
  console.log(
    `Period maintenance: ${result.landlords} landlord(s), ${result.created} period(s) created, ${result.overdueRefreshed} overdue flip(s)`
  );
  await mongoose.disconnect();
  console.log('Cron job finished.');
  process.exit(0);
}

run().catch((err) => {
  console.error('Cron job failed:', err);
  process.exit(1);
});
