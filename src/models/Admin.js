'use strict';

const mongoose = require('mongoose');

// Holds every account that can sign in. Admins manage rooms, members, payments
// and settings; users get a read-only view of the same data.
const ROLES = ['admin', 'user'];

const accountSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true, maxlength: 80 },
    username: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      lowercase: true,
      minlength: 3,
      maxlength: 40,
    },
    contact: { type: String, trim: true, lowercase: true, maxlength: 120 },
    passwordHash: { type: String, required: true },
    role: { type: String, enum: ROLES, default: 'user', index: true },
    lastLoginAt: { type: Date },
  },
  { timestamps: true }
);

// Role filter for the accounts list.
accountSchema.index({ role: 1, createdAt: 1 });

module.exports = mongoose.model('Admin', accountSchema);
module.exports.ROLES = ROLES;
