'use strict';

const Member = require('../models/Member');
const Room = require('../models/Room');
const RentPeriod = require('../models/RentPeriod');
const Payment = require('../models/Payment');
const rentService = require('./rentService');
const { toObjectId } = require('./roomService');
const { startOfDay, today } = require('../utils/dates');
const { requireOwnerId } = require('../utils/owner');
const {
  ValidationError,
  collect,
  optionalAadhaar,
  optionalText,
  requireAmount,
  requireDate,
  requireMobile,
  requireText,
} = require('../utils/validate');

async function assertRoom(roomId, ownerId) {
  const room = await Room.findOne({ _id: toObjectId(roomId, 'roomId'), ownerId: requireOwnerId(ownerId) });
  if (!room) throw new ValidationError([{ field: 'roomId', message: 'Room not found' }]);
  return room;
}

/** Vacating/adding members changes whether a room is occupied. */
async function syncRoomStatus(roomId, ownerId) {
  const room = await Room.findOne({ _id: roomId, ownerId });
  if (!room || room.status === 'Maintenance') return room;
  const active = await Member.countDocuments({ ownerId, roomId, status: 'active' });
  const next = active > 0 ? 'Occupied' : 'Empty';
  if (room.status !== next) {
    room.status = next;
    await room.save();
  }
  return room;
}

/** A room cannot hold more active members than its capacity. */
async function assertRoomHasSpace(room, field = 'roomId') {
  const capacity = Number(room.capacity);
  if (!Number.isFinite(capacity) || capacity < 1) return;
  const activeMembers = await Member.countDocuments({ ownerId: room.ownerId, roomId: room._id, status: 'active' });
  if (activeMembers >= capacity) {
    throw new ValidationError([
      {
        field,
        message: `Room ${room.roomNumber} is full: capacity is ${capacity} member(s) and all are occupied`,
      },
    ]);
  }
}

/** Add a member to a room and open their first rental cycle. */
async function createMember(body, ownerId) {
  const room = await assertRoom(body.roomId, ownerId);
  if (room.status === 'Maintenance') {
    throw new ValidationError([
      { field: 'roomId', message: 'This room is under maintenance; change its status first' },
    ]);
  }
  await assertRoomHasSpace(room);
  const rentStartDate = requireDate(body.rentStartDate, 'Rent start date');
  if (rentStartDate > today()) {
    throw new ValidationError([
      { field: 'rentStartDate', message: 'Rent start date cannot be in the future' },
    ]);
  }
  const data = collect((ok) => ({
    ownerId: room.ownerId,
    roomId: room._id,
    name: requireText(body.name, 'Name', { max: 120 }),
    mobile: requireMobile(body.mobile),
    aadhaarNumber: ok(() => optionalAadhaar(body.aadhaarNumber)),
    address: ok(() => optionalText(body.address, 'Address', { max: 500 })),
    emergencyContact: ok(() => optionalText(body.emergencyContact, 'Emergency contact', { max: 120 })),
    monthlyRent: requireAmount(body.monthlyRent, 'Monthly rent'),
    rentStartDate,
    joiningDate: rentStartDate,
    notes: ok(() => optionalText(body.notes, 'Notes', { max: 1000 })),
    status: 'active',
  }));

  const member = await Member.create(data);
  await rentService.ensurePeriodsForMember(member.toObject());
  if (room.status === 'Empty') {
    room.status = 'Occupied';
    await room.save();
  }
  return member;
}

async function updateMember(id, body, ownerId) {
  const member = await Member.findOne({ _id: toObjectId(id, 'memberId'), ownerId: requireOwnerId(ownerId) });
  if (!member) throw new ValidationError([{ field: 'memberId', message: 'Member not found' }]);
  if (member.status !== 'active' && body.status !== 'active') {
    throw new ValidationError([
      { field: 'memberId', message: 'Vacated members are read-only; their history is preserved' },
    ]);
  }

  const rentStartDate =
    body.rentStartDate === undefined ? member.rentStartDate : requireDate(body.rentStartDate, 'Rent start date');
  if (rentStartDate > today()) {
    throw new ValidationError([
      { field: 'rentStartDate', message: 'Rent start date cannot be in the future' },
    ]);
  }

  const data = collect((ok) => ({
    name: body.name === undefined ? member.name : requireText(body.name, 'Name', { max: 120 }),
    mobile: body.mobile === undefined ? member.mobile : requireMobile(body.mobile),
    aadhaarNumber:
      body.aadhaarNumber === undefined ? member.aadhaarNumber : ok(() => optionalAadhaar(body.aadhaarNumber)),
    address: body.address === undefined ? member.address : ok(() => optionalText(body.address, 'Address', { max: 500 })),
    emergencyContact:
      body.emergencyContact === undefined
        ? member.emergencyContact
        : ok(() => optionalText(body.emergencyContact, 'Emergency contact', { max: 120 })),
    monthlyRent:
      body.monthlyRent === undefined ? member.monthlyRent : requireAmount(body.monthlyRent, 'Monthly rent'),
    notes: body.notes === undefined ? member.notes : ok(() => optionalText(body.notes, 'Notes', { max: 1000 })),
  }));

  const rentChanged =
    data.monthlyRent !== member.monthlyRent || rentStartDate.getTime() !== member.rentStartDate.getTime();

  Object.assign(member, data);
  member.rentStartDate = rentStartDate;
  await member.save();

  if (rentChanged) {
    // Rent/cycle edits only affect periods that have no money against them.
    const untouched = await RentPeriod.find({ ownerId: member.ownerId, memberId: member._id, paidAmount: { $gt: 0 } })
      .select('startDate endDate')
      .lean();
    await RentPeriod.deleteMany({ ownerId: member.ownerId, memberId: member._id, paidAmount: 0 });
    await rentService.ensurePeriodsForMember(member.toObject());
    for (const period of untouched) {
      await rentService.recalcPeriod(period._id);
    }
  }
  return member;
}

/**
 * Vacate a member: the record is kept, only its status changes.
 * Future auto-generated periods beyond the vacating date are removed
 * (they carry no payments), and the remaining periods are recalculated.
 */
async function vacateMember(id, body, ownerId) {
  const member = await Member.findOne({ _id: toObjectId(id, 'memberId'), ownerId: requireOwnerId(ownerId) });
  if (!member) throw new ValidationError([{ field: 'memberId', message: 'Member not found' }]);
  if (member.status !== 'active') {
    throw new ValidationError([{ field: 'memberId', message: 'This member is already vacated' }]);
  }
  const vacatingDate = body.vacatingDate === undefined
    ? today()
    : requireDate(body.vacatingDate, 'Vacating date');
  if (vacatingDate < startOfDay(member.rentStartDate)) {
    throw new ValidationError([
      { field: 'vacatingDate', message: 'Vacating date cannot be before the rent start date' },
    ]);
  }
  const finalPeriod =
    body.finalPeriod === undefined ? undefined : requireDate(body.finalPeriod, 'Final rent period end date');
  if (finalPeriod && finalPeriod < vacatingDate) {
    throw new ValidationError([
      { field: 'finalPeriod', message: 'Final rent period cannot end before the vacating date' },
    ]);
  }
  const notes = body.notes === undefined ? undefined : String(body.notes || '').trim() || undefined;

  member.status = 'inactive';
  member.vacatingDate = vacatingDate;
  if (notes) {
    member.notes = member.notes ? `${member.notes}\n[Vacated] ${notes}` : `[Vacated] ${notes}`;
  }
  await member.save();

  // Generate the cycles the member actually lived through, then trim the rest.
  await rentService.ensurePeriodsForMember({ ...member.toObject(), vacatingDate });
  const future = await RentPeriod.find({
    ownerId: member.ownerId,
    memberId: member._id,
    startDate: { $gt: vacatingDate },
  }).select('_id paidAmount');
  const deletable = future.filter((p) => p.paidAmount === 0).map((p) => p._id);
  if (deletable.length) await RentPeriod.deleteMany({ _id: { $in: deletable } });

  const remaining = await RentPeriod.find({ ownerId: member.ownerId, memberId: member._id }).select('_id');
  for (const period of remaining) await rentService.recalcPeriod(period._id);

  const outstanding = await RentPeriod.aggregate([
    { $match: { ownerId: member.ownerId, memberId: member._id } },
    { $group: { _id: null, pending: { $sum: '$pendingAmount' } } },
  ]);
  await syncRoomStatus(member.roomId, member.ownerId);

  return {
    member,
    finalPeriod: finalPeriod || null,
    outstanding: outstanding.length ? Math.round(outstanding[0].pending * 100) / 100 : 0,
  };
}

/** Waive unpaid rent for a vacated member, oldest cycle first. */
async function waiveMemberDebt(id, body, ownerId) {
  const owner = requireOwnerId(ownerId);
  const member = await Member.findOne({ _id: toObjectId(id, 'memberId'), ownerId: owner });
  if (!member) throw new ValidationError([{ field: 'memberId', message: 'Member not found' }]);
  if (member.status !== 'inactive') {
    throw new ValidationError([
      { field: 'memberId', message: 'Debt can only be waived for a vacated member' },
    ]);
  }
  const amount = requireAmount(body.amount, 'Waive amount', { min: 0.01 });
  const notes = body.notes === undefined ? undefined : optionalText(body.notes, 'Notes', { max: 500 });
  const periods = await RentPeriod.find({
    ownerId: owner,
    memberId: member._id,
    pendingAmount: { $gt: 0 },
  }).sort({ startDate: 1 });

  const round2 = (value) => Math.round((Number(value) || 0) * 100) / 100;
  const outstanding = round2(periods.reduce((sum, p) => sum + (p.pendingAmount || 0), 0));
  if (outstanding <= 0) {
    throw new ValidationError([{ field: 'amount', message: 'This member has no outstanding balance' }]);
  }
  if (amount > outstanding + 0.001) {
    throw new ValidationError([
      { field: 'amount', message: `Amount exceeds the outstanding balance (${outstanding})` },
    ]);
  }

  let remaining = amount;
  for (const period of periods) {
    if (remaining <= 0) break;
    const pending = round2(period.pendingAmount);
    if (pending <= 0) continue;
    const take = round2(Math.min(remaining, pending));
    period.waivedAmount = round2((period.waivedAmount || 0) + take);
    await period.save();
    await rentService.recalcPeriod(period._id);
    remaining = round2(remaining - take);
  }

  if (notes) {
    member.notes = member.notes ? `${member.notes}\n[Waived] ${notes}` : `[Waived] ${notes}`;
    await member.save();
  }

  return {
    member,
    waivedAmount: amount,
    outstanding: round2(outstanding - amount),
  };
}

/** Account > Vacated Members: former tenants with their dues summary. */
async function vacatedMembers(ownerId) {
  const owner = requireOwnerId(ownerId);
  const members = await Member.find({ ownerId: owner, status: 'inactive' })
    .sort({ vacatingDate: -1, name: 1 })
    .lean();
  if (!members.length) {
    return {
      members: [],
      summary: {
        memberCount: 0,
        totalBilled: 0,
        totalCollected: 0,
        waivedAmount: 0,
        totalStillToCollect: 0,
      },
    };
  }

  const [rooms, periods] = await Promise.all([
    Room.find({ ownerId: owner, _id: { $in: [...new Set(members.map((m) => m.roomId.toString()))] } })
      .select('roomNumber')
      .lean(),
    RentPeriod.find({ ownerId: owner, memberId: { $in: members.map((m) => m._id) } })
      .sort({ startDate: 1 })
      .lean(),
  ]);
  const roomById = new Map(rooms.map((r) => [r._id.toString(), r.roomNumber]));
  const periodsByMember = new Map();
  for (const period of periods) {
    const key = period.memberId.toString();
    if (!periodsByMember.has(key)) periodsByMember.set(key, []);
    periodsByMember.get(key).push(period);
  }

  const round2 = (value) => Math.round((Number(value) || 0) * 100) / 100;
  const rows = members.map((member) => {
    const own = periodsByMember.get(member._id.toString()) || [];
    return {
      _id: member._id,
      name: member.name,
      mobile: member.mobile,
      roomId: member.roomId,
      roomNumber: roomById.get(member.roomId.toString()) || '-',
      vacatingDate: member.vacatingDate || null,
      monthlyRent: member.monthlyRent || 0,
      totalBilled: round2(own.reduce((sum, p) => sum + (p.rentAmount || 0), 0)),
      totalCollected: round2(own.reduce((sum, p) => sum + (p.paidAmount || 0), 0)),
      waivedAmount: round2(own.reduce((sum, p) => sum + (p.waivedAmount || 0), 0)),
      stillToCollect: round2(own.reduce((sum, p) => sum + (p.pendingAmount || 0), 0)),
    };
  });

  return {
    members: rows,
    summary: {
      memberCount: rows.length,
      totalBilled: round2(rows.reduce((sum, r) => sum + r.totalBilled, 0)),
      totalCollected: round2(rows.reduce((sum, r) => sum + r.totalCollected, 0)),
      waivedAmount: round2(rows.reduce((sum, r) => sum + r.waivedAmount, 0)),
      totalStillToCollect: round2(rows.reduce((sum, r) => sum + r.stillToCollect, 0)),
    },
  };
}

/** Search / filter members (used by search and the payments filters). */
async function searchMembers({ search = '', roomId = null, status = 'active', ownerId = null } = {}) {
  const query = { ownerId: requireOwnerId(ownerId) };
  if (status !== 'all') query.status = status;
  if (roomId) query.roomId = toObjectId(roomId, 'roomId');
  if (search && search.trim()) {
    const rx = { $regex: search.trim(), $options: 'i' };
    query.$or = [{ name: rx }, { mobile: rx }, { aadhaarNumber: rx }];
  }
  return Member.find(query).sort({ name: 1 }).limit(50).lean();
}

/** Member Details page: personal info, current period, rent history, payment history. */
async function memberDetail(id, ownerId) {
  const owner = requireOwnerId(ownerId);
  const member = await Member.findOne({ _id: toObjectId(id, 'memberId'), ownerId: owner }).lean();
  if (!member) throw new ValidationError([{ field: 'memberId', message: 'Member not found' }]);
  const room = await Room.findOne({ _id: member.roomId, ownerId: owner }).lean();
  const live = await Member.findOne({ _id: member._id, ownerId: owner });
  await rentService.ensurePeriodsForMember(live);

  const reference = today();
  // Only cycles that have begun: rent due today or already due. A cycle is
  // generated a month ahead, so a not-yet-started one is not money owed and
  // must not be sent as a future due at all.
  const periods = (
    await RentPeriod.find({ ownerId: owner, memberId: member._id })
      .sort({ startDate: -1 })
      .lean()
  ).filter((p) => startOfDay(p.startDate) <= reference);
  const current =
    periods.find((p) => startOfDay(p.startDate) <= reference && startOfDay(p.endDate) >= reference) ||
    periods.filter((p) => startOfDay(p.startDate) <= reference)[0] ||
    periods[0] ||
    null;
  const payments = await Payment.find({ ownerId: owner, memberId: member._id })
    .sort({ paymentDate: -1, createdAt: -1 })
    .populate('rentPeriodId', 'startDate endDate rentAmount status')
    .lean();
  const paymentsByPeriod = new Map();
  for (const p of payments) {
    const key = (p.rentPeriodId._id || p.rentPeriodId).toString();
    if (!paymentsByPeriod.has(key)) paymentsByPeriod.set(key, []);
    paymentsByPeriod.get(key).push(p);
  }
  // Every cycle left has begun, so split by whether it has ended:
  //   lapsed  - ended before today, unpaid carry-over
  //   running - covers today, this is the rent owed right now
  // Invariant: outstanding = due + overdue.
  const lapsed = periods.filter((p) => startOfDay(p.endDate) < reference);
  const running = periods.filter((p) => startOfDay(p.endDate) >= reference);
  const money = (list) =>
    Math.round(list.reduce((sum, p) => sum + (p.pendingAmount || 0), 0) * 100) / 100;

  const decorated = periods.map((p) => ({ ...p, started: true }));
  const paidTotal = Math.round(periods.reduce((sum, p) => sum + (p.paidAmount || 0), 0) * 100) / 100;
  const outstanding = money(periods);
  const round2 = (value) => Math.round((Number(value) || 0) * 100) / 100;

  return {
    member,
    room,
    periods: decorated,
    current,
    payments,
    paymentsByPeriod,
    // Everything owed on cycles that have begun: due + overdue.
    outstanding,
    // Rent billed for the member's whole stay (the original obligation).
    totalBilled: round2(periods.reduce((sum, p) => sum + (p.rentAmount || 0), 0)),
    // Cash actually collected from this member.
    totalCollected: paidTotal,
    // Debt written off by the landlord.
    waivedAmount: round2(periods.reduce((sum, p) => sum + (p.waivedAmount || 0), 0)),
    stillToCollect: outstanding,
    // Rent owed right now, on the cycle running today.
    due: money(running),
    // Unpaid rent from cycles that already ended, carried into today.
    overdue: money(lapsed),
    paidTotal,
  };
}

module.exports = {
  assertRoomHasSpace,
  createMember,
  memberDetail,
  searchMembers,
  updateMember,
  vacateMember,
  vacatedMembers,
  waiveMemberDebt,
};
