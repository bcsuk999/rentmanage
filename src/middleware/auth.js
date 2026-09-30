'use strict';

const Admin = require('../models/Admin');

const PASSWORD_RULES = [
  { test: (p) => p.length >= 8, message: 'Password must be at least 8 characters' },
  { test: (p) => /[a-z]/.test(p), message: 'Password must include a lowercase letter' },
  { test: (p) => /[A-Z]/.test(p), message: 'Password must include an uppercase letter' },
  { test: (p) => /[0-9]/.test(p), message: 'Password must include a number' },
];

function validatePassword(password) {
  const errors = PASSWORD_RULES.filter((rule) => !rule.test(String(password || ''))).map(
    (rule) => ({ field: 'password', message: rule.message })
  );
  return errors;
}

async function attachUser(req, res, next) {
  if (req.session.adminId) {
    req.session.admin = await Admin.findById(req.session.adminId).lean().catch(() => null);
    if (!req.session.admin) delete req.session.adminId;
  }
  return next();
}

function requireAuth(req, res, next) {
  if (req.session && req.session.adminId) return next();
  req.session.flash = { type: 'error', message: 'Please sign in to continue.' };
  return res.redirect('/login');
}

/** True when the signed-in account holds one of the given roles. */
function hasRole(user, ...roles) {
  return Boolean(user && roles.includes(user.role));
}

/**
 * Route guard for privileged actions. Signed-in accounts without the role get a
 * 403 instead of a redirect, so the UI and the server agree on who may do what.
 */
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.session || !req.session.adminId) {
      req.session.flash = { type: 'error', message: 'Please sign in to continue.' };
      return res.redirect('/login');
    }
    if (hasRole(req.session.admin, ...roles)) return next();
    return res.status(403).render('error', {
      title: 'Not allowed',
      message: 'Your account does not have permission to do that. Ask an admin for access.',
    });
  };
}

function redirectIfAuthed(req, res, next) {
  if (req.session && req.session.adminId) return res.redirect('/rooms');
  return next();
}

module.exports = {
  attachUser,
  hasRole,
  redirectIfAuthed,
  requireAuth,
  requireRole,
  validatePassword,
};
