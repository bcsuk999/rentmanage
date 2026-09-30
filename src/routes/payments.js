'use strict';

const express = require('express');
const paymentService = require('../services/paymentService');
const Room = require('../models/Room');
const Member = require('../models/Member');
const { PAYMENT_METHODS } = require('../models/Payment');
const { firstErrorMessage, wrap } = require('../utils/http');
const { formatDateRange } = require('../utils/dates');

const router = express.Router();

/** All payment transactions with filters. */
router.get(
  '/',
  wrap(async (req, res) => {
    const filters = {
      roomId: String(req.query.roomId || '').trim(),
      memberId: String(req.query.memberId || '').trim(),
      paymentMethod: String(req.query.paymentMethod || '').trim(),
      rentPeriodId: String(req.query.rentPeriodId || '').trim(),
      from: String(req.query.from || '').trim(),
      to: String(req.query.to || '').trim(),
      page: req.query.page,
    };
    const result = await paymentService.listPayments(filters);
    const [rooms, members] = await Promise.all([
      Room.find().select('roomNumber').sort({ roomNumber: 1 }).lean(),
      Member.find().select('name mobile').sort({ name: 1 }).limit(300).lean(),
    ]);
    res.render('payments/index', {
      title: 'Payments',
      ...result,
      rooms,
      members,
      methods: PAYMENT_METHODS,
      filters,
      formatRange: formatDateRange,
    });
  })
);

/** Record a payment against a rent period. */
router.post(
  '/',
  wrap(async (req, res) => {
    const back = req.body.returnTo || (req.body.rentPeriodId ? `/rent-periods/${req.body.rentPeriodId}` : '/payments');
    try {
      const payment = await paymentService.addPayment({
        rentPeriodId: req.body.rentPeriodId,
        amount: req.body.amount,
        paymentDate: req.body.paymentDate,
        paymentMethod: req.body.paymentMethod,
        reference: req.body.reference,
        notes: req.body.notes,
      });
      req.flash('success', 'Payment recorded. Rent totals recalculated.');
      return res.redirect(back || `/rent-periods/${payment.rentPeriodId}`);
    } catch (err) {
      req.flash('error', firstErrorMessage(err));
      return res.redirect(back);
    }
  })
);

module.exports = router;
