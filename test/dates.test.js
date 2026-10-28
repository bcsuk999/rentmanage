'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { parseDateInput, today } = require('../src/utils/dates');

test('today uses the India calendar date even when the UTC date is different', () => {
  assert.equal(today(new Date('2026-10-27T18:45:00.000Z')).toISOString(), '2026-10-28T00:00:00.000Z');
});

test('date-only input remains the same calendar date', () => {
  assert.equal(parseDateInput('2026-10-28').toISOString(), '2026-10-28T00:00:00.000Z');
});

test('timestamp input is reduced to its India calendar date', () => {
  assert.equal(
    parseDateInput('2026-10-27T20:00:00.000Z').toISOString(),
    '2026-10-28T00:00:00.000Z'
  );
});
