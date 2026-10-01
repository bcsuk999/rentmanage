'use strict';

const express = require('express');
const RentPeriod = require('../models/RentPeriod');
const Member = require('../models/Member');
const Room = require('../models/Room');
const Payment = require('../models/Payment');
const { recalcPeriod } = require('../services/rentService');
const { requireRole } = require('../middleware/auth');
const { sendApiError, wrap } = require('../utils/http');
const { PAYMENT_METHODS } = require('../models/Payment');

const router = express.Router();

/** One rental cycle with its individual payment transactions. */
router.get(
  '/:id',
  wrap(async (req, res) => {
    try {
      const period = await RentPeriod.findById(req.params.id).lean();
      if (!period) {
        return res.status(404).json({ error: 'Rent period not found.' });
      }
      const [member, room, payments] = await Promise.all([
        Member.findById(period.memberId).lean(),
        Room.findById(period.roomId).lean(),
        Payment.find({ rentPeriodId: period._id }).sort({ paymentDate: 1, createdAt: 1 }).lean(),
      ]);
      return res.json({ period, member, room, payments, methods: PAYMENT_METHODS });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** Close a cycle so no further payments can be attached to it. */
router.post(
  '/:id/close',
  requireRole('admin'),
  wrap(async (req, res) => {
    try {
      const period = await RentPeriod.findById(req.params.id);
      if (!period) return res.status(404).json({ error: 'Rent period not found.' });
      period.isClosed = true;
      period.closedAt = new Date();
      await period.save();
      await recalcPeriod(period._id);
      return res.json({ period, message: 'Rent period closed. No further payments can be recorded against it.' });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** Reopen a closed cycle. */
router.post(
  '/:id/reopen',
  requireRole('admin'),
  wrap(async (req, res) => {
    try {
      const period = await RentPeriod.findById(req.params.id);
      if (!period) return res.status(404).json({ error: 'Rent period not found.' });
      period.isClosed = false;
      period.closedAt = undefined;
      await period.save();
      return res.json({ period, message: 'Rent period reopened.' });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

module.exports = router;
