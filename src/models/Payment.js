'use strict';

const mongoose = require('mongoose');

const PAYMENT_METHODS = ['Cash', 'UPI', 'Bank Transfer', 'Other'];

const paymentSchema = new mongoose.Schema(
  {
    rentPeriodId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'RentPeriod',
      required: true,
      index: true,
    },
    memberId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Member',
      required: true,
      index: true,
    },
    roomId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Room',
      required: true,
      index: true,
    },
    amount: { type: Number, required: [true, 'Amount is required'], min: [1, 'Amount must be greater than 0'] },
    paymentDate: { type: Date, required: true, default: Date.now, index: true },
    paymentMethod: { type: String, enum: PAYMENT_METHODS, required: true },
    reference: { type: String, trim: true, maxlength: 120 },
    notes: { type: String, trim: true, maxlength: 500 },
    createdAt: { type: Date, default: Date.now },
    updatedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

paymentSchema.index({ paymentDate: -1 });
paymentSchema.index({ memberId: 1, paymentDate: -1 });

module.exports = mongoose.model('Payment', paymentSchema);
module.exports.PAYMENT_METHODS = PAYMENT_METHODS;
