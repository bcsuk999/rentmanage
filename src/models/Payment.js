'use strict';

const mongoose = require('mongoose');

const PAYMENT_METHODS = ['Cash', 'UPI', 'Bank Transfer', 'Other'];

const paymentSchema = new mongoose.Schema(
  {
    // Owning landlord account (copied from the period/member). Scopes every query.
    ownerId: {
      type: mongoose.Schema.Types.ObjectId,
      required: true,
      index: true,
    },
    rentPeriodId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'RentPeriod',
      required: true,
    },
    memberId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Member',
      required: true,
    },
    roomId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Room',
      required: true,
    },
    amount: { type: Number, required: [true, 'Amount is required'], min: [1, 'Amount must be greater than 0'] },
    paymentDate: { type: Date, required: true, default: Date.now },
    paymentMethod: { type: String, enum: PAYMENT_METHODS, required: true },
    // How this payment was split: oldest dues first, then the current cycle.
    // Absent on payments recorded before the split was tracked.
    allocOverdue: { type: Number, default: null, min: 0 },
    allocCurrent: { type: Number, default: null, min: 0 },
    // Per-cycle credit ledger. A spanning payment (e.g. ₹2000 = ₹500 overdue +
    // ₹1500 current) still lands as one record, but each cycle it clears is
    // listed here so recalcPeriod() credits the exact cycle the money went to.
    // Empty on payments recorded before the ledger existed.
    allocations: {
      type: [
        new mongoose.Schema(
          {
            rentPeriodId: { type: mongoose.Schema.Types.ObjectId, ref: 'RentPeriod', required: true },
            amount: { type: Number, required: true, min: 0 },
            overdue: { type: Boolean, default: false },
            periodStart: { type: Date },
            periodEnd: { type: Date },
          },
          { _id: false }
        ),
      ],
      default: [],
    },
    reference: { type: String, trim: true, maxlength: 120 },
    notes: { type: String, trim: true, maxlength: 500 },
  },
  // createdAt/updatedAt come from `timestamps` below. Declaring them by hand as
  // well fought the plugin, so they are left to it.
  { timestamps: true }
);

// Per-period totals (recalcPeriod), member history, room/date filtered lists and
// cash-in-range reports.
paymentSchema.index({ ownerId: 1, paymentDate: -1 });
paymentSchema.index({ rentPeriodId: 1, paymentDate: 1 });
paymentSchema.index({ ownerId: 1, memberId: 1, paymentDate: -1 });
paymentSchema.index({ ownerId: 1, roomId: 1, paymentDate: -1 });
paymentSchema.index({ ownerId: 1, paymentMethod: 1, paymentDate: -1 });

module.exports = mongoose.model('Payment', paymentSchema);
module.exports.PAYMENT_METHODS = PAYMENT_METHODS;
