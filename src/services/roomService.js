'use strict';

const mongoose = require('mongoose');
const Room = require('../models/Room');
const Member = require('../models/Member');
const RentPeriod = require('../models/RentPeriod');
const Payment = require('../models/Payment');
const { ROOM_STATUSES } = require('../models/Room');
const { ensurePeriodsForActiveMembers, selectPeriodsByMember, summarise } = require('./rentService');
const { MONTHS, parseDateInput, startOfDay, today } = require('../utils/dates');
const { requireOwnerId } = require('../utils/owner');
const {
  ValidationError,
  collect,
  oneOf,
  optionalText,
  requireCapacity,
  requireText,
} = require('../utils/validate');

const PAYMENT_FILTERS = ['Fully Paid', 'Partial', 'Pending', 'Overdue'];

const round2 = (n) => Math.round(n * 100) / 100;

/** '15 Sep' - day is not zero padded, it reads as a natural label. */
function shortDay(value) {
  const d = startOfDay(value);
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
}

/**
 * One label covering every overdue cycle of a member: earliest start to latest
 * end, e.g. '15 Sep to 16 Oct'.
 */
function overduePeriodLabel(periods) {
  const start = periods.reduce((min, p) => (p.startDate < min ? p.startDate : min), periods[0].startDate);
  const end = periods.reduce((max, p) => (p.endDate > max ? p.endDate : max), periods[0].endDate);
  return `${shortDay(start)} to ${shortDay(end)}`;
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

/**
 * Rooms joined with their period rollup.
 * Periods are (re)generated for active members first so totals are current.
 * Without from/to this covers each member's current cycle; with an explicit
 * range every snapshot (room totals, per-member rows) comes from the periods
 * overlapping that range, so list screens can show any month.
 */
async function listRoomsWithSummary({ search = '', status = 'All', paymentState = 'All', from = null, to = null, ownerId = null } = {}) {
  const owner = requireOwnerId(ownerId);
  const reference = today();
  let range = null;
  if (from || to) {
    const parsedFrom = from ? parseDateInput(from) : null;
    const parsedTo = to ? parseDateInput(to) : null;
    if (!parsedFrom || !parsedTo || parsedFrom > parsedTo) {
      throw new ValidationError([
        { field: 'to', message: 'Give a valid from and to date (YYYY-MM-DD) with to on or after from' },
      ]);
    }
    range = { from: startOfDay(parsedFrom), to: startOfDay(parsedTo) };
  }
  const effectiveRef = range ? range.to : reference;
  await ensurePeriodsForActiveMembers({ reference: effectiveRef, ownerId: owner });

  // Every room is loaded and rolled up unfiltered; the list filters are applied
  // to that result in memory. That keeps one query per collection (the summary
  // needs the full set anyway) and guarantees the summary stays portfolio-wide
  // while the list narrows.
  const rooms = await Room.find({ ownerId: owner }).sort({ roomNumber: 1 }).lean();

  const roomIds = rooms.map((r) => r._id);
  const periodMatch = range
    ? {
      ownerId: owner,
      roomId: { $in: roomIds },
      startDate: { $lte: range.to },
      endDate: { $gte: range.from },
    }
    : {
      ownerId: owner,
      roomId: { $in: roomIds },
      startDate: { $lte: reference },
      endDate: { $gte: reference },
    };
  const [members, periods, overduePeriods] = await Promise.all([
    Member.find({ ownerId: owner, roomId: { $in: roomIds }, status: 'active' })
      .select('roomId name mobile aadhaarNumber monthlyRent rentStartDate')
      .lean(),
    RentPeriod.find(periodMatch)
      .sort({ startDate: 1 })
      .select('memberId roomId startDate endDate rentAmount paidAmount pendingAmount status')
      .lean(),
    // Lapsed cycles are independent of the selected range, so they need their
    // own query: every overdue period of every active member in these rooms.
    RentPeriod.find({
      ownerId: owner,
      roomId: { $in: roomIds },
      status: 'Overdue',
      pendingAmount: { $gt: 0 },
    })
      .sort({ startDate: 1 })
      .select('memberId startDate endDate pendingAmount')
      .lean(),
  ]);

  const membersByRoom = new Map();
  for (const m of members) {
    const key = m.roomId.toString();
    if (!membersByRoom.has(key)) membersByRoom.set(key, []);
    membersByRoom.get(key).push(m);
  }
  const periodsByMember = new Map();
  // One row per member: the cycle active at the reference point (today while the
  // range covers today, else the range end) or the earliest overlapping cycle.
  // This makes a freshly started cycle show its due immediately, instead of the
  // just-ended (already paid) cycle it replaced.
  const now = today();
  const inRange = range && startOfDay(now) >= range.from && startOfDay(now) <= range.to;
  const rowReference = range && !inRange ? range.to : now;
  // First occurrence per member is the fallback; a cycle containing the
  // reference overrides it.
  for (const [key, p] of selectPeriodsByMember(periods, rowReference)) {
    periodsByMember.set(key, p);
  }

  // Lapsed cycles grouped per member, for the per-member overdue badge.
  const overdueByMember = new Map();
  for (const p of overduePeriods) {
    const key = p.memberId.toString();
    if (!overdueByMember.has(key)) overdueByMember.set(key, []);
    overdueByMember.get(key).push(p);
  }

  // Cash actually received in the window these cards show: every payment dated
  // inside the range. Without an explicit range the window is the span of the
  // selected cycles, which is what /api/reports defaults to as well. These
  // figures cover every room, so a paymentState filter on the list does not
  // narrow them (same as the separate /api/reports call did).
  const selectedCycles = [...periodsByMember.values()];
  const cashFrom = range ? range.from : selectedCycles.reduce(
    (min, p) => (p.startDate < min ? p.startDate : min),
    startOfDay(reference),
  );
  const cashTo = range ? range.to : selectedCycles.reduce(
    (max, p) => (p.endDate > max ? p.endDate : max),
    startOfDay(reference),
  );
  const paymentsInRange = roomIds.length
    ? await Payment.find({
        ownerId: owner,
        roomId: { $in: roomIds },
        paymentDate: { $gte: cashFrom, $lte: cashTo },
      })
        .select('amount paymentMethod')
        .lean()
    : [];
  const methodTotals = paymentsInRange.reduce((acc, p) => {
    acc[p.paymentMethod] = round2((acc[p.paymentMethod] || 0) + p.amount);
    return acc;
  }, {});

  const allRows = rooms.map((room) => {
    const roomMembers = membersByRoom.get(room._id.toString()) || [];
    // One period per member — the same single period shown on each member row.
    // Summing every overlapping period would double-count when a member's cycle
    // straddles the selected month (cycles are anchored to the member's own
    // rent start day, so a calendar month can overlap two of them).
    const roomPeriods = roomMembers
      .map((m) => periodsByMember.get(m._id.toString()))
      .filter(Boolean);
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
      ...publicRoom(room),
      memberCount: roomMembers.length,
      capacity: room.capacity || roomMembers.length,
      isFull: roomMembers.length >= (room.capacity || roomMembers.length),
      totalRent: summary.totalRent,
      totalPaid: summary.totalPaid,
      totalPending: summary.totalPending,
      paymentState: summary.paymentState,
      periodStart,
      periodEnd,
      // Per-member snapshot for mobile room cards. In range mode a member
      // without an overlapping period owes nothing that month.
      members: roomMembers.map((m) => {
        const key = m._id.toString();
        const p = periodsByMember.get(key);
        // { period: '15 Sep to 16 Oct', amt: 1500 } when the member still owes
        // lapsed cycles; null when there is nothing overdue.
        const lapsed = overdueByMember.get(key) || [];
        const overdue = lapsed.length
          ? {
            period: overduePeriodLabel(lapsed),
            amt: round2(lapsed.reduce((s, q) => s + (q.pendingAmount || 0), 0)),
          }
          : null;
        if (!p && range) {
          return {
            id: m._id,
            name: m.name,
            rent: 0,
            paid: 0,
            pending: 0,
            status: 'No period',
            dueDate: null,
            overdue,
          };
        }
        return {
          id: m._id,
          name: m.name,
          rent: p ? p.rentAmount : m.monthlyRent || 0,
          paid: p ? p.paidAmount : 0,
          pending: p ? p.pendingAmount : m.monthlyRent || 0,
          status: p ? p.status : 'Pending',
          dueDate: p ? p.endDate : null,
          overdue,
        };
      }),
    };
  });

  // Filters narrow the list only; `totals` below stays portfolio-wide.
  let rows = allRows;
  if (status !== 'All' && ROOM_STATUSES.includes(status)) {
    rows = rows.filter((r) => r.status === status);
  }
  if (search) {
    // Room numbers match on their indexed prefix; member search hits name,
    // mobile and aadhaar. Member docs are read from the lookup map, never from
    // the response rows, so mobile/aadhaar are never serialised out.
    const term = search.trim().toLowerCase();
    rows = rows.filter((r) => {
      if (String(r.roomNumber).toLowerCase().startsWith(term)) return true;
      const roomMembers = membersByRoom.get(r._id.toString()) || [];
      return roomMembers.some(
        (m) =>
          String(m.name).toLowerCase().includes(term) ||
          String(m.mobile).toLowerCase().includes(term) ||
          String(m.aadhaarNumber).toLowerCase().includes(term)
      );
    });
  }
  if (paymentState !== 'All' && PAYMENT_FILTERS.includes(paymentState)) {
    rows = rows.filter((r) => r.paymentState === paymentState);
  }
  return {
    rooms: rows,
    cash: {
      // Pending on cycles that are already past their due date, using the same
      // "one cycle per member" selection as the rent figures above - identical
      // to /api/reports totals.overduePending.
      overduePending: round2(selectedCycles
        .filter((p) => p.status === 'Overdue')
        .reduce((s, p) => s + (p.pendingAmount || 0), 0)),
      cashFrom,
      cashTo,
      receivedInRange: round2(paymentsInRange.reduce((s, p) => s + (p.amount || 0), 0)),
      paymentCount: paymentsInRange.length,
      methodTotals,
    },
    totals: {
      roomCount: allRows.length,
      memberCount: allRows.reduce((s, r) => s + r.memberCount, 0),
      totalRent: round2(allRows.reduce((s, r) => s + r.totalRent, 0)),
      totalPaid: round2(allRows.reduce((s, r) => s + r.totalPaid, 0)),
      totalPending: round2(allRows.reduce((s, r) => s + r.totalPending, 0)),
    },
  };
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

  const historical = await Member.find({ ownerId: owner, roomId: room._id, status: 'inactive' })
    .sort({ vacatingDate: -1 })
    .lean();

  return {
    room: publicRoom(room),
    members: rows,
    summary: { ...summary, memberCount: members.length },
    capacity: room.capacity || members.length,
    isFull: members.length >= (room.capacity || members.length),
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
