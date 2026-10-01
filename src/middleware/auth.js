'use strict';

const jwt = require('jsonwebtoken');
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

/** Short public shape of an account sent to API clients. */
function publicAccount(account) {
  if (!account) return null;
  return {
    id: String(account._id || account.id),
    name: account.name,
    username: account.username,
    role: account.role,
  };
}

function signToken(account) {
  return jwt.sign({ id: String(account._id), role: account.role }, jwtSecret(), {
    expiresIn: TOKEN_TTL,
  });
}

/**
 * Bearer-token guard. Loads the account fresh on every request so role changes
 * take effect without re-login. Responds 401 JSON when missing/invalid.
 */
async function requireAuth(req, res, next) {
  try {
    const header = String(req.headers.authorization || '');
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!token) {
      return res.status(401).json({ error: 'Sign in required.' });
    }
    const payload = jwt.verify(token, jwtSecret());
    const account = await Admin.findById(payload.id).lean();
    if (!account) {
      return res.status(401).json({ error: 'Account no longer exists. Sign in again.' });
    }
    req.user = account;
    req.isAdmin = account.role === 'admin';
    return next();
  } catch {
    return res.status(401).json({ error: 'Session expired. Sign in again.' });
  }
}

/** True when the signed-in account holds one of the given roles. */
function hasRole(user, ...roles) {
  return Boolean(user && roles.includes(user.role));
}

/** 403 JSON for signed-in accounts without the role. */
function requireRole(...roles) {
  return (req, res, next) => {
    if (hasRole(req.user, ...roles)) return next();
    return res.status(403).json({
      error: 'Your account does not have permission to do that. Ask an admin for access.',
    });
  };
}

module.exports = {
  hasRole,
  publicAccount,
  requireAuth,
  requireRole,
  signToken,
  validatePassword,
};
