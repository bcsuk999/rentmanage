'use strict';

const mongoose = require('mongoose');

const ROOM_STATUSES = ['Occupied', 'Empty', 'Maintenance'];
const MAX_CAPACITY = 100;

const roomSchema = new mongoose.Schema(
  {
    // Owning landlord account. Every query is scoped to this so one landlord
    // can never see or touch another's data.
    ownerId: {
      type: mongoose.Schema.Types.ObjectId,
      required: true,
      index: true,
    },
    roomNumber: {
      type: String,
      required: [true, 'Room number is required'],
      trim: true,
      maxlength: 40,
    },
    // Lower-cased copy of roomNumber. Uniqueness and lookups run against this so
    // they are index-backed equality/prefix matches instead of case-insensitive
    // regex scans.
    roomNumberKey: { type: String, trim: true, lowercase: true },
    /** Maximum number of active members allowed in the room. */
    capacity: {
      type: Number,
      required: [true, 'Capacity is required'],
      min: [1, 'Capacity must be at least 1'],
      max: [MAX_CAPACITY, `Capacity cannot be more than ${MAX_CAPACITY}`],
      default: 2,
    },
    status: { type: String, enum: ROOM_STATUSES, default: 'Empty' },
    notes: { type: String, trim: true, maxlength: 1000 },
    createdAt: { type: Date, default: Date.now },
    updatedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

// Room numbers are unique per landlord (two landlords may both have "101").
roomSchema.index({ ownerId: 1, roomNumberKey: 1 }, { unique: true });
// Serves the room list: status filter + roomNumber sort, scoped per landlord.
roomSchema.index({ ownerId: 1, status: 1, roomNumberKey: 1 });

/** Keep roomNumberKey in sync with roomNumber on every write. */
roomSchema.pre('validate', function syncRoomNumberKey() {
  if (this.roomNumber !== undefined) {
    this.roomNumberKey = String(this.roomNumber).trim().toLowerCase();
  }
});

module.exports = mongoose.model('Room', roomSchema);
module.exports.ROOM_STATUSES = ROOM_STATUSES;
module.exports.MAX_CAPACITY = MAX_CAPACITY;
