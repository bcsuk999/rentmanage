'use strict';

const express = require('express');
const bcrypt = require('bcryptjs');
const Landlord = require('../models/Landlord');
const Admin = require('../models/Admin');
const { publicAccount, requireAuth, signToken, validatePassword } = require('../middleware/auth');
const { sendApiError, wrap } = require('../utils/http');
const { ValidationError, requireMobile } = require('../utils/validate');

const router = express.Router();

/** Self-service registration can be switched off with ALLOW_REGISTRATION=false. */
function registrationOpen() {
  return String(process.env.ALLOW_REGISTRATION || 'true').toLowerCase() !== 'false';
}

/** Normalize a mobile number or throw a 422. */
function parseMobile(value) {
  try {
    return requireMobile(value, 'Mobile');
  } catch (err) {
    if (err instanceof ValidationError) {
      throw new ValidationError(
        err.errors.map((e) => ({ field: 'mobile', message: e.message.replace(/^Mobile\s*/i, '').trim() || e.message }))
      );
    }
    throw err;
  }
}

/**
 * Landlord sign-in with mobile + password.
 * Legacy Admin username logins still work during migration: when no landlord
 * matches, the username store is checked with the same password.
 */
router.post(
  '/login',
  wrap(async (req, res) => {
    try {
      const rawId = String(req.body.mobile ?? req.body.username ?? '').trim();
      const password = String(req.body.password || '');
      const looksMobile = /^[0-9\s-]{10,14}$/.test(rawId);
      const mobile = looksMobile ? rawId.replace(/[\s-]/g, '') : null;

      let account = null;
      let isLandlord = false;
      if (mobile && /^[0-9]{10}$/.test(mobile)) {
        account = await Landlord.findOne({ mobile });
        isLandlord = true;
      }
      if (!account && !looksMobile) {
        const username = rawId.toLowerCase();
        account = await Admin.findOne({ username });
        isLandlord = false;
      }
      const ok = account ? await bcrypt.compare(password, account.passwordHash) : false;
      if (!account || !ok) {
        return res.status(401).json({ error: 'Invalid mobile number or password' });
      }
      account.lastLoginAt = new Date();
      await account.save();
      void isLandlord;
      return res.json({ token: signToken(account), user: publicAccount(account) });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/**
 * Landlord sign-up with mobile + password.
 * Req: { mobile*, password*, confirmPassword?, name? }
 */
router.post(
  '/register',
  wrap(async (req, res) => {
    try {
      if (!registrationOpen()) {
        return res.status(403).json({ error: 'Registration is closed on this server.' });
      }
      const mobile = parseMobile(req.body.mobile);
      const name = String(req.body.name || '').trim().slice(0, 80) || `Landlord ${mobile.slice(-4)}`;
      const password = String(req.body.password || '');
      const confirm = req.body.confirmPassword === undefined ? password : String(req.body.confirmPassword || '');

      const errors = validatePassword(password).map((e) => ({ ...e, field: 'password' }));
      if (password !== confirm) {
        errors.push({ field: 'confirmPassword', message: 'Passwords do not match' });
      }
      if (await Landlord.exists({ mobile })) {
        errors.push({ field: 'mobile', message: 'This mobile number is already registered' });
      }
      if (errors.length) throw new ValidationError(errors);

      const account = await Landlord.create({
        name,
        mobile,
        passwordHash: await bcrypt.hash(password, 12),
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
      const account = req.user._isLegacyAdmin
        ? await Admin.findById(req.user._id)
        : await Landlord.findById(req.user._id);
      if (!account) {
        return res.status(401).json({ error: 'Account no longer exists. Sign in again.' });
      }
      const errors = [];
      if (!(await bcrypt.compare(current, account.passwordHash))) {
        errors.push({ field: 'currentPassword', message: 'Current password is incorrect' });
      }
      errors.push(...validatePassword(next).map((e) => ({ ...e, field: 'password' })));
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
