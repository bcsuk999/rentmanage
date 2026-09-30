'use strict';

const inr = new Intl.NumberFormat('en-IN', {
  style: 'currency',
  currency: 'INR',
  maximumFractionDigits: 0,
});

const inrWithPaise = new Intl.NumberFormat('en-IN', {
  style: 'currency',
  currency: 'INR',
  minimumFractionDigits: 2,
});

/** Format a rupee amount stored as a Number (rupees, 2dp safe). */
function currency(amount) {
  const value = Number(amount) || 0;
  return Number.isInteger(value) ? inr.format(value) : inrWithPaise.format(value);
}

/** Parse a user-entered rupee amount ("8,000.50") into a Number. Returns NaN when invalid. */
function parseAmount(input) {
  if (input === undefined || input === null) return NaN;
  const cleaned = String(input).replace(/[,\s\u20b9]/g, '');
  if (!/^\d+(\.\d{1,2})?$/.test(cleaned)) return NaN;
  return Number(cleaned);
}

module.exports = { currency, parseAmount };
