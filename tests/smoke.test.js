'use strict';

/**
 * End-to-end smoke test against an in-memory MongoDB.
 * Run with: npm test
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const bcrypt = require('bcryptjs');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

process.env.NODE_ENV = 'test';
process.env.SESSION_SECRET = 'test-secret-value';
process.env.SESSION_NAME = 'rentmanage.sid';

const ADMIN = { username: 'admin', password: 'Admin@123' };

let mongod;
let app;
let Admin;
let Member;
let Payment;
let RentPeriod;
let Room;

const agent = () => request.agent(app);

test.before(async () => {
  mongod = await MongoMemoryServer.create();
  process.env.MONGODB_URI = mongod.getUri();

  Admin = require('../src/models/Admin');
  Member = require('../src/models/Member');
  Payment = require('../src/models/Payment');
  RentPeriod = require('../src/models/RentPeriod');
  Room = require('../src/models/Room');

  await mongoose.connect(process.env.MONGODB_URI);
  await Admin.create({
    name: 'Test Admin',
    username: ADMIN.username,
    passwordHash: await bcrypt.hash(ADMIN.password, 4),
  });
  app = require('../server');
});

test.after(async () => {
  if (mongoose.connection.readyState === 1) await mongoose.disconnect();
  if (mongod) await mongod.stop();
});

async function signIn(credentials = ADMIN) {
  const client = agent();
  const res = await client
    .post('/login')
    .type('form')
    .send({ username: credentials.username, password: credentials.password });
  assert.equal(res.status, 302, `login failed: ${res.status}`);
  assert.equal(res.headers.location, '/rooms');
  return client;
}

/** Create a room with one member and return the ids needed for assertions. */
async function seedRoomAndMember(rentStartDate, monthlyRent = 8000) {
  const client = await signIn();
  const roomRes = await client.post('/rooms').type('form').send({ roomNumber: '101', status: 'Empty' });
  assert.equal(roomRes.status, 302);
  const roomId = roomRes.headers.location.split('/').pop();

  const memberRes = await client
    .post(`/rooms/${roomId}/members`)
    .type('form')
    .send({
      name: 'Amit Sharma',
      mobile: '9810010001',
      aadhaarNumber: '123456789012',
      monthlyRent,
      rentStartDate,
    });
  assert.equal(memberRes.status, 302);
  const member = await Member.findOne({ roomId });
  assert.ok(member, 'member was not created');
  return { client, roomId, member };
}

test('rooms require authentication', async () => {
  const res = await request(app).get('/rooms');
  assert.equal(res.status, 302);
  assert.equal(res.headers.location, '/login');
});

test('login rejects a wrong password and accepts the right one', async () => {
  const bad = await request(app).post('/login').type('form').send({ username: 'admin', password: 'wrong' });
  assert.equal(bad.status, 401);

  const client = await signIn();
  const rooms = await client.get('/rooms');
  assert.equal(rooms.status, 200);
  assert.match(rooms.text, /Rooms/);
});

test('room numbers must be unique', async () => {
  const client = await signIn();
  const first = await client.post('/rooms').type('form').send({ roomNumber: '201', status: 'Empty' });
  assert.equal(first.status, 302);
  const second = await client.post('/rooms').type('form').send({ roomNumber: '201', status: 'Empty' });
  assert.equal(second.status, 422);
  assert.equal(await Room.countDocuments({ roomNumber: '201' }), 1);
});

test('adding a member generates a date-range rent period, never a calendar month', async () => {
  const start = '2026-09-15';
  const { roomId, member } = await seedRoomAndMember(start);
  const periods = await RentPeriod.find({ memberId: member._id }).sort({ startDate: 1 }).lean();
  assert.ok(periods.length >= 1, 'no rent period generated');

  const first = periods[0];
  assert.equal(first.startDate.toISOString().slice(0, 10), '2026-09-15');
  assert.equal(first.endDate.toISOString().slice(0, 10), '2026-10-14');
  assert.equal(first.rentAmount, 8000);
  assert.equal(first.status, 'Pending');

  // Cycles must not overlap.
  for (let i = 1; i < periods.length; i += 1) {
    assert.ok(periods[i].startDate > periods[i - 1].endDate, 'rent periods overlap');
  }

  const room = await Room.findById(roomId).lean();
  assert.equal(room.status, 'Occupied');
});

test('monthly rent is validated server-side', async () => {
  const client = await signIn();
  const roomRes = await client.post('/rooms').type('form').send({ roomNumber: '301', status: 'Empty' });
  const roomId = roomRes.headers.location.split('/').pop();
  const res = await client.post(`/rooms/${roomId}/members`).type('form').send({
    name: 'Bad Input',
    mobile: '123',
    monthlyRent: 'abc',
    rentStartDate: '2026-09-15',
  });
  assert.equal(res.status, 422);
  assert.equal(await Member.countDocuments({ roomId }), 0);
});

test('payments move a period from Pending to Partial to Paid', async () => {
  const { client, member } = await seedRoomAndMember('2026-01-10', 8000);
  const now = new Date();
  const period = await RentPeriod.findOne({
    memberId: member._id,
    startDate: { $lte: now },
    endDate: { $gte: now },
  });
  assert.ok(period, 'current period missing');

  const pay = (amount, date) =>
    client.post('/payments').type('form').send({
      rentPeriodId: period._id,
      amount,
      paymentDate: date,
      paymentMethod: 'Cash',
    });

  let res = await pay(3000, period.startDate.toISOString().slice(0, 10));
  assert.equal(res.status, 302);
  let fresh = await RentPeriod.findById(period._id).lean();
  assert.equal(fresh.paidAmount, 3000);
  assert.equal(fresh.pendingAmount, 5000);
  assert.equal(fresh.status, 'Partial');

  res = await pay(5000, period.endDate.toISOString().slice(0, 10));
  assert.equal(res.status, 302);
  fresh = await RentPeriod.findById(period._id).lean();
  assert.equal(fresh.paidAmount, 8000);
  assert.equal(fresh.pendingAmount, 0);
  assert.equal(fresh.status, 'Paid');
  assert.equal(await Payment.countDocuments({ rentPeriodId: period._id }), 2);
});

test('overpayment and out-of-period payment dates are rejected', async () => {
  const { client, member } = await seedRoomAndMember('2026-02-05', 5000);
  const now = new Date();
  const period = await RentPeriod.findOne({
    memberId: member._id,
    startDate: { $lte: now },
    endDate: { $gte: now },
  });

  const tooMuch = await client.post('/payments').type('form').send({
    rentPeriodId: period._id,
    amount: 9999,
    paymentDate: period.startDate.toISOString().slice(0, 10),
    paymentMethod: 'UPI',
  });
  assert.equal(tooMuch.status, 302);
  assert.equal(await Payment.countDocuments({ rentPeriodId: period._id }), 0);

  const outside = await client.post('/payments').type('form').send({
    rentPeriodId: period._id,
    amount: 100,
    paymentDate: '2020-01-01',
    paymentMethod: 'UPI',
  });
  assert.equal(outside.status, 302);
  assert.equal(await Payment.countDocuments({ rentPeriodId: period._id }), 0);
});

test('vacating keeps history, hides the member from the room and blocks new payments', async () => {
  const { client, roomId, member } = await seedRoomAndMember('2026-03-01', 6000);
  const now = new Date();
  const period = await RentPeriod.findOne({
    memberId: member._id,
    startDate: { $lte: now },
    endDate: { $gte: now },
  });
  await client.post('/payments').type('form').send({
    rentPeriodId: period._id,
    amount: 1000,
    paymentDate: period.startDate.toISOString().slice(0, 10),
    paymentMethod: 'Cash',
  });

  const vacate = await client
    .post(`/members/${member._id}/vacate`)
    .type('form')
    .send({ vacatingDate: new Date().toISOString().slice(0, 10), notes: 'Moved out' });
  assert.equal(vacate.status, 302);

  const updated = await Member.findById(member._id).lean();
  assert.equal(updated.status, 'inactive');
  assert.ok(updated.vacatingDate, 'vacating date not stored');

  // Active member list on the room page no longer shows the member.
  const roomPage = await client.get(`/rooms/${roomId}`);
  assert.equal(roomPage.status, 200);
  assert.doesNotMatch(roomPage.text, /Vacate\s+Amit/);
  assert.match(roomPage.text, /Vacated members/);

  // History survives.
  const detail = await client.get(`/members/${member._id}`);
  assert.equal(detail.status, 200);
  assert.match(detail.text, /Rent period history/);
  assert.equal(await RentPeriod.countDocuments({ memberId: member._id }) > 0, true);
  assert.equal(await Payment.countDocuments({ memberId: member._id }), 1);
});

test('aadhaar is stored but always masked in the UI', async () => {
  const { client, member } = await seedRoomAndMember('2026-04-01', 4000);
  const stored = await Member.findById(member._id).lean();
  assert.equal(stored.aadhaarNumber, '123456789012');

  const detail = await client.get(`/members/${member._id}`);
  assert.match(detail.text, /XXXX XXXX 9012/);
  assert.doesNotMatch(detail.text, /123456789012/);

  const list = await client.get('/members?search=9810010001');
  assert.equal(list.status, 200);
  assert.doesNotMatch(list.text, /123456789012/);
});

test('rooms with members or history cannot be deleted', async () => {
  const { client, roomId } = await seedRoomAndMember('2026-05-01', 3000);
  const res = await client.post(`/rooms/${roomId}/delete`).type('form').send({});
  assert.equal(res.status, 302);
  assert.ok(await Room.findById(roomId).lean(), 'room should still exist');
});

test('room detail can switch rental period and room search filters work', async () => {
  const { client, roomId, member } = await seedRoomAndMember('2026-06-12', 7000);
  const periods = await RentPeriod.find({ memberId: member._id }).sort({ startDate: 1 }).lean();
  const target = periods[periods.length - 2] || periods[0];

  const page = await client.get(
    `/rooms/${roomId}?from=${target.startDate.toISOString().slice(0, 10)}&to=${target.endDate.toISOString().slice(0, 10)}`
  );
  assert.equal(page.status, 200);
  assert.match(page.text, /Amit Sharma/);

  const byName = await client.get('/rooms?search=Amit');
  assert.equal(byName.status, 200);
  assert.match(byName.text, /Amit Sharma|101/);

  const paid = await client.get('/rooms?paymentState=Pending');
  assert.equal(paid.status, 200);
});

test('payments page lists transactions with filters', async () => {
  const client = await signIn();
  const page = await client.get('/payments');
  assert.equal(page.status, 200);
  assert.match(page.text, /Payments/);

  const period = await RentPeriod.findOne({ paidAmount: { $gt: 0 } });
  const filtered = await client.get(`/payments?rentPeriodId=${period._id}`);
  assert.equal(filtered.status, 200);
  assert.match(filtered.text, /Bank Transfer|Cash|UPI/);
});

test('reports require and use an explicit date range', async () => {
  const client = await signIn();
  const res = await client.get('/reports?from=2026-01-01&to=2026-12-31');
  assert.equal(res.status, 200);
  assert.match(res.text, /Expected rent/);
  assert.match(res.text, /Room-wise summary/);
  assert.match(res.text, /Member-wise summary/);

  const reversed = await client.get('/reports?from=2026-12-31&to=2026-01-01');
  assert.equal(reversed.status, 500);
});

test('logout clears the session', async () => {
  const client = await signIn();
  const out = await client.post('/logout').type('form').send({});
  assert.equal(out.status, 302);
  const after = await client.get('/rooms');
  assert.equal(after.status, 302);
  assert.equal(after.headers.location, '/login');
});
