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

function redirectIfAuthed(req, res, next) {
  if (req.session && req.session.adminId) return res.redirect('/rooms');
  return next();
}

module.exports = { attachUser, redirectIfAuthed, requireAuth, validatePassword };
