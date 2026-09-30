'use strict';

const { parseDateInput } = require('./dates');
const { parseAmount } = require('./format');

class ValidationError extends Error {
  constructor(errors) {
    super('Validation failed');
    this.name = 'ValidationError';
    this.status = 422;
    this.expose = true;
    this.errors = errors;
  }
}

function str(value) {
  return value === undefined || value === null ? '' : String(value).trim();
}

function isBlank(value) {
  return str(value) === '';
}

function oneOf(value, allowed, label) {
  const v = str(value);
  if (!allowed.includes(v)) {
    throw new ValidationError([{ field: label, message: `Invalid ${label.toLowerCase()}` }]);
  }
  return v;
}

function requireText(value, field, { max = 200 } = {}) {
  const v = str(value);
  if (!v) throw new ValidationError([{ field, message: `${field} is required` }]);
  if (v.length > max) {
    throw new ValidationError([{ field, message: `${field} must be ${max} characters or fewer` }]);
  }
  return v;
}

function optionalText(value, field, { max = 1000 } = {}) {
  const v = str(value);
  if (!v) return undefined;
  if (v.length > max) {
    throw new ValidationError([{ field, message: `${field} must be ${max} characters or fewer` }]);
  }
  return v;
}

function requireDate(value, field) {
  const d = parseDateInput(value);
  if (!d) throw new ValidationError([{ field, message: `${field} is a required valid date` }]);
  return d;
}

function optionalDate(value, field) {
  if (isBlank(value)) return undefined;
  const d = parseDateInput(value);
  if (!d) throw new ValidationError([{ field, message: `${field} must be a valid date` }]);
  return d;
}

function requireAmount(value, field, { min = 1 } = {}) {
  const amount = parseAmount(value);
  if (Number.isNaN(amount)) {
    throw new ValidationError([{ field, message: `${field} must be a valid amount` }]);
  }
  if (amount < min) {
    throw new ValidationError([{ field, message: `${field} must be at least ${min}` }]);
  }
  if (amount > 10000000) {
    throw new ValidationError([{ field, message: `${field} looks too large` }]);
  }
  return Math.round(amount * 100) / 100;
}

function requireMobile(value, field = 'Mobile') {
  const v = str(value).replace(/[\s-]/g, '');
  if (!/^[0-9]{10}$/.test(v)) {
    throw new ValidationError([{ field, message: `${field} number must be 10 digits` }]);
  }
  return v;
}

/** Aadhaar is optional. Stores 12 digits (spaces/dashes removed) when supplied. */
function optionalAadhaar(value, field = 'Aadhaar') {
  if (isBlank(value)) return undefined;
  const v = str(value).replace(/[\s-]/g, '');
  if (!/^[0-9]{12}$/.test(v)) {
    throw new ValidationError([{ field, message: 'Aadhaar number must be 12 digits' }]);
  }
  return v;
}

/** Whole number of people a room can hold (1..100). */
function requireCapacity(value, field = 'Capacity') {
  const raw = str(value);
  if (!raw) throw new ValidationError([{ field, message: `${field} is required` }]);
  if (!/^[0-9]+$/.test(raw)) {
    throw new ValidationError([{ field, message: `${field} must be a whole number` }]);
  }
  const capacity = Number(raw);
  if (capacity < 1) {
    throw new ValidationError([{ field, message: `${field} must be at least 1` }]);
  }
  if (capacity > 100) {
    throw new ValidationError([{ field, message: `${field} cannot be more than 100` }]);
  }
  return capacity;
}

/** Usernames are lowercase letters, digits, dot, dash and underscore. */
function requireUsername(value, field = 'Username') {
  const v = str(value).toLowerCase();
  if (!v) throw new ValidationError([{ field, message: `${field} is required` }]);
  if (v.length < 3) {
    throw new ValidationError([{ field, message: `${field} must be at least 3 characters` }]);
  }
  if (v.length > 40) {
    throw new ValidationError([{ field, message: `${field} must be 40 characters or fewer` }]);
  }
  if (!/^[a-z0-9._-]+$/.test(v)) {
    throw new ValidationError([
      { field, message: `${field} may only use letters, numbers, dot, dash and underscore` },
    ]);
  }
  return v;
}

function collect(validator) {
  const errors = [];
  const safe = (fn) => {
    try {
      return fn();
    } catch (err) {
      if (err instanceof ValidationError) errors.push(...err.errors);
      else throw err;
      return undefined;
    }
  };
  const value = validator(safe);
  if (errors.length) throw new ValidationError(errors);
  return value;
}

module.exports = {
  ValidationError,
  collect,
  isBlank,
  oneOf,
  optionalAadhaar,
  optionalDate,
  optionalText,
  requireAmount,
  requireCapacity,
  requireDate,
  requireMobile,
  requireText,
  requireUsername,
  str,
};
