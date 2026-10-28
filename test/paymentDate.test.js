'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const mongoose = require('mongoose');
const Member = require('../src/models/Member');
const Payment = require('../src/models/Payment');
const RentPeriod = require('../src/models/RentPeriod');
const paymentService = require('../src/services/paymentService');
const { today } = require('../src/utils/dates');

test('payment date is set to the recording day, not the rent period end', async (t) => {
  const periodId = new mongoose.Types.ObjectId();
  const memberId = new mongoose.Types.ObjectId();
  const roomId = new mongoose.Types.ObjectId();
  const ownerId = new mongoose.Types.ObjectId();
  const startDate = new Date('2026-08-03T00:00:00.000Z');
  const endDate = new Date('2030-09-02T00:00:00.000Z');
  const period = { _id: periodId, memberId, isClosed: false, startDate };
  const freshPeriod = {
    _id: periodId,
    memberId,
    roomId,
    pendingAmount: 2888,
    startDate,
    endDate,
    status: 'Pending',
  };
  const storedPeriod = {
    ...freshPeriod,
    rentAmount: 2888,
    waivedAmount: 0,
    paidAmount: 0,
    save: async () => {},
  };
  let createdPayment;

  t.mock.method(RentPeriod, 'findOne', async () => period);
  t.mock.method(RentPeriod, 'findById', async () => storedPeriod);
  t.mock.method(Payment, 'aggregate', async () => []);
  t.mock.method(Member, 'findOne', async () => ({ _id: memberId }));
  t.mock.method(RentPeriod, 'find', () => ({
    sort: () => ({ lean: async () => [freshPeriod] }),
  }));
  t.mock.method(Payment, 'create', async (data) => {
    createdPayment = data;
    return data;
  });

  await paymentService.addPayment({
    rentPeriodId: String(periodId),
    amount: 2888,
    paymentDate: '2026-09-02',
    paymentMethod: 'Cash',
    ownerId: String(ownerId),
  });

  assert.equal(createdPayment.paymentDate.toISOString(), today().toISOString());
  assert.notEqual(createdPayment.paymentDate.toISOString(), endDate.toISOString());
});
