'use strict';

const mongoose = require('mongoose');
const { ValidationError } = require('./validate');

/**
 * Normalise the signed-in account id into an owner ObjectId.
 * Every data query is scoped with this so one landlord can never read or
 * write another landlord's records.
 */
function requireOwnerId(value) {
  const text = String(value || '').trim();
  if (!mongoose.isValidObjectId(text)) {
    throw new ValidationError([{ field: 'owner', message: 'Invalid account' }]);
  }
  return new mongoose.Types.ObjectId(text);
}

module.exports = { requireOwnerId };
