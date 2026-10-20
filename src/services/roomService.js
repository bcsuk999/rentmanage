'use strict';

const mongoose = require('mongoose');
const Room = require('../models/Room');
const Member = require('../models/Member');
const RentPeriod = require('../models/RentPeriod');
const { ROOM_STATUSES } = require('../models/Room');
const { ensurePeriodsForActiveMembers, summarise } = require('./rentService');
const { MONTHS, startOfDay, today } = require('../utils/dates');
const { requireOwnerId } = require('../utils/owner');
const {
  ValidationError,
  collect,
  oneOf,
  optionalText,
  requireCapacity,
  requireText,
} = require('../utils/validate');

const round2 = (n) => Math.round(n * 100) / 100;

/** '15 Sep' - day is not zero padded, it reads as a natural label. */
function shortDay(value) {
  const d = startOfDay(value);
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
}

/**
 * Carry-over from cycles that have already ended, or null when nothing is
 * overdue. The label spans the member's oldest and newest lapsed cycle, so one
 * badge covers several months.
 */
function overdueSummary(lapsed) {
  if (!lapsed.length) return null;
  const start = lapsed.reduce((min, p) => (p.startDate < min ? p.startDate : min), lapsed[0].startDate);
  const end = lapsed.reduce((max, p) => (p.endDate > max ? p.endDate : max), lapsed[0].endDate);
  const amt = round2(lapsed.reduce((total, p) => total + (p.pendingAmount || 0), 0));
  return { period: `${shortDay(start)} to ${shortDay(end)}`, amt };
}

/**
 * Public room payload. Never spread the raw document into a response: that
 * leaks ownerId, the lookup key and createdAt/updatedAt.
 */
function publicRoom(room) {
  return {
    _id: room._id,
    roomNumber: room.roomNumber,
    capacity: room.capacity,
    status: room.status,
    ...(room.notes ? { notes: room.notes } : {}),
  };
}

/** Room numbers are matched case-insensitively via the indexed roomNumberKey. */
function findRoomByNumber(roomNumber, ownerId) {
  return Room.findOne({
    ownerId: requireOwnerId(ownerId),
    roomNumberKey: String(roomNumber).trim().toLowerCase(),
  });
}

function toObjectId(value, field = 'id') {
  if (!mongoose.isValidObjectId(value)) {
    throw new ValidationError([{ field, message: 'Invalid identifier' }]);
  }
  return new mongoose.Types.ObjectId(String(value));
}

async function createRoom(body, ownerId) {
  const owner = requireOwnerId(ownerId);
  const data = collect((ok) => ({
    roomNumber: requireText(body.roomNumber, 'Room number', { max: 40 }),
    capacity: requireCapacity(body.capacity),
    status: body.status ? oneOf(body.status, ROOM_STATUSES, 'Status') : 'Empty',
    notes: ok(() => optionalText(body.notes, 'Notes', { max: 1000 })),
  }));
  const exists = await findRoomByNumber(data.roomNumber, owner);
  if (exists) {
    throw new ValidationError([{ field: 'roomNumber', message: 'This room number already exists' }]);
  }
  try {
    return await Room.create({ ...data, ownerId: owner });
  } catch (err) {
    if (err && err.code === 11000) {
      throw new ValidationError([
        { field: 'roomNumber', message: 'This room number already exists' },
      ]);
    }
    throw err;
  }
}

async function updateRoom(id, body, ownerId) {
  const room = await Room.findOne({ _id: toObjectId(id, 'roomId'), ownerId: requireOwnerId(ownerId) });
  if (!room) throw new ValidationError([{ field: 'roomId', message: 'Room not found' }]);
  const data = collect((ok) => ({
    roomNumber: body.roomNumber === undefined
      ? room.roomNumber
      : requireText(body.roomNumber, 'Room number', { max: 40 }),
    capacity: body.capacity === undefined ? room.capacity : requireCapacity(body.capacity),
    status: body.status === undefined ? room.status : oneOf(body.status, ROOM_STATUSES, 'Status'),
    notes: body.notes === undefined ? room.notes : ok(() => optionalText(body.notes, 'Notes', { max: 1000 })),
  }));
  if (data.capacity < room.capacity) {
    const activeMembers = await Member.countDocuments({ ownerId: room.ownerId, roomId: room._id, status: 'active' });
    if (data.capacity < activeMembers) {
      throw new ValidationError([
        {
          field: 'capacity',
          message: `Capacity cannot be lower than the ${activeMembers} active member(s) already in this room`,
        },
      ]);
    }
  }
  room.roomNumber = data.roomNumber;
  room.capacity = data.capacity;
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
async function deleteRoom(id, ownerId) {
  const room = await Room.findOne({ _id: toObjectId(id, 'roomId'), ownerId: requireOwnerId(ownerId) });
  if (!room) throw new ValidationError([{ field: 'roomId', message: 'Room not found' }]);
  const members = await Member.countDocuments({ ownerId: room.ownerId, roomId: room._id });
  if (members > 0) {
    throw new ValidationError([
      {
        field: 'roomId',
        message: 'This room still has members (active or vacated). Vacate or move them first.',
      },
    ]);
  }
  const periods = await RentPeriod.countDocuments({ ownerId: room.ownerId, roomId: room._id });
  if (periods > 0) {
    throw new ValidationError([
      { field: 'roomId', message: 'This room has rent history and cannot be deleted.' },
    ]);
  }
  await room.deleteOne();
  return room;
}

/** Full detail for the Room Details page, for the selected date range. */
async function roomDetail(id, selectedRange, ownerId) {
  const owner = requireOwnerId(ownerId);
  const room = await Room.findOne({ _id: toObjectId(id, 'roomId'), ownerId: owner }).lean();
  if (!room) throw new ValidationError([{ field: 'roomId', message: 'Room not found' }]);

  await ensurePeriodsForActiveMembers({ roomId: room._id, ownerId: owner });

  const members = await Member.find({ ownerId: owner, roomId: room._id, status: 'active' })
    .sort({ name: 1 })
    .lean();
  const memberIds = members.map((m) => m._id);

  const periods = memberIds.length
    ? await RentPeriod.find({ ownerId: owner, memberId: { $in: memberIds } })
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
  // Never default to a future (not-yet-started) cycle: fall back to the most
  // recent started range so due totals never include next month early.
  const startedRanges = ranges.filter((r) => startOfDay(r.start) <= reference);
  const range = selectedRange || currentRangeOption || startedRanges[0] || ranges[0] || null;

  const rows = members.map((member) => {
    const own = periods.filter((p) => p.memberId.toString() === member._id.toString());
    const selected = range
      ? own.find(
          (p) => startOfDay(p.startDate) <= startOfDay(range.end) && startOfDay(p.endDate) >= startOfDay(range.start)
        ) || null
      : null;
    // A member can owe money on ended cycles even when this cycle is settled,
    // so carry-over is measured against today rather than the selected range.
    // The selected cycle is excluded: its pending is already shown as due, and
    // on an older range it would otherwise be counted twice.
    const lapsed = own.filter(
      (p) => p !== selected && startOfDay(p.endDate) < reference && (p.pendingAmount || 0) > 0
    );
    return {
      member,
      period: selected,
      status: selected ? selected.status : 'No period',
      overdue: overdueSummary(lapsed),
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
  const totalOverdue = round2(rows.reduce((total, r) => total + (r.overdue ? r.overdue.amt : 0), 0));

  const historical = await Member.find({ ownerId: owner, roomId: room._id, status: 'inactive' })
    .sort({ vacatingDate: -1 })
    .lean();

  return {
    room: publicRoom(room),
    members: rows,
    summary: {
      ...summary,
      memberCount: members.length,
      totalOverdue,
      totalDue: round2(summary.totalPending + totalOverdue),
    },
    capacity: room.capacity || members.length,
    isFull: members.length >= (room.capacity || members.length),
    ranges,
    range,
    historical,
  };
}

module.exports = {
  createRoom,
  deleteRoom,
  findRoomByNumber,
  roomDetail,
  toObjectId,
  updateRoom,
};
