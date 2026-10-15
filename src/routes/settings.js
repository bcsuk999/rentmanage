'use strict';

const express = require('express');
const Landlord = require('../models/Landlord');
const { publicAccount } = require('../middleware/auth');
const { sendApiError, wrap } = require('../utils/http');
const { ValidationError, requireMobile } = require('../utils/validate');

const router = express.Router();

/** Signed-in landlord profile. */
router.get(
  '/profile',
  wrap(async (req, res) => {
    try {
      if (req.user._isLegacyAdmin) {
        return res.json({ user: publicAccount(req.user) });
      }
      const account = await Landlord.findById(req.user._id).lean();
      if (!account) return res.status(401).json({ error: 'Account no longer exists. Sign in again.' });
      return res.json({ user: publicAccount(account) });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** Update the signed-in landlord's name / mobile. */
router.patch(
  '/profile',
  wrap(async (req, res) => {
    try {
      if (req.user._isLegacyAdmin) {
        throw new ValidationError([
          { field: 'mobile', message: 'Legacy username accounts cannot change profile. Register with a mobile number.' },
        ]);
      }
      const account = await Landlord.findById(req.user._id);
      if (!account) return res.status(401).json({ error: 'Account no longer exists. Sign in again.' });
      if (req.body.mobile !== undefined) {
        const mobile = requireMobile(req.body.mobile, 'Mobile');
        const taken = await Landlord.findOne({ mobile, _id: { $ne: account._id } }).lean();
        if (taken) {
          throw new ValidationError([{ field: 'mobile', message: 'This mobile number is already registered' }]);
        }
        account.mobile = mobile;
      }
      if (req.body.name !== undefined) {
        const name = String(req.body.name || '').trim().slice(0, 80);
        if (!name) throw new ValidationError([{ field: 'name', message: 'Name is required' }]);
        account.name = name;
      }
      await account.save();
      return res.json({ user: publicAccount(account), message: 'Profile updated.' });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

module.exports = router;
