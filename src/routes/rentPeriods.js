'use strict';

const express = require('express');
const RentPeriod = require('../models/RentPeriod');
const Member = require('../models/Member');
const Room = require('../models/Room');
const Payment = require('../models/Payment');
const { recalcPeriod } = require('../services/rentService');
const { firstErrorMessage, wrap } = require('../utils/http');
const { formatDateRange, toDateInput, today } = require('../utils/dates');
const { PAYMENT_METHODS } = require('../models/Payment');

const router = express.Router();

/** One rental cycle with its individual payment transactions. */
router.get(
  '/:id',
  wrap(async (req, res) => {
    const period = await RentPeriod.findById(req.params.id).lean();
    if (!period) {
      req.flash('error', 'Rent period not found.');
      return res.redirect('/rooms');
    }
    const [member, room, payments] = await Promise.all([
      Member.findById(period.memberId).lean(),
      Room.findById(period.roomId).lean(),
      Payment.find({ rentPeriodId: period._id }).sort({ paymentDate: 1, createdAt: 1 }).lean(),
    ]);
    return res.render('rentPeriods/detail', {
      title: 'Rent period',
      period,
      member,
      room,
      payments,
      rangeLabel: formatDateRange(period.startDate, period.endDate),
      methods: PAYMENT_METHODS,
      today: toDateInput(today()),
    });
  })
);

/** Close a cycle so no further payments can be attached to it. */
router.post(
  '/:id/close',
  wrap(async (req, res) => {
    try {
      const period = await RentPeriod.findById(req.params.id);
      if (!period) throw new Error('Rent period not found');
      period.isClosed = true;
      period.closedAt = new Date();
      await period.save();
      await recalcPeriod(period._id);
      req.flash('success', 'Rent period closed. No further payments can be recorded against it.');
    } catch (err) {
      req.flash('error', firstErrorMessage(err));
    }
    return res.redirect(req.get('referrer') || `/rent-periods/${req.params.id}`);
  })
);

/** Reopen a closed cycle. */
router.post(
  '/:id/reopen',
  wrap(async (req, res) => {
    try {
      const period = await RentPeriod.findById(req.params.id);
      if (!period) throw new Error('Rent period not found');
      period.isClosed = false;
      period.closedAt = undefined;
      await period.save();
      req.flash('success', 'Rent period reopened.');
    } catch (err) {
      req.flash('error', firstErrorMessage(err));
    }
    return res.redirect(`/rent-periods/${req.params.id}`);
  })
);

module.exports = router;
