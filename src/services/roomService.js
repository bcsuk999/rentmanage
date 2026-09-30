'use strict';

const mongoose = require('mongoose');
const Room = require('../models/Room');
const Member = require('../models/Member');
const RentPeriod = require('../models/RentPeriod');
const { ROOM_STATUSES } = require('../models/Room');
const { ensurePeriodsForActiveMembers, summarise } = require('./rentService');
const { startOfDay, today } = require('../utils/dates');
const { ValidationError, collect, oneOf, optionalText, requireText } = require('../utils/validate');

const PAYMENT_FILTERS = ['Fully Paid', 'Partial', 'Pending', 'Overdue'];

/** Room numbers are matched case-insensitively (101 vs 101A stay distinct). */
function findRoomByNumber(roomNumber) {
  const escaped = String(roomNumber).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return Room.findOne({ roomNumber: { $regex: `^${escaped}$`, $options: 'i' } });
}

function toObjectId(value, field = 'id') {
  if (!mongoose.isValidObjectId(value)) {
    throw new ValidationError([{ field, message: 'Invalid identifier' }]);
  }
  return new mongoose.Types.ObjectId(String(value));
}

async function createRoom(body) {
  const data = collect((ok) => ({
    roomNumber: requireText(body.roomNumber, 'Room number', { max: 40 }),
    status: body.status ? oneOf(body.status, ROOM_STATUSES, 'Status') : 'Empty',
    notes: ok(() => optionalText(body.notes, 'Notes', { max: 1000 })),
  }));
  const exists = await findRoomByNumber(data.roomNumber);
  if (exists) {
    throw new ValidationError([{ field: 'roomNumber', message: 'This room number already exists' }]);
  }
  try {
    return await Room.create(data);
  } catch (err) {
    if (err && err.code === 11000) {
      throw new ValidationError([
        { field: 'roomNumber', message: 'This room number already exists' },
      ]);
    }
    throw err;
  }
}

async function updateRoom(id, body) {
  const room = await Room.findById(toObjectId(id, 'roomId'));
  if (!room) throw new ValidationError([{ field: 'roomId', message: 'Room not found' }]);
  const data = collect((ok) => ({
    roomNumber: body.roomNumber === undefined
      ? room.roomNumber
      : requireText(body.roomNumber, 'Room number', { max: 40 }),
    status: body.status === undefined ? room.status : oneOf(body.status, ROOM_STATUSES, 'Status'),
    notes: body.notes === undefined ? room.notes : ok(() => optionalText(body.notes, 'Notes', { max: 1000 })),
  }));
  room.roomNumber = data.roomNumber;
  room.status = data.status;
  room.notes = data.notes;
  try {
    await room.save();
  } catch (err) {
    if (err && err.code === 11000) {
      throw new ValidationError([
        { field: 'roomNumber', message: 'This room number already exists' },
      ]);
    }
    throw err;
  }
  return room;
}

/** Rooms are never deleted while members or financial history reference them. */
async function deleteRoom(id) {
  const room = await Room.findById(toObjectId(id, 'roomId'));
  if (!room) throw new ValidationError([{ field: 'roomId', message: 'Room not found' }]);
  const members = await Member.countDocuments({ roomId: room._id });
  if (members > 0) {
    throw new ValidationError([
      {
        field: 'roomId',
        message: 'This room still has members (active or vacated). Vacate or move them first.',
      },
    ]);
  }
  const periods = await RentPeriod.countDocuments({ roomId: room._id });
  if (periods > 0) {
    throw new ValidationError([
      { field: 'roomId', message: 'This room has rent history and cannot be deleted.' },
    ]);
  }
  await room.deleteOne();
  return room;
}

/**
 * Rooms joined with their current-period rollup.
 * Periods are (re)generated for active members first so totals are current.
 */
async function listRoomsWithSummary({ search = '', status = 'All', paymentState = 'All' } = {}) {
  const reference = today();
  await ensurePeriodsForActiveMembers({ reference });

  let matchingRoomIds = null;
  if (search) {
    const term = search.trim();
    const memberFilter = {
      $or: [
        { name: { $regex: term, $options: 'i' } },
        { mobile: { $regex: term, $options: 'i' } },
        { aadhaarNumber: { $regex: term, $options: 'i' } },
      ],
    };
    const memberRooms = await Member.find(memberFilter).distinct('roomId');
    matchingRoomIds = memberRooms.map((r) => r.toString());
  }

  const roomFilter = {};
  if (status !== 'All' && ROOM_STATUSES.includes(status)) roomFilter.status = status;
  if (search) {
    const rx = { $regex: search.trim(), $options: 'i' };
    const ors = [{ roomNumber: rx }];
    if (matchingRoomIds && matchingRoomIds.length) ors.push({ _id: { $in: matchingRoomIds.map((r) => new mongoose.Types.ObjectId(r)) } });
    roomFilter.$or = ors;
  }

  const rooms = await Room.find(roomFilter).sort({ roomNumber: 1 }).lean();

  const roomIds = rooms.map((r) => r._id);
  const [members, periods] = await Promise.all([
    Member.find({ roomId: { $in: roomIds }, status: 'active' })
      .select('roomId monthlyRent rentStartDate')
      .lean(),
    RentPeriod.find({
      roomId: { $in: roomIds },
      startDate: { $lte: reference },
      endDate: { $gte: reference },
    })
      .select('memberId roomId startDate endDate rentAmount paidAmount pendingAmount status')
      .lean(),
  ]);

  const membersByRoom = new Map();
  for (const m of members) {
    const key = m.roomId.toString();
    if (!membersByRoom.has(key)) membersByRoom.set(key, []);
    membersByRoom.get(key).push(m);
  }
  const periodsByRoom = new Map();
  for (const p of periods) {
    const key = p.roomId.toString();
    if (!periodsByRoom.has(key)) periodsByRoom.set(key, []);
    periodsByRoom.get(key).push(p);
  }

  let rows = rooms.map((room) => {
    const roomMembers = membersByRoom.get(room._id.toString()) || [];
    const roomPeriods = periodsByRoom.get(room._id.toString()) || [];
    const summary = summarise(
      roomPeriods.map((p) => ({
        rent: p.rentAmount,
        paid: p.paidAmount,
        pending: p.pendingAmount,
        status: p.status,
      }))
    );
    const periodStart = roomPeriods.length
      ? roomPeriods.reduce((min, p) => (p.startDate < min ? p.startDate : min), roomPeriods[0].startDate)
      : null;
    const periodEnd = roomPeriods.length
      ? roomPeriods.reduce((max, p) => (p.endDate > max ? p.endDate : max), roomPeriods[0].endDate)
      : null;
    return {
      ...room,
      memberCount: roomMembers.length,
      totalRent: summary.totalRent,
      totalPaid: summary.totalPaid,
      totalPending: summary.totalPending,
      paymentState: summary.paymentState,
      periodStart,
      periodEnd,
    };
  });

  if (paymentState !== 'All' && PAYMENT_FILTERS.includes(paymentState)) {
    rows = rows.filter((r) => r.paymentState === paymentState);
  }
  return rows;
}

/** Full detail for the Room Details page, for the selected date range. */
async function roomDetail(id, selectedRange) {
  const room = await Room.findById(toObjectId(id, 'roomId')).lean();
  if (!room) throw new ValidationError([{ field: 'roomId', message: 'Room not found' }]);

  await ensurePeriodsForActiveMembers({ roomId: room._id });

  const members = await Member.find({ roomId: room._id, status: 'active' })
    .sort({ name: 1 })
    .lean();
  const memberIds = members.map((m) => m._id);

  const periods = memberIds.length
    ? await RentPeriod.find({ memberId: { $in: memberIds } })
        .sort({ startDate: 1 })
        .lean()
    : [];

  const ranges = [];
  const seen = new Set();
  for (const p of periods) {
    const key = `${p.startDate.toISOString()}|${p.endDate.toISOString()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    ranges.push({ start: p.startDate, end: p.endDate });
  }
  ranges.sort((a, b) => b.start - a.start);

  const reference = today();
  const currentRangeOption = ranges.find(
    (r) => startOfDay(r.start) <= reference && startOfDay(r.end) >= reference
  );
  const range = selectedRange || currentRangeOption || ranges[0] || null;

  const rows = members.map((member) => {
    const own = periods.filter((p) => p.memberId.toString() === member._id.toString());
    const selected = range
      ? own.find(
          (p) => startOfDay(p.startDate) <= startOfDay(range.end) && startOfDay(p.endDate) >= startOfDay(range.start)
        ) || null
      : null;
    return {
      member,
      period: selected,
      status: selected ? selected.status : 'No period',
    };
  });

  const summary = summarise(
    rows.filter((r) => r.period).map((r) => ({
      rent: r.period.rentAmount,
      paid: r.period.paidAmount,
      pending: r.period.pendingAmount,
      status: r.period.status,
    }))
  );

  const historical = await Member.find({ roomId: room._id, status: 'inactive' })
    .sort({ vacatingDate: -1 })
    .lean();

  return {
    room,
    members: rows,
    summary: { ...summary, memberCount: members.length },
    ranges,
    range,
    historical,
  };
}

module.exports = {
  PAYMENT_FILTERS,
  createRoom,
  deleteRoom,
  findRoomByNumber,
  listRoomsWithSummary,
  roomDetail,
  toObjectId,
  updateRoom,
};
