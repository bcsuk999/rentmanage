'use strict';

const express = require('express');
const bcrypt = require('bcryptjs');
const Admin = require('../models/Admin');
const { publicAccount, validatePassword } = require('../middleware/auth');
const { sendApiError, wrap } = require('../utils/http');
const { ValidationError, requireUsername } = require('../utils/validate');

const router = express.Router();

/** Account list (password hashes never leave the server). */
router.get(
  '/admins',
  wrap(async (req, res) => {
    try {
      const admins = await Admin.find().sort({ createdAt: 1 }).lean();
      return res.json({
        admins: admins.map((a) => ({ ...publicAccount(a), contact: a.contact || null })),
      });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** Promote an account to admin, or demote it back to read-only. */
router.post(
  '/admins/role',
  wrap(async (req, res) => {
    try {
      const nextRole = req.body.role === 'admin' ? 'admin' : 'user';
      if (!Admin.isValidObjectId(req.body.id)) {
        throw new ValidationError([{ field: 'id', message: 'Invalid account' }]);
      }
      const account = await Admin.findById(req.body.id);
      if (!account) throw new ValidationError([{ field: 'id', message: 'Account not found' }]);
      if (String(account._id) === String(req.user._id) && nextRole !== 'admin') {
        throw new ValidationError([
          { field: 'id', message: 'You cannot remove your own admin access' },
        ]);
      }
      const adminCount = await Admin.countDocuments({ role: 'admin' });
      if (account.role === 'admin' && nextRole !== 'admin' && adminCount <= 1) {
        throw new ValidationError([
          { field: 'id', message: 'At least one admin account must remain' },
        ]);
      }
      account.role = nextRole;
      await account.save();
      return res.json({
        account: publicAccount(account),
        message: `${account.username} is now ${nextRole === 'admin' ? 'an admin' : 'read-only'}.`,
      });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** Create an account by hand (self-registration only ever makes viewers). */
router.post(
  '/admins',
  wrap(async (req, res) => {
    try {
      const username = requireUsername(req.body.username);
      const name = String(req.body.name || '').trim().slice(0, 80) || username;
      const password = String(req.body.password || '');
      const errors = validatePassword(password);
      if (await Admin.exists({ username })) {
        errors.push({ field: 'username', message: 'That username is already taken' });
      }
      if (errors.length) throw new ValidationError(errors);
      const account = await Admin.create({
        name,
        username,
        passwordHash: await bcrypt.hash(password, 12),
        contact: String(req.body.contact || '').trim().toLowerCase() || undefined,
        role: req.body.role === 'admin' ? 'admin' : 'user',
      });
      return res.status(201).json({ account: publicAccount(account), message: `Account "${account.username}" created.` });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

module.exports = router;
