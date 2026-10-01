'use strict';

const Member = require('../models/Member');
const Room = require('../models/Room');
const RentPeriod = require('../models/RentPeriod');
const Payment = require('../models/Payment');
const rentService = require('./rentService');
const { toObjectId } = require('./roomService');
const { startOfDay, today } = require('../utils/dates');
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

async function assertRoom(roomId) {
  const room = await Room.findById(toObjectId(roomId, 'roomId'));
  if (!room) throw new ValidationError([{ field: 'roomId', message: 'Room not found' }]);
  return room;
}

/** A room cannot hold more active members than its capacity. */
async function assertRoomHasSpace(room, field = 'roomId') {
  const capacity = Number(room.capacity);
  if (!Number.isFinite(capacity) || capacity < 1) return;
  const activeMembers = await Member.countDocuments({ roomId: room._id, status: 'active' });
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
async function createMember(body) {
  const room = await assertRoom(body.roomId);
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

async function updateMember(id, body) {
  const member = await Member.findById(toObjectId(id, 'memberId'));
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
    const untouched = await RentPeriod.find({ memberId: member._id, paidAmount: { $gt: 0 } })
      .select('startDate endDate')
      .lean();
    await RentPeriod.deleteMany({ memberId: member._id, paidAmount: 0 });
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
async function vacateMember(id, body) {
  const member = await Member.findById(toObjectId(id, 'memberId'));
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
    memberId: member._id,
    startDate: { $gt: vacatingDate },
  }).select('_id paidAmount');
  const deletable = future.filter((p) => p.paidAmount === 0).map((p) => p._id);
  if (deletable.length) await RentPeriod.deleteMany({ _id: { $in: deletable } });

  const remaining = await RentPeriod.find({ memberId: member._id }).select('_id');
  for (const period of remaining) await rentService.recalcPeriod(period._id);

  const outstanding = await RentPeriod.aggregate([
    { $match: { memberId: member._id } },
    { $group: { _id: null, pending: { $sum: '$pendingAmount' } } },
  ]);

  return {
    member,
    finalPeriod: finalPeriod || null,
    outstanding: outstanding.length ? Math.round(outstanding[0].pending * 100) / 100 : 0,
  };
}

/** Search / filter members (used by search and the payments filters). */
async function searchMembers({ search = '', roomId = null, status = 'active' } = {}) {
  const query = {};
  if (status !== 'all') query.status = status;
  if (roomId) query.roomId = toObjectId(roomId, 'roomId');
  if (search && search.trim()) {
    const rx = { $regex: search.trim(), $options: 'i' };
    query.$or = [{ name: rx }, { mobile: rx }, { aadhaarNumber: rx }];
  }
  return Member.find(query).sort({ name: 1 }).limit(50).lean();
}

/** Member Details page: personal info, current period, rent history, payment history. */
async function memberDetail(id) {
  const member = await Member.findById(toObjectId(id, 'memberId')).lean();
  if (!member) throw new ValidationError([{ field: 'memberId', message: 'Member not found' }]);
  const room = await Room.findById(member.roomId).lean();
  const live = await Member.findById(member._id);
  await rentService.ensurePeriodsForMember(live);

  const periods = await RentPeriod.find({ memberId: member._id })
    .sort({ startDate: -1 })
    .lean();
  const reference = today();
  const current =
    periods.find((p) => startOfDay(p.startDate) <= reference && startOfDay(p.endDate) >= reference) ||
    periods.filter((p) => startOfDay(p.startDate) <= reference)[0] ||
    periods[0] ||
    null;
  const payments = await Payment.find({ memberId: member._id })
    .sort({ paymentDate: -1, createdAt: -1 })
    .populate('rentPeriodId', 'startDate endDate rentAmount status')
    .lean();
  const paymentsByPeriod = new Map();
  for (const p of payments) {
    const key = (p.rentPeriodId._id || p.rentPeriodId).toString();
    if (!paymentsByPeriod.has(key)) paymentsByPeriod.set(key, []);
    paymentsByPeriod.get(key).push(p);
  }
  // Due = only periods that have started (startDate <= today).
  // Future advance cycles (e.g. 1 Nov created while today is 1 Oct) must not
  // inflate the due/outstanding total.
  const duePeriods = periods.filter((p) => startOfDay(p.startDate) <= reference);
  const outstanding = duePeriods.reduce((sum, p) => sum + (p.pendingAmount || 0), 0);
  const paidTotal = periods.reduce((sum, p) => sum + (p.paidAmount || 0), 0);
  const futurePending = Math.round(
    periods
      .filter((p) => startOfDay(p.startDate) > reference)
      .reduce((sum, p) => sum + (p.pendingAmount || 0), 0) * 100
  ) / 100;

  return {
    member,
    room,
    periods,
    current,
    payments,
    paymentsByPeriod,
    outstanding: Math.round(outstanding * 100) / 100,
    paidTotal: Math.round(paidTotal * 100) / 100,
    futurePending,
  };
}

module.exports = {
  assertRoomHasSpace,
  createMember,
  memberDetail,
  searchMembers,
  updateMember,
  vacateMember,
};
