'use strict';

const Payment = require('../models/Payment');
const RentPeriod = require('../models/RentPeriod');
const Member = require('../models/Member');
const { recalcPeriod } = require('./rentService');
const { contains, parseDateInput, startOfDay } = require('../utils/dates');
const { ValidationError } = require('../utils/validate');
const { PAYMENT_METHODS } = require('../models/Payment');

/**
 * Record a payment against a rent period.
 * Server-side guards: period must exist, must not be closed, the payment date
 * must fall inside the period, and the amount cannot exceed the pending amount.
 */
async function addPayment({
  rentPeriodId,
  amount,
  paymentDate,
  paymentMethod,
  reference,
  notes,
}) {
  const period = await RentPeriod.findById(rentPeriodId);
  if (!period) {
    throw new ValidationError([{ field: 'rentPeriod', message: 'Rent period not found' }]);
  }
  if (period.isClosed) {
    throw new ValidationError([
      { field: 'rentPeriod', message: 'This rent period is closed and cannot accept payments' },
    ]);
  }
  const member = await Member.findById(period.memberId);
  if (!member) {
    throw new ValidationError([{ field: 'rentPeriod', message: 'Member not found for this period' }]);
  }
  const on = parseDateInput(paymentDate) || startOfDay(new Date());
  if (!contains(period.startDate, period.endDate, on)) {
    throw new ValidationError([
      {
        field: 'paymentDate',
        message: 'Payment date must fall inside the selected rent period',
      },
    ]);
  }
  const amountValue = Number(amount);
  if (!Number.isFinite(amountValue) || amountValue <= 0) {
    throw new ValidationError([{ field: 'amount', message: 'Amount must be greater than 0' }]);
  }
  if (amountValue > 10000000) {
    throw new ValidationError([{ field: 'amount', message: 'Amount looks too large' }]);
  }
  if (!PAYMENT_METHODS.includes(paymentMethod)) {
    throw new ValidationError([{ field: 'paymentMethod', message: 'Invalid payment method' }]);
  }

  // Recalculate first so the pending amount used for validation is fresh.
  const fresh = await recalcPeriod(period._id);
  if (amountValue > fresh.pendingAmount) {
    throw new ValidationError([
      {
        field: 'amount',
        message: `Amount exceeds the pending amount (${fresh.pendingAmount}) for this period`,
      },
    ]);
  }

  const payment = await Payment.create({
    rentPeriodId: fresh._id,
    memberId: fresh.memberId,
    roomId: fresh.roomId,
    amount: Math.round(amountValue * 100) / 100,
    paymentDate: on,
    paymentMethod,
    reference: reference ? String(reference).trim() : undefined,
    notes: notes ? String(notes).trim() : undefined,
  });
  await recalcPeriod(fresh._id);
  return payment;
}

async function paymentsForPeriod(rentPeriodId) {
  return Payment.find({ rentPeriodId })
    .sort({ paymentDate: 1, createdAt: 1 })
    .populate('memberId', 'name mobile')
    .populate('roomId', 'roomNumber')
    .lean();
}

async function paymentsForMember(memberId) {
  return Payment.find({ memberId })
    .sort({ paymentDate: -1, createdAt: -1 })
    .populate('rentPeriodId', 'startDate endDate rentAmount status')
    .populate('roomId', 'roomNumber')
    .lean();
}

/** Payments page: filterable, newest first, with optional pagination. */
async function listPayments(filters = {}) {
  const { roomId, memberId, paymentMethod, from, to, rentPeriodId } = filters;
  const query = {};
  if (roomId) query.roomId = roomId;
  if (memberId) query.memberId = memberId;
  if (rentPeriodId) query.rentPeriodId = rentPeriodId;
  if (paymentMethod && PAYMENT_METHODS.includes(paymentMethod)) {
    query.paymentMethod = paymentMethod;
  }
  if (from || to) {
    query.paymentDate = {};
    if (from) query.paymentDate.$gte = startOfDay(parseDateInput(from));
    if (to) query.paymentDate.$lte = startOfDay(parseDateInput(to));
  }
  const page = Math.max(1, Number(filters.page) || 1);
  const limit = Math.min(200, Math.max(10, Number(filters.limit) || 50));
  const [rows, total, sumRows] = await Promise.all([
    Payment.find(query)
      .sort({ paymentDate: -1, createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .populate('memberId', 'name mobile status')
      .populate('roomId', 'roomNumber')
      .populate('rentPeriodId', 'startDate endDate status')
      .lean(),
    Payment.countDocuments(query),
    Payment.aggregate([{ $match: query }, { $group: { _id: null, total: { $sum: '$amount' } } }]),
  ]);
  return {
    rows,
    total,
    page,
    limit,
    pages: Math.max(1, Math.ceil(total / limit)),
    totalAmount: sumRows.length ? Math.round(sumRows[0].total * 100) / 100 : 0,
  };
}

/** Cash received per day inside a range (used by reports). */
async function totalsForRange(from, to) {
  const match = { paymentDate: { $gte: from, $lte: to } };
  const [result] = await Payment.aggregate([
    { $match: match },
    { $group: { _id: null, total: { $sum: '$amount' }, count: { $sum: 1 } } },
  ]);
  return { total: result ? result.total : 0, count: result ? result.count : 0 };
}

module.exports = {
  addPayment,
  listPayments,
  paymentsForMember,
  paymentsForPeriod,
  totalsForRange,
};
