'use strict';

const mongoose = require('mongoose');

const MEMBER_STATUSES = ['active', 'inactive'];

const memberSchema = new mongoose.Schema(
  {
    roomId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Room',
      required: true,
      index: true,
    },
    name: { type: String, required: [true, 'Name is required'], trim: true, maxlength: 120 },
    mobile: {
      type: String,
      required: [true, 'Mobile number is required'],
      trim: true,
      match: [/^[0-9]{10}$/, 'Mobile number must be 10 digits'],
    },
    aadhaarNumber: { type: String, trim: true, maxlength: 14 },
    address: { type: String, trim: true, maxlength: 500 },
    emergencyContact: { type: String, trim: true, maxlength: 120 },
    monthlyRent: {
      type: Number,
      required: [true, 'Monthly rent is required'],
      min: [1, 'Monthly rent must be greater than 0'],
    },
    rentStartDate: {
      type: Date,
      required: [true, 'Rent start date is required'],
    },
    joiningDate: { type: Date, required: true, default: Date.now },
    vacatingDate: { type: Date },
    status: { type: String, enum: MEMBER_STATUSES, default: 'active', index: true },
    notes: { type: String, trim: true, maxlength: 1000 },
    createdAt: { type: Date, default: Date.now },
    updatedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

memberSchema.index({ roomId: 1, status: 1 });
memberSchema.index({ mobile: 1 });
memberSchema.index({ aadhaarNumber: 1 });
memberSchema.index({ name: 'text' });

module.exports = mongoose.model('Member', memberSchema);
module.exports.MEMBER_STATUSES = MEMBER_STATUSES;
