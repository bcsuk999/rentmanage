'use strict';

const jwt = require('jsonwebtoken');
const Landlord = require('../models/Landlord');
const Admin = require('../models/Admin');

const PASSWORD_RULES = [
  { test: (p) => p.length >= 8, message: 'Password must be at least 8 characters' },
  { test: (p) => /[a-z]/.test(p), message: 'Password must include a lowercase letter' },
  { test: (p) => /[A-Z]/.test(p), message: 'Password must include an uppercase letter' },
  { test: (p) => /[0-9]/.test(p), message: 'Password must include a number' },
];

const TOKEN_TTL = '8h';

function validatePassword(password) {
  const errors = PASSWORD_RULES.filter((rule) => !rule.test(String(password || ''))).map(
    (rule) => ({ field: 'password', message: rule.message })
  );
  return errors;
}

function jwtSecret() {
  return process.env.JWT_SECRET || process.env.SESSION_SECRET || 'dev-only-insecure-secret';
}

/** Short public shape of a landlord sent to API clients. No admin fields. */
function publicAccount(account) {
  if (!account) return null;
  if (account.mobile) {
    return {
      id: String(account._id || account.id),
      name: account.name,
      mobile: account.mobile,
      role: 'landlord',
    };
  }
  // Legacy Admin doc served during migration: present it as a landlord.
  return {
    id: String(account._id || account.id),
    name: account.name,
    mobile: account.contact && /^[0-9]{10}$/.test(account.contact) ? account.contact : undefined,
    username: account.username,
    role: 'landlord',
  };
}

function signToken(account) {
  return jwt.sign({ id: String(account._id), role: 'landlord' }, jwtSecret(), {
    expiresIn: TOKEN_TTL,
  });
}

/** Find a landlord by id, falling back to a legacy Admin doc (migration). */
async function findAccountById(id) {
  const landlord = await Landlord.findById(id).lean();
  if (landlord) return { ...landlord, _isLandlord: true };
  const admin = await Admin.findById(id).lean();
  if (admin) return { ...admin, _isLegacyAdmin: true };
  return null;
}

/**
 * Bearer-token guard. Loads the landlord fresh on every request.
 * Legacy Admin tokens issued before the mobile-login migration are still
 * honoured so existing installs are not locked out.
 * Responds 401 JSON when missing/invalid.
 */
async function requireAuth(req, res, next) {
  try {
    const header = String(req.headers.authorization || '');
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!token) {
      return res.status(401).json({ error: 'Sign in required.' });
    }
    const payload = jwt.verify(token, jwtSecret());
    const account = await findAccountById(payload.id);
    if (!account) {
      return res.status(401).json({ error: 'Account no longer exists. Sign in again.' });
    }
    req.user = account;
    req.isAdmin = true;
    req.isLandlord = true;
    return next();
  } catch {
    return res.status(401).json({ error: 'Session expired. Sign in again.' });
  }
}

/** True when the signed-in account holds one of the given roles. */
function hasRole(user, ...roles) {
  if (!user) return false;
  // Single-role system now: every signed-in landlord passes admin checks so
  // legacy `requireRole('admin')` call sites keep working during migration.
  if (roles.includes('admin') || roles.includes('landlord')) return true;
  return Boolean(user && roles.includes(user.role));
}

/** 403 JSON for signed-in accounts without the role. */
function requireRole(...roles) {
  return (req, res, next) => {
    if (hasRole(req.user, ...roles)) return next();
    return res.status(403).json({
      error: 'Your account does not have permission to do that.',
    });
  };
}

module.exports = {
  findAccountById,
  hasRole,
  publicAccount,
  requireAuth,
  requireRole,
  signToken,
  validatePassword,
};
