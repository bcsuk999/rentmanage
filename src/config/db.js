'use strict';

const dns = require('node:dns');
const mongoose = require('mongoose');

// Atlas connection strings are resolved through an SRV lookup. Some networks /
// resolvers refuse SRV queries, so point Node at public resolvers unless the
// operator overrides them. (Same approach as the backendLedger service.)
const dnsServers = (process.env.MONGODB_DNS_SERVERS || '8.8.8.8,1.1.1.1')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
dns.setServers(dnsServers);

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
  return mongoose.connection;
}

module.exports = connectDb;
