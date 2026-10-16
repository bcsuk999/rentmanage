'use strict';

const Member = require('../models/Member');
const RentPeriod = require('../models/RentPeriod');
const Room = require('../models/Room');
const { ensurePeriodsForActiveMembers } = require('./rentService');
const { today } = require('../utils/dates');
const { requireOwnerId } = require('../utils/owner');

const round = (n) => Math.round(n * 100) / 100;

/**
 * Every member holding at least one overdue cycle, with each overdue period
 * and member-level totals. Sorted by highest overdue amount first so the
 * biggest dues are on top.
 */
async function overdueReport(ownerId) {
  const owner = requireOwnerId(ownerId);
  const reference = today();
  await ensurePeriodsForActiveMembers({ reference, ownerId: owner });

  const periods = await RentPeriod.find({ ownerId: owner, status: 'Overdue' })
    .sort({ endDate: 1 })
    .lean();
  if (!periods.length) {
    return { members: [], summary: { memberCount: 0, periodCount: 0, totalOverdue: 0 } };
  }

  const memberIds = [...new Set(periods.map((p) => p.memberId.toString()))];
  const members = await Member.find({ ownerId: owner, _id: { $in: memberIds } })
    .select('name mobile roomId status')
    .lean();
  const memberById = new Map(members.map((m) => [m._id.toString(), m]));

  const roomIds = [...new Set(members.map((m) => m.roomId.toString()))];
  const rooms = await Room.find({ ownerId: owner, _id: { $in: roomIds } }).select('roomNumber').lean();
  const roomById = new Map(rooms.map((r) => [r._id.toString(), r.roomNumber]));

  const byMember = new Map();
  for (const p of periods) {
    const key = p.memberId.toString();
    if (!byMember.has(key)) byMember.set(key, []);
    byMember.get(key).push({
      id: p._id,
      startDate: p.startDate,
      endDate: p.endDate,
      rentAmount: p.rentAmount,
      paidAmount: p.paidAmount,
      pendingAmount: p.pendingAmount,
      status: p.status,
    });
  }

  const rows = [];
  for (const [key, list] of byMember) {
    const member = memberById.get(key);
    if (!member) continue;
    rows.push({
      memberId: member._id,
      name: member.name,
      mobile: member.mobile,
      memberStatus: member.status,
      roomId: member.roomId,
      roomNumber: roomById.get(member.roomId.toString()) || '-',
      periodCount: list.length,
      totalOverdue: round(list.reduce((s, p) => s + (p.pendingAmount || 0), 0)),
      periods: list,
    });
  }
  rows.sort((a, b) => b.totalOverdue - a.totalOverdue);

  return {
    members: rows,
    summary: {
      memberCount: rows.length,
      periodCount: periods.length,
      totalOverdue: round(rows.reduce((s, r) => s + r.totalOverdue, 0)),
    },
  };
}

module.exports = { overdueReport };
