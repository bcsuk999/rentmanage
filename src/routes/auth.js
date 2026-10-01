'use strict';

const express = require('express');
const bcrypt = require('bcryptjs');
const Admin = require('../models/Admin');
const { publicAccount, requireAuth, signToken, validatePassword } = require('../middleware/auth');
const { sendApiError, wrap } = require('../utils/http');
const { ValidationError, requireUsername } = require('../utils/validate');

const router = express.Router();

/** Self-service registration can be switched off with ALLOW_REGISTRATION=false. */
function registrationOpen() {
  return String(process.env.ALLOW_REGISTRATION || 'true').toLowerCase() !== 'false';
}

router.post(
  '/login',
  wrap(async (req, res) => {
    try {
      const username = String(req.body.username || '').trim().toLowerCase();
      const password = String(req.body.password || '');
      const account = await Admin.findOne({ username });
      const ok = account ? await bcrypt.compare(password, account.passwordHash) : false;
      if (!account || !ok) {
        return res.status(401).json({ error: 'Invalid username or password' });
      }
      account.lastLoginAt = new Date();
      await account.save();
      return res.json({ token: signToken(account), user: publicAccount(account) });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/**
 * Self-service sign-up. New accounts are always created with the read-only
 * "user" role; only an existing admin can grant admin access.
 */
router.post(
  '/register',
  wrap(async (req, res) => {
    try {
      if (!registrationOpen()) {
        return res.status(403).json({ error: 'Registration is closed on this server.' });
      }
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
      account.lastLoginAt = new Date();
      await account.save();
      return res.status(201).json({ token: signToken(account), user: publicAccount(account) });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** Stateless tokens: logout is the client discarding its token. */
router.post('/logout', (req, res) => {
  res.json({ ok: true });
});

router.get('/me', requireAuth, (req, res) => {
  res.json({ user: publicAccount(req.user) });
});

router.post(
  '/change-password',
  requireAuth,
  wrap(async (req, res) => {
    try {
      const current = String(req.body.currentPassword || '');
      const next = String(req.body.newPassword || '');
      const confirm = String(req.body.confirmPassword || '');
      const account = await Admin.findById(req.user._id);
      if (!account) {
        return res.status(401).json({ error: 'Account no longer exists. Sign in again.' });
      }
      const errors = [];
      if (!(await bcrypt.compare(current, account.passwordHash))) {
        errors.push({ field: 'currentPassword', message: 'Current password is incorrect' });
      }
      errors.push(...validatePassword(next));
      if (next !== confirm) {
        errors.push({ field: 'confirmPassword', message: 'Passwords do not match' });
      }
      if (errors.length) throw new ValidationError(errors);
      account.passwordHash = await bcrypt.hash(next, 12);
      await account.save();
      return res.json({ ok: true, message: 'Password updated.' });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

module.exports = router;
