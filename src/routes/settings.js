'use strict';

const express = require('express');
const bcrypt = require('bcryptjs');
const Admin = require('../models/Admin');
const roomService = require('../services/roomService');
const { fieldErrors, firstErrorMessage, wrap } = require('../utils/http');
const { ValidationError, requireUsername } = require('../utils/validate');
const { validatePassword } = require('../middleware/auth');
const { formatDate, toDateInput, today } = require('../utils/dates');

const router = express.Router();

router.get(
  '/',
  wrap(async (req, res) => {
    const rooms = await roomService.listRoomsWithSummary({});
    res.render('settings/index', {
      title: 'Settings',
      rooms,
      today: toDateInput(today()),
    });
  })
);

router.get(
  '/admins',
  wrap(async (req, res) => {
    const admins = await Admin.find().sort({ createdAt: 1 }).lean();
    res.render('settings/admins', {
      title: 'Accounts',
      admins: admins.map((a) => ({ ...a, createdAtLabel: formatDate(a.createdAt), lastLogin: a.lastLoginAt ? formatDate(a.lastLoginAt) : 'Never' })),
    });
  })
);

/** Promote an account to admin, or demote it back to read-only. */
router.post(
  '/admins/role',
  wrap(async (req, res) => {
    const nextRole = req.body.role === 'admin' ? 'admin' : 'user';
    const back = '/settings/admins';
    try {
      if (!Admin.isValidObjectId(req.body.id)) {
        throw new ValidationError([{ field: 'id', message: 'Invalid account' }]);
      }
      const account = await Admin.findById(req.body.id);
      if (!account) throw new ValidationError([{ field: 'id', message: 'Account not found' }]);
      if (account._id.equals(req.session.adminId) && nextRole !== 'admin') {
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
      req.flash('success', `${account.username} is now ${nextRole === 'admin' ? 'an admin' : 'read-only'}.`);
    } catch (err) {
      req.flash('error', firstErrorMessage(err) || fieldErrors(err).message);
    }
    return res.redirect(back);
  })
);

/** Create an admin account by hand (self-registration only ever makes viewers). */
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
      req.flash('success', `Account "${account.username}" created.`);
    } catch (err) {
      req.flash('error', firstErrorMessage(err));
    }
    return res.redirect('/settings/admins');
  })
);

module.exports = router;
