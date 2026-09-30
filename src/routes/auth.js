'use strict';

const express = require('express');
const bcrypt = require('bcryptjs');
const Admin = require('../models/Admin');
const { redirectIfAuthed, validatePassword } = require('../middleware/auth');
const { fieldErrors, firstErrorMessage, wrap } = require('../utils/http');
const { ValidationError, requireUsername } = require('../utils/validate');
const { toDateInput } = require('../utils/dates');

const router = express.Router();

/** Self-service registration can be switched off with ALLOW_REGISTRATION=false. */
function registrationOpen() {
  return String(process.env.ALLOW_REGISTRATION || 'true').toLowerCase() !== 'false';
}

/** Signs the account in and persists the new session before redirecting. */
async function signIn(req, res, account, message) {
  account.lastLoginAt = new Date();
  await account.save();
  // Regenerate to avoid session fixation, then persist before redirecting so
  // the first request after login always finds the session in the store.
  await new Promise((resolve, reject) => {
    req.session.regenerate((err) => (err ? reject(err) : resolve()));
  });
  req.session.adminId = account._id.toString();
  req.flash('success', message);
  await new Promise((resolve, reject) => {
    req.session.save((err) => (err ? reject(err) : resolve()));
  });
  return res.redirect('/rooms');
}

router.get('/login', redirectIfAuthed, (req, res) => {
  res.render('auth/login', {
    title: 'Sign in',
    form: { username: '' },
    errors: [],
    registrationOpen: registrationOpen(),
  });
});

router.post(
  '/login',
  wrap(async (req, res) => {
    const username = String(req.body.username || '').trim().toLowerCase();
    const password = String(req.body.password || '');
    const admin = await Admin.findOne({ username });
    const ok = admin ? await bcrypt.compare(password, admin.passwordHash) : false;
    if (!admin || !ok) {
      return res.status(401).render('auth/login', {
        title: 'Sign in',
        form: { username },
        errors: [{ message: 'Invalid username or password' }],
        registrationOpen: registrationOpen(),
      });
    }
    return signIn(req, res, admin, `Welcome back, ${admin.name}.`);
  })
);

router.get('/register', redirectIfAuthed, (req, res) => {
  if (!registrationOpen()) {
    return res.redirect('/login');
  }
  return res.render('auth/register', {
    title: 'Create account',
    form: { username: '', name: '' },
    errors: [],
  });
});

/**
 * Self-service sign-up. New accounts are always created with the read-only
 * "user" role; only an existing admin can grant admin access.
 */
router.post(
  '/register',
  wrap(async (req, res) => {
    if (!registrationOpen()) {
      req.flash('error', 'Registration is closed on this server.');
      return res.redirect('/login');
    }
    try {
      const username = requireUsername(req.body.username);
      const name = String(req.body.name || '').trim().slice(0, 80) || username;
      const password = String(req.body.password || '');
      const confirm = String(req.body.confirmPassword || '');

      const errors = validatePassword(password);
      if (password !== confirm) {
        errors.push({ field: 'confirmPassword', message: 'Passwords do not match' });
      }
      if (await Admin.exists({ username })) {
        errors.push({ field: 'username', message: 'That username is already taken' });
      }
      if (errors.length) throw new ValidationError(errors);

      const account = await Admin.create({
        name,
        username,
        passwordHash: await bcrypt.hash(password, 12),
        role: 'user',
      });
      return signIn(req, res, account, `Account created. Welcome, ${account.name}.`);
    } catch (err) {
      return res.status(err.status || 422).render('auth/register', {
        title: 'Create account',
        form: { username: req.body.username || '', name: req.body.name || '' },
        errors: fieldErrors(err),
        error: firstErrorMessage(err),
      });
    }
  })
);

router.post('/logout', (req, res) => {
  req.session.destroy(() => {
    res.clearCookie('rentmanage.sid');
    res.redirect('/login');
  });
});

router.get('/change-password', (req, res) => {
  res.render('auth/change-password', { title: 'Change password', form: {}, errors: [] });
});

router.post(
  '/change-password',
  wrap(async (req, res) => {
    const current = String(req.body.currentPassword || '');
    const next = String(req.body.newPassword || '');
    const confirm = String(req.body.confirmPassword || '');
    const admin = await Admin.findById(req.session.adminId);
    const errors = [];
    if (!admin) {
      res.redirect('/login');
      return;
    }
    if (!(await bcrypt.compare(current, admin.passwordHash))) {
      errors.push({ field: 'currentPassword', message: 'Current password is incorrect' });
    }
    errors.push(...validatePassword(next));
    if (next !== confirm) {
      errors.push({ field: 'confirmPassword', message: 'Passwords do not match' });
    }
    if (errors.length) {
      return res.status(422).render('auth/change-password', {
        title: 'Change password',
        form: { ...req.body, newPassword: '', confirmPassword: '' },
        errors: fieldErrors(new ValidationError(errors)),
      });
    }
    admin.passwordHash = await bcrypt.hash(next, 12);
    await admin.save();
    req.flash('success', 'Password updated.');
    return res.redirect('/rooms');
  })
);

router.get('/account', (req, res) => {
  const admin = req.session.admin;
  res.render('settings/account', {
    title: 'My account',
    admin: {
      ...admin,
      createdAt: toDateInput(admin.createdAt) || null,
    },
  });
});

module.exports = router;
