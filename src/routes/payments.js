'use strict';

const express = require('express');
const paymentService = require('../services/paymentService');
const Room = require('../models/Room');
const Member = require('../models/Member');
const { PAYMENT_METHODS } = require('../models/Payment');
const { requireRole } = require('../middleware/auth');
const { sendApiError, wrap } = require('../utils/http');

const router = express.Router();

/** All payment transactions with filters. Query: ?roomId=&memberId=&method=&from=&to=&page= */
router.get(
  '/',
  wrap(async (req, res) => {
    try {
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
      return res.json({ ...result, rooms, members, methods: PAYMENT_METHODS });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** Record a payment against a rent period. */
router.post(
  '/',
  requireRole('admin'),
  wrap(async (req, res) => {
    try {
      const payment = await paymentService.addPayment({
        rentPeriodId: req.body.rentPeriodId,
        amount: req.body.amount,
        paymentDate: req.body.paymentDate,
        paymentMethod: req.body.paymentMethod,
        reference: req.body.reference,
        notes: req.body.notes,
      });
      return res.status(201).json({ payment, message: 'Payment recorded. Rent totals recalculated.' });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

module.exports = router;
