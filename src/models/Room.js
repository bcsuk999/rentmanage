'use strict';

const mongoose = require('mongoose');

const ROOM_STATUSES = ['Occupied', 'Empty', 'Maintenance'];

const roomSchema = new mongoose.Schema(
  {
    roomNumber: {
      type: String,
      required: [true, 'Room number is required'],
      trim: true,
      maxlength: 40,
    },
    status: { type: String, enum: ROOM_STATUSES, default: 'Empty', index: true },
    notes: { type: String, trim: true, maxlength: 1000 },
    createdAt: { type: Date, default: Date.now },
    updatedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

roomSchema.index({ roomNumber: 1 }, { unique: true });

module.exports = mongoose.model('Room', roomSchema);
module.exports.ROOM_STATUSES = ROOM_STATUSES;
