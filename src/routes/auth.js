'use strict';

const express = require('express');
const bcrypt = require('bcryptjs');
const Admin = require('../models/Admin');
const { redirectIfAuthed, validatePassword } = require('../middleware/auth');
const { fieldErrors, wrap } = require('../utils/http');
const { ValidationError } = require('../utils/validate');
const { toDateInput } = require('../utils/dates');

const router = express.Router();

router.get('/login', redirectIfAuthed, (req, res) => {
  res.render('auth/login', { title: 'Sign in', form: { username: '' }, errors: [] });
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
      });
    }
    admin.lastLoginAt = new Date();
    await admin.save();
    // Regenerate to avoid session fixation, then persist before redirecting so
    // the first request after login always finds the session in the store.
    await new Promise((resolve, reject) => {
      req.session.regenerate((err) => (err ? reject(err) : resolve()));
    });
    req.session.adminId = admin._id.toString();
    req.flash('success', `Welcome back, ${admin.name}.`);
    await new Promise((resolve, reject) => {
      req.session.save((err) => (err ? reject(err) : resolve()));
    });
    return res.redirect('/rooms');
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
