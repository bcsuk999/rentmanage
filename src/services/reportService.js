'use strict';

const mongoose = require('mongoose');
const Room = require('../models/Room');
const Member = require('../models/Member');
const RentPeriod = require('../models/RentPeriod');
const Payment = require('../models/Payment');
const { ensurePeriodsForActiveMembers, selectPeriodsByMember } = require('./rentService');
const { startOfDay, today } = require('../utils/dates');
const { ValidationError } = require('../utils/validate');

/** Periods that overlap the requested date range. */
function overlapFilter(from, to) {
  return { startDate: { $lte: to }, endDate: { $gte: from } };
}

function sum(arr, pick) {
  return Math.round(arr.reduce((s, x) => s + (pick(x) || 0), 0) * 100) / 100;
}

function countByStatus(periods) {
  const counts = { Paid: 0, Partial: 0, Pending: 0, Overdue: 0 };
  for (const p of periods) {
    if (counts[p.status] !== undefined) counts[p.status] += 1;
  }
  return counts;
}

/**
 * Report for an explicit date range (e.g. 15 Sep -> 14 Oct).
 * Rent figures come from the rent periods overlapping the range; cash figures
 * come from payments actually made inside the range.
 */
async function buildReport({ from, to, roomId = null }) {
  const range = { from: startOfDay(from), to: startOfDay(to) };
  await ensurePeriodsForActiveMembers({ reference: range.to });

  let roomObjectId = null;
  if (roomId) {
    if (!mongoose.isValidObjectId(String(roomId))) {
      throw new ValidationError([{ field: 'roomId', message: 'Invalid room filter' }]);
    }
    roomObjectId = new mongoose.Types.ObjectId(String(roomId));
  }

  const periodQuery = overlapFilter(range.from, range.to);
  if (roomObjectId) periodQuery.roomId = roomObjectId;

  const periods = await RentPeriod.find(periodQuery)
    .sort({ startDate: 1 })
    .populate('memberId', 'name mobile status roomId')
    .populate('roomId', 'roomNumber status')
    .lean();

  // Rent figures use ONE period per member. Cycles are anchored to each
  // member's own rent start day, so a range can include a just-ended (paid)
  // cycle and a just-started one; prefer the cycle active at the reference
  // point (today when the range covers today, else the range end). Cash figures
  // (below) still use every overlapping period so received payments are
  // complete.
  const now = today();
  const inRange = startOfDay(now) >= range.from && startOfDay(now) <= range.to;
  const rowReference = inRange ? now : range.to;
  const primaryPeriods = [...selectPeriodsByMember(periods, rowReference).values()];

  const periodIds = periods.map((p) => p._id);
  const paymentsInRange = periodIds.length
    ? await Payment.find({
        rentPeriodId: { $in: periodIds },
        paymentDate: { $gte: range.from, $lte: range.to },
      })
        .select('amount paymentMethod')
        .lean()
    : [];

  const roomFilter = {};
  if (roomObjectId) roomFilter._id = roomObjectId;
  const rooms = await Room.find(roomFilter).select('roomNumber status').lean();
  const memberFilter = roomObjectId ? { roomId: roomObjectId } : {};
  const memberCount = await Member.countDocuments({ ...memberFilter, status: 'active' });
  const allMemberCount = await Member.countDocuments(memberFilter);

  const methodTotals = paymentsInRange.reduce((acc, p) => {
    acc[p.paymentMethod] = (acc[p.paymentMethod] || 0) + p.amount;
    return acc;
  }, {});

  const byRoomMap = new Map();
  const byMemberMap = new Map();
  for (const p of primaryPeriods) {
    const roomKey = p.roomId ? p.roomId._id.toString() : 'unknown';
    const roomLabel = p.roomId ? p.roomId.roomNumber : 'Unknown room';
    if (!byRoomMap.has(roomKey)) {
      byRoomMap.set(roomKey, {
        roomId: roomKey,
        roomNumber: roomLabel,
        roomStatus: p.roomId ? p.roomId.status : '-',
        periods: 0,
        totalRent: 0,
        totalPaid: 0,
        totalPending: 0,
        statuses: new Set(),
      });
    }
    const room = byRoomMap.get(roomKey);
    room.periods += 1;
    room.totalRent += p.rentAmount;
    room.totalPaid += p.paidAmount;
    room.totalPending += p.pendingAmount;
    room.statuses.add(p.status);

    const memberKey = p.memberId ? p.memberId._id.toString() : 'unknown';
    if (!byMemberMap.has(memberKey)) {
      byMemberMap.set(memberKey, {
        memberId: memberKey,
        name: p.memberId ? p.memberId.name : 'Unknown member',
        mobile: p.memberId ? p.memberId.mobile : '-',
        memberStatus: p.memberId ? p.memberId.status : '-',
        roomNumber: roomLabel,
        periods: 0,
        totalRent: 0,
        totalPaid: 0,
        totalPending: 0,
        status: p.status,
      });
    }
    const member = byMemberMap.get(memberKey);
    member.periods += 1;
    member.totalRent += p.rentAmount;
    member.totalPaid += p.paidAmount;
    member.totalPending += p.pendingAmount;
    member.status = p.status; // most recent period in range (periods sorted ascending)
  }

  const byRoom = [...byRoomMap.values()]
    .map((r) => ({ ...r, statuses: undefined, paymentState: rollup([...r.statuses]) }))
    .sort((a, b) => String(a.roomNumber).localeCompare(String(b.roomNumber), undefined, { numeric: true }));
  const byMember = [...byMemberMap.values()].sort((a, b) =>
    a.name.localeCompare(b.name, undefined, { numeric: true })
  );

  const counts = countByStatus(primaryPeriods);

  return {
    range,
    totals: {
      totalRooms: rooms.length,
      totalMembers: memberCount,
      totalHistoricalMembers: allMemberCount,
      totalRent: sum(primaryPeriods, (p) => p.rentAmount),
      totalPaid: sum(primaryPeriods, (p) => p.paidAmount),
      totalPending: sum(primaryPeriods, (p) => p.pendingAmount),
      overduePending: sum(primaryPeriods.filter((p) => p.status === 'Overdue'), (p) => p.pendingAmount),
      receivedInRange: sum(paymentsInRange, (p) => p.amount),
      paymentCount: paymentsInRange.length,
      methodTotals,
      periodCount: primaryPeriods.length,
      paidMembers: counts.Paid,
      partialMembers: counts.Partial,
      pendingMembers: counts.Pending,
      overdueMembers: counts.Overdue,
    },
    byRoom,
    byMember,
  };
}

function rollup(statuses) {
  if (!statuses.length) return 'None';
  if (statuses.includes('Overdue')) return 'Overdue';
  if (statuses.every((s) => s === 'Paid')) return 'Fully Paid';
  if (statuses.every((s) => s === 'Pending')) return 'Pending';
  return 'Partial';
}

/** Default report range: the current rental cycle for the whole system. */
async function defaultRange() {
  const reference = today();
  const first = await RentPeriod.find().sort({ startDate: 1 }).select('startDate endDate').lean();
  const started = first.filter((p) => startOfDay(p.startDate) <= reference);
  const current =
    first.find((p) => startOfDay(p.startDate) <= reference && startOfDay(p.endDate) >= reference) ||
    started[started.length - 1] ||
    first[first.length - 1];
  return current
    ? { from: startOfDay(current.startDate), to: startOfDay(current.endDate) }
    : { from: reference, to: reference };
}

module.exports = { buildReport, defaultRange };
