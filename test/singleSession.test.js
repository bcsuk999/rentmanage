'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const jwt = require('jsonwebtoken');
const Landlord = require('../src/models/Landlord');
const Admin = require('../src/models/Admin');
const { requireAuth, signToken } = require('../src/middleware/auth');

// Same fallback the middleware signs with, so a test token is a real one.
const SECRET = process.env.JWT_SECRET || process.env.SESSION_SECRET || 'dev-only-insecure-secret';
const ACCOUNT_ID = '507f1f77bcf86cd799439011';

function fakeRes() {
  const res = { statusCode: 200, body: null };
  res.status = (code) => {
    res.statusCode = code;
    return res;
  };
  res.json = (payload) => {
    res.body = payload;
    return res;
  };
  return res;
}

/** Landlord lookup returns an account at the given session counter. */
function stubAccount(t, tokenVersion) {
  const doc = tokenVersion === undefined ? { _id: ACCOUNT_ID } : { _id: ACCOUNT_ID, tokenVersion };
  t.mock.method(Landlord, 'findById', () => ({ lean: async () => doc }));
  t.mock.method(Admin, 'findById', () => ({ lean: async () => null }));
}

async function run(token) {
  const req = { headers: { authorization: `Bearer ${token}` } };
  const res = fakeRes();
  let allowed = false;
  await requireAuth(req, res, () => {
    allowed = true;
  });
  return { allowed, res };
}

test('signToken stamps the account session counter into the token', () => {
  const token = signToken({ _id: ACCOUNT_ID, tokenVersion: 7 });
  assert.equal(jwt.decode(token).tv, 7);
  assert.equal(jwt.decode(signToken({ _id: ACCOUNT_ID })).tv, 0);
});

test('the token from the latest sign-in is accepted', async (t) => {
  stubAccount(t, 4);
  const { allowed, res } = await run(signToken({ _id: ACCOUNT_ID, tokenVersion: 4 }));
  assert.equal(allowed, true);
  assert.equal(res.statusCode, 200);
});

test('a token minted before the latest sign-in is refused', async (t) => {
  stubAccount(t, 5);
  const { allowed, res } = await run(signToken({ _id: ACCOUNT_ID, tokenVersion: 4 }));
  assert.equal(allowed, false);
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, 'Account logged in somewhere else. Please login again.');
});

test('tokens from before the counter existed survive until the next sign-in', async (t) => {
  stubAccount(t, 0);
  const legacy = jwt.sign({ id: ACCOUNT_ID, role: 'landlord' }, SECRET, { expiresIn: '8h' });
  assert.equal((await run(legacy)).allowed, true);
  assert.equal((await run(signToken({ _id: ACCOUNT_ID, tokenVersion: 0 }))).allowed, true);
});

test('an account written before the field existed matches an old token', async (t) => {
  stubAccount(t, undefined); // legacy document, no tokenVersion field at all
  const legacy = jwt.sign({ id: ACCOUNT_ID, role: 'landlord' }, SECRET, { expiresIn: '8h' });
  assert.equal((await run(legacy)).allowed, true);
});
