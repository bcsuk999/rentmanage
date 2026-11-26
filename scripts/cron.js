'use strict';

/**
 * Background job: generate missing rent periods and sweep overdue statuses
 * for every landlord. Runs outside API requests so page loads never block on
 * database writes.
 *
 * Usage:
 *   node scripts/cron.js
 *
 * Schedule (example crontab, runs every hour):
 *   0 * * * * cd /path/to/rentapp && node scripts/cron.js >> logs/cron.log 2>&1
 */

const mongoose = require('mongoose');
const connectDb = require('../src/config/db');
const Landlord = require('../src/models/Landlord');
const {
  ensurePeriodsForActiveMembers,
  refreshOverdueStatuses,
} = require('../src/services/rentService');

async function run() {
  await connectDb();

  const landlords = await Landlord.find({}, '_id').lean();
  console.log(`Found ${landlords.length} landlord(s)`);

  for (const landlord of landlords) {
    const ownerId = landlord._id;
    console.log(`Processing owner ${ownerId}...`);

    const generated = await ensurePeriodsForActiveMembers({ ownerId });
    console.log(
      `  Periods: checked ${generated.members} members, created ${generated.created}`
    );

    const overdue = await refreshOverdueStatuses({ ownerId });
    console.log(`  Overdue sweep: flipped ${overdue} period(s) to Overdue`);
  }

  await mongoose.disconnect();
  console.log('Cron job finished.');
  process.exit(0);
}

run().catch((err) => {
  console.error('Cron job failed:', err);
  process.exit(1);
});
