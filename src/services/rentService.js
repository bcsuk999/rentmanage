'use strict';

const RentPeriod = require('../models/RentPeriod');
const Member = require('../models/Member');
const Payment = require('../models/Payment');
const { addDays, cycleAt, cycleIndexFor, isOverdue, startOfDay, today } = require('../utils/dates');

/** Cycles generated ahead of today so advance payments can be recorded early. */
const FUTURE_CYCLES = 1;

/**
 * Derive paid/pending/status from server-side values only.
 * Pending = rent - paid. Zero pending => Paid. Ended with pending => Overdue.
 */
function deriveTotals(rentAmount, paidAmount, endDate, reference = today()) {
  const rent = Number(rentAmount) || 0;
  const paid = Math.max(0, Number(paidAmount) || 0);
  const pending = Math.max(0, Math.round((rent - paid) * 100) / 100);
  let status;
  if (pending <= 0) {
    status = 'Paid';
  } else if (isOverdue(endDate, reference)) {
    status = 'Overdue';
  } else if (paid > 0) {
    status = 'Partial';
  } else {
    status = 'Pending';
  }
  return { rentAmount: rent, paidAmount: paid, pendingAmount: pending, status };
}

/** Last cycle a member should own: today's cycle (plus FUTURE_CYCLES) or the vacating month. */
function generationCeiling(member, reference = today()) {
  const anchor = startOfDay(member.rentStartDate);
  const lastIndex = cycleIndexFor(anchor, reference);
  if (lastIndex < 0) return -1;
  const ceiling = addDays(cycleAt(anchor, lastIndex + FUTURE_CYCLES).end, 0);
  if (member.vacatingDate) {
    const vacate = startOfDay(member.vacatingDate);
    if (vacate < ceiling) return vacate;
  }
  return ceiling;
}

/**
 * Create any missing rent periods for one member.
 * Uses the member's own rent start date as the cycle anchor, so every member
 * gets an individual rental cycle. Never creates overlapping cycles.
 */
async function ensurePeriodsForMember(member, reference = today()) {
  const anchor = startOfDay(member.rentStartDate);
  const ceiling = generationCeiling(member, reference);
  if (ceiling < anchor) return [];

  const existing = await RentPeriod.find({ memberId: member._id })
    .sort({ startDate: 1 })
    .select('startDate endDate')
    .lean();
  const knownStarts = new Set(existing.map((p) => startOfDay(p.startDate).getTime()));

  const created = [];
  const lastIndex = cycleIndexFor(anchor, ceiling);
  for (let index = 0; index <= lastIndex; index += 1) {
    const { start, end } = cycleAt(anchor, index);
    if (start > ceiling) break;
    if (knownStarts.has(start.getTime())) continue;
    // Guard against overlaps with an already stored period.
    const overlaps = existing.some(
      (p) => startOfDay(p.startDate) < end && startOfDay(p.endDate) >= start
    ) || created.some((p) => p.startDate < end && p.endDate >= start);
    if (overlaps) continue;
    try {
      const doc = await RentPeriod.create({
        memberId: member._id,
        roomId: member.roomId,
        startDate: start,
        endDate: end,
        rentAmount: member.monthlyRent,
        paidAmount: 0,
        pendingAmount: member.monthlyRent,
        status: 'Pending',
      });
      knownStarts.add(start.getTime());
      created.push(doc);
    } catch (err) {
      if (err && err.code === 11000) continue; // created concurrently
      throw err;
    }
  }
  return created;
}

/** Generate periods for every active member (optionally scoped to one room). */
async function ensurePeriodsForActiveMembers({ roomId = null, reference = today() } = {}) {
  const filter = { status: 'active' };
  if (roomId) filter.roomId = roomId;
  const members = await Member.find(filter).lean();
  let created = 0;
  for (const member of members) {
    created += (await ensurePeriodsForMember(member, reference)).length;
  }
  return { members: members.length, created };
}

/** Recompute one period from its payment records. */
async function recalcPeriod(periodId, reference = today()) {
  const period = await RentPeriod.findById(periodId);
  if (!period) return null;
  const totals = await Payment.aggregate([
    { $match: { rentPeriodId: period._id } },
    { $group: { _id: null, paid: { $sum: '$amount' } } },
  ]);
  const paid = totals.length ? totals[0].paid : 0;
  const next = deriveTotals(period.rentAmount, paid, period.endDate, reference);
  period.paidAmount = next.paidAmount;
  period.pendingAmount = next.pendingAmount;
  period.status = next.status;
  await period.save();
  return period;
}

/** The member's period that contains `date`, creating cycles when needed. */
async function periodForDate(member, date, reference = today()) {
  await ensurePeriodsForMember(member, reference);
  const anchor = startOfDay(member.rentStartDate);
  const index = cycleIndexFor(anchor, date);
  if (index < 0) return null;
  const { start, end } = cycleAt(anchor, index);
  return RentPeriod.findOne({ memberId: member._id, startDate: start, endDate: end });
}

/** The member's current period: the cycle containing today (or latest started period). */
async function currentPeriodForMember(member, reference = today()) {
  await ensurePeriodsForMember(member, reference);
  const current = await RentPeriod.findOne({
    memberId: member._id,
    startDate: { $lte: reference },
    endDate: { $gte: reference },
  })
    .sort({ startDate: -1 })
    .lean();
  if (current) return current;
  // Never fall back to a future (not-yet-started) advance cycle.
  return RentPeriod.findOne({ memberId: member._id, startDate: { $lte: reference } })
    .sort({ startDate: -1 })
    .lean();
}

/** Distinct rental periods that exist in a room, newest first (room period selector). */
async function roomPeriodOptions(roomId, limit = 24) {
  return RentPeriod.aggregate([
    { $match: { roomId: roomId._id || roomId } },
    { $group: { _id: { startDate: '$startDate', endDate: '$endDate' }, rentAmount: { $sum: '$rentAmount' } } },
    { $sort: { '_id.startDate': -1 } },
    { $limit: limit },
    {
      $project: {
        _id: 0,
        startDate: '$_id.startDate',
        endDate: '$_id.endDate',
        totalRent: '$rentAmount',
      },
    },
  ]);
}

/** Pick a member's period that overlaps a room-level selected range. */
function periodOverlapping(periods, range) {
  if (!range) return null;
  const { start, end } = range;
  return (
    periods.find((p) => startOfDay(p.startDate) <= end && startOfDay(p.endDate) >= start) || null
  );
}

/** Roll up member periods into room totals. */
function summarise(members) {
  const totals = members.reduce(
    (acc, m) => {
      acc.rent += m.rent || 0;
      acc.paid += m.paid || 0;
      acc.pending += m.pending || 0;
      return acc;
    },
    { rent: 0, paid: 0, pending: 0 }
  );
  const statuses = new Set(members.map((m) => m.status).filter(Boolean));
  let paymentState = 'None';
  if (statuses.size) {
    const list = [...statuses];
    if (list.includes('Overdue')) paymentState = 'Overdue';
    else if (list.every((s) => s === 'Paid')) paymentState = 'Fully Paid';
    else if (list.every((s) => s === 'Pending')) paymentState = 'Pending';
    else paymentState = 'Partial';
  }
  return {
    memberCount: members.length,
    totalRent: Math.round(totals.rent * 100) / 100,
    totalPaid: Math.round(totals.paid * 100) / 100,
    totalPending: Math.round(totals.pending * 100) / 100,
    paymentState,
  };
}

module.exports = {
  FUTURE_CYCLES,
  currentPeriodForMember,
  deriveTotals,
  ensurePeriodsForActiveMembers,
  ensurePeriodsForMember,
  generationCeiling,
  periodForDate,
  periodOverlapping,
  recalcPeriod,
  roomPeriodOptions,
  summarise,
};
