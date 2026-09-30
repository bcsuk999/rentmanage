'use strict';

const mongoose = require('mongoose');

const RENT_STATUSES = ['Pending', 'Partial', 'Paid', 'Overdue'];

const rentPeriodSchema = new mongoose.Schema(
  {
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
    startDate: { type: Date, required: true },
    endDate: { type: Date, required: true },
    rentAmount: { type: Number, required: true, min: 0 },
    paidAmount: { type: Number, default: 0, min: 0 },
    pendingAmount: { type: Number, default: 0, min: 0 },
    status: { type: String, enum: RENT_STATUSES, default: 'Pending', index: true },
    isClosed: { type: Boolean, default: false },
    closedAt: { type: Date },
    createdAt: { type: Date, default: Date.now },
    updatedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

// One rent period per member per cycle start; periods for a member must not overlap.
rentPeriodSchema.index({ memberId: 1, startDate: 1 }, { unique: true });
rentPeriodSchema.index({ roomId: 1, startDate: 1, endDate: 1 });
rentPeriodSchema.index({ endDate: 1 });

module.exports = mongoose.model('RentPeriod', rentPeriodSchema);
module.exports.RENT_STATUSES = RENT_STATUSES;
