'use strict';

/**
 * Seeds the landlord account from .env and (optionally) demo rooms/members/payments.
 * Usage: npm run seed            -> landlord (+ legacy admin) only
 *        npm run seed -- --demo  -> admin + sample rooms, members and payments
 */
require('dotenv').config();

const bcrypt = require('bcryptjs');
const connectDb = require('../src/config/db');
const Admin = require('../src/models/Admin');
const Landlord = require('../src/models/Landlord');
const Member = require('../src/models/Member');
const Payment = require('../src/models/Payment');
const Room = require('../src/models/Room');
const rentService = require('../src/services/rentService');
const { addDays, cycleAt, today } = require('../src/utils/dates');

const DEMO = process.argv.includes('--demo');
const RESET_PASSWORD = process.argv.includes('--reset-password');

async function seedLandlord() {
  const mobile = String(process.env.LANDLORD_MOBILE || '').replace(/[\s-]/g, '')
    || String(process.env.ADMIN_CONTACT || '').replace(/[\s-]/g, '');
  const password = process.env.LANDLORD_PASSWORD || process.env.ADMIN_PASSWORD || 'Landlord@123';
  if (!/^[0-9]{10}$/.test(mobile)) {
    console.log('Skipping landlord seed: set LANDLORD_MOBILE to a 10-digit number.');
    return null;
  }
  const existing = await Landlord.findOne({ mobile });
  if (existing) {
    if (!RESET_PASSWORD) {
      console.log(`Landlord "${mobile}" already exists; leaving it untouched.`);
      console.log('Run "npm run seed -- --reset-password" to set it to LANDLORD_PASSWORD.');
      return existing;
    }
    existing.passwordHash = await bcrypt.hash(password, 12);
    if (process.env.LANDLORD_NAME) existing.name = process.env.LANDLORD_NAME;
    await existing.save();
    console.log(`Reset password for landlord "${mobile}" to the LANDLORD_PASSWORD value.`);
    return existing;
  }
  const landlord = await Landlord.create({
    name: process.env.LANDLORD_NAME || process.env.ADMIN_NAME || 'Landlord',
    mobile,
    passwordHash: await bcrypt.hash(password, 12),
  });
  console.log(`Created landlord "${mobile}" with the seed password. Change it after first sign in.`);
  return landlord;
}

async function seedAdmin() {
  const username = (process.env.ADMIN_USERNAME || 'admin').toLowerCase();
  const password = process.env.ADMIN_PASSWORD || 'Admin@123';
  const existing = await Admin.findOne({ username });
  if (existing) {
    if (!RESET_PASSWORD) {
      console.log(`Admin "${username}" already exists; leaving it untouched.`);
      console.log('Run "npm run seed -- --reset-password" to set it to ADMIN_PASSWORD.');
      return existing;
    }
    existing.passwordHash = await bcrypt.hash(password, 12);
    if (process.env.ADMIN_NAME) existing.name = process.env.ADMIN_NAME;
    await existing.save();
    console.log(`Reset password for admin "${username}" to the ADMIN_PASSWORD value.`);
    return existing;
  }
  const admin = await Admin.create({
    name: process.env.ADMIN_NAME || 'Admin',
    username,
    passwordHash: await bcrypt.hash(password, 12),
    contact: (process.env.ADMIN_CONTACT || '').toLowerCase() || undefined,
    role: 'admin',
  });
  console.log(`Created admin "${username}" with password "${password}". Change it after first sign in.`);
  return admin;
}

/** Rooms created before capacities existed get one that fits their members. */
async function backfillCapacity() {
  const rooms = await Room.find({ $or: [{ capacity: { $exists: false } }, { capacity: null }] });
  for (const room of rooms) {
    const activeMembers = await Member.countDocuments({ ownerId: room.ownerId, roomId: room._id, status: 'active' });
    room.capacity = Math.max(1, activeMembers);
    await room.save();
  }
  if (rooms.length) {
    console.log(`Backfilled capacity for ${rooms.length} existing room(s).`);
  }
}

async function seedDemo(ownerId) {
  if (!ownerId) {
    console.log('Skipping demo seed: no landlord/admin account to own the demo data.');
    return;
  }
  const reference = today();
  const rooms = [
    { roomNumber: '101', status: 'Occupied', capacity: 4 },
    { roomNumber: '102', status: 'Occupied', capacity: 3 },
    { roomNumber: '103', status: 'Empty', capacity: 2 },
    { roomNumber: '104', status: 'Maintenance', capacity: 1, notes: 'Painting work in progress' },
  ];
  for (const room of rooms) {
    const exists = await Room.findOne({ ownerId, roomNumberKey: room.roomNumber.toLowerCase() });
    if (!exists) await Room.create({ ...room, ownerId });
    else if (!exists.capacity) await Room.updateOne({ _id: exists._id }, { $set: { capacity: room.capacity } });
  }

  const people = [
    { roomNumber: '101', name: 'Amit Sharma', mobile: '9810010001', monthlyRent: 8000, monthsAgo: 0, payments: [3000, 2000] },
    { roomNumber: '101', name: 'Priya Nair', mobile: '9810010002', monthlyRent: 8000, monthsAgo: 0, payments: [8000] },
    { roomNumber: '101', name: 'Rohit Verma', mobile: '9810010003', monthlyRent: 8000, monthsAgo: 0, payments: [] },
    { roomNumber: '101', name: 'Sneha Iyer', mobile: '9810010004', monthlyRent: 8000, monthsAgo: 0, payments: [4000] },
    { roomNumber: '102', name: 'Vikram Singh', mobile: '9810010005', monthlyRent: 9500, monthsAgo: 1, payments: [9500, 2000] },
    { roomNumber: '102', name: 'Anita Das', mobile: '9810010006', monthlyRent: 7500, monthsAgo: 0, payments: [] },
  ];

  for (const person of people) {
    const room = await Room.findOne({ ownerId, roomNumberKey: person.roomNumber.toLowerCase() });
    const exists = await Member.findOne({ ownerId, roomId: room._id, name: person.name });
    if (exists) continue;
    const start = addDays(cycleAt(reference, -person.monthsAgo).start, 0);
    const member = await Member.create({
      ownerId,
      roomId: room._id,
      name: person.name,
      mobile: person.mobile,
      aadhaarNumber: person.name === 'Amit Sharma' ? '123456789012' : undefined,
      monthlyRent: person.monthlyRent,
      rentStartDate: start,
      joiningDate: start,
      status: 'active',
    });
    await rentService.ensurePeriodsForMember(member.toObject(), reference);
    const current = await rentService.periodForDate(member.toObject(), reference, reference);
    let remaining = person.monthlyRent;
    person.payments.forEach((amount, index) => {
      const value = Math.min(amount, remaining);
      remaining -= value;
      if (value <= 0) return;
      const when = addDays(current.startDate, Math.min(2 + index * 7, 25));
      Payment.create({
        ownerId,
        rentPeriodId: current._id,
        memberId: member._id,
        roomId: room._id,
        amount: value,
        paymentDate: when > reference ? reference : when,
        paymentMethod: ['Cash', 'UPI', 'Bank Transfer'][index % 3],
        reference: index === 0 ? 'CASH-001' : undefined,
      }).catch(() => {});
    });
    await rentService.recalcPeriod(current._id, reference);
  }
  console.log('Demo rooms, members and payments created.');
}

(async () => {
  try {
    await connectDb();
    const landlord = await seedLandlord();
    const admin = await seedAdmin();
    await backfillCapacity();
    if (DEMO) await seedDemo((landlord || admin) && (landlord || admin)._id);
    process.exit(0);
  } catch (err) {
    console.error('Seed failed:', err);
    process.exit(1);
  }
})();
