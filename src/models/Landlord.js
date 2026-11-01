'use strict';

const mongoose = require('mongoose');

// Every landlord signs in with mobile + password. Landlords own full access:
// rooms, members, payments, reports. There are no roles and no usernames.
const landlordSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true, maxlength: 80 },
    mobile: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      match: [/^[0-9]{10}$/, 'Mobile number must be 10 digits'],
    },
    passwordHash: { type: String, required: true },
    lastLoginAt: { type: Date },
    // Bumped on every sign-in. A token only validates while it carries the
    // current value, so a sign-in on a second device instantly expires the
    // tokens already in someone else's hands (single-device sessions).
    tokenVersion: { type: Number, default: 0 },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Landlord', landlordSchema);
