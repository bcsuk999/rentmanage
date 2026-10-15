'use strict';

const bcrypt = require('bcryptjs');
const Landlord = require('../models/Landlord');
const Admin = require('../models/Admin');

/**
 * Creates the landlord described by LANDLORD_* env vars when missing.
 * Falls back to legacy ADMIN_* vars, and migrates the legacy admin account
 * (username login) into a landlord when the mobile matches, so existing
 * installs are not locked out by the mobile-login migration.
 */
async function ensureLandlordFromEnv() {
  const mobile = String(process.env.LANDLORD_MOBILE || '').replace(/[\s-]/g, '');
  const password = String(process.env.LANDLORD_PASSWORD || '');
  const name = String(process.env.LANDLORD_NAME || process.env.ADMIN_NAME || 'Landlord').trim().slice(0, 80);

  if (mobile && password) {
    if (!/^[0-9]{10}$/.test(mobile)) {
      console.log('Skipping landlord seed: LANDLORD_MOBILE must be 10 digits.');
      return null;
    }
    const existing = await Landlord.findOne({ mobile });
    if (existing) return existing;
    const landlord = await Landlord.create({
      name: name || `Landlord ${mobile.slice(-4)}`,
      mobile,
      passwordHash: await bcrypt.hash(password, 12),
    });
    console.log(`Created landlord "${mobile}" from LANDLORD_MOBILE/LANDLORD_PASSWORD env vars.`);
    return landlord;
  }

  // Legacy path: seed from ADMIN_* so a fresh deployment still boots.
  // The landlord mobile comes from ADMIN_CONTACT when it is a 10-digit number,
  // otherwise the operator must register via POST /api/auth/register.
  const legacyPassword = String(process.env.ADMIN_PASSWORD || '');
  const legacyContact = String(process.env.ADMIN_CONTACT || '').replace(/[\s-]/g, '');
  if (/^[0-9]{10}$/.test(legacyContact) && legacyPassword) {
    const existing = await Landlord.findOne({ mobile: legacyContact });
    if (existing) return existing;
    const landlord = await Landlord.create({
      name: name || 'Landlord',
      mobile: legacyContact,
      passwordHash: await bcrypt.hash(legacyPassword, 12),
    });
    console.log(`Created landlord "${legacyContact}" from ADMIN_CONTACT/ADMIN_PASSWORD env vars.`);
    return landlord;
  }
  return null;
}

/** Legacy admin seeder kept so old username logins keep working. */
async function ensureAdminFromEnv() {
  const username = String(process.env.ADMIN_USERNAME || '').trim().toLowerCase();
  const password = String(process.env.ADMIN_PASSWORD || '');
  if (!username || !password) return null;

  const existing = await Admin.findOne({ username });
  if (existing) return existing;

  const admin = await Admin.create({
    name: process.env.ADMIN_NAME || 'Admin',
    username,
    passwordHash: await bcrypt.hash(password, 12),
    contact: (process.env.ADMIN_CONTACT || '').toLowerCase() || undefined,
    role: 'admin',
  });
  console.log(`Created admin "${username}" from ADMIN_USERNAME/ADMIN_PASSWORD env vars.`);
  return admin;
}

module.exports = { ensureAdminFromEnv, ensureLandlordFromEnv };
