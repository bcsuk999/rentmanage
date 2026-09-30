'use strict';

const bcrypt = require('bcryptjs');
const Admin = require('../models/Admin');

/**
 * Creates the admin account described by ADMIN_* env vars when it does not exist yet.
 * Never touches an existing account, so changing env vars cannot silently reset a
 * password that was already changed from the UI.
 * Returns the admin document, or null when no env credentials are configured.
 */
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

module.exports = { ensureAdminFromEnv };
