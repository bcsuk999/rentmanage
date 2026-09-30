'use strict';

const dns = require('node:dns');
const mongoose = require('mongoose');
const Admin = require('../models/Admin');
const Member = require('../models/Member');
const Payment = require('../models/Payment');
const RentPeriod = require('../models/RentPeriod');
const Room = require('../models/Room');

// Atlas connection strings are resolved through an SRV lookup. Some networks /
// resolvers refuse SRV queries, so point Node at public resolvers unless the
// operator overrides them. (Same approach as the backendLedger service.)
const dnsServers = (process.env.MONGODB_DNS_SERVERS || '8.8.8.8,1.1.1.1')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
dns.setServers(dnsServers);

/**
 * Bring the collection indexes in line with the schemas: builds anything new and
 * drops indexes the schemas no longer declare (several single-field indexes became
 * compound prefixes, which is cheaper to maintain on every write).
 */
async function syncIndexes() {
  const models = [Room, Member, RentPeriod, Payment, Admin];
  for (const model of models) {
    // syncIndexes() resolves with the dropped index names.
    const dropped = await model.syncIndexes();
    const removed = Array.isArray(dropped) ? dropped.length : 0;
    console.log(
      `Indexes synced for ${model.modelName} (${model.schema.indexes().length} defined${removed ? `, ${removed} removed` : ''})`
    );
  }
}

async function connectDb() {
  const uri = process.env.MONGODB_URI;
  if (!uri) {
    throw new Error('MONGODB_URI is not set. Add it to your .env file.');
  }
  mongoose.set('strictQuery', true);
  await mongoose.connect(uri, {
    serverSelectionTimeoutMS: 15000,
  });
  console.log(`MongoDB connected: ${mongoose.connection.host}/${mongoose.connection.name}`);
  await syncIndexes();
  return mongoose.connection;
}

module.exports = connectDb;
module.exports.syncIndexes = syncIndexes;
