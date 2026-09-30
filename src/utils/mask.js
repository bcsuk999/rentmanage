'use strict';

const AADHAAR_MASK = 'XXXX XXXX 1234';

/** Mask an Aadhaar number for normal UI display: 12 digits -> "XXXX XXXX 1234". */
function maskAadhaar(value) {
  if (!value) return null;
  const digits = String(value).replace(/\D/g, '');
  if (digits.length !== 12) return AADHAAR_MASK;
  return `XXXX XXXX ${digits.slice(-4)}`;
}

module.exports = { maskAadhaar, AADHAAR_MASK };
