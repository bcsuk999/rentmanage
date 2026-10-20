'use strict';

const Room = require('../models/Room');
const Member = require('../models/Member');
const RentPeriod = require('../models/RentPeriod');
const Payment = require('../models/Payment');
const { ROOM_STATUSES } = require('../models/Room');
const { ensurePeriodsForActiveMembers, selectPeriodsByMember, summarise } = require('./rentService');
const { MONTHS, addDays, parseDateInput, startOfDay, toDateInput, today } = require('../utils/dates');
const { requireOwnerId } = require('../utils/owner');
const { ValidationError } = require('../utils/validate');

const PAYMENT_FILTERS = ['Fully Paid', 'Partial', 'Pending', 'Overdue'];

// Search results are capped so a one-character term cannot return the entire
// portfolio. The caller gets `truncated: true` and can ask for more.
const DEFAULT_SEARCH_LIMIT = 50;
const MAX_SEARCH_LIMIT = 200;

const round2 = (n) => Math.round(n * 100) / 100;
const sum = (list, pick) => round2(list.reduce((total, item) => total + (pick(item) || 0), 0));

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

function groupByRoom(members) {
  const map = new Map();
  for (const m of members) {
    const key = m.roomId.toString();
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(m);
  }
  return map;
}

function groupByMember(periods) {
  const map = new Map();
  for (const p of periods) {
    const key = p.memberId.toString();
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(p);
  }
  return map;
}

/** The calendar month containing `reference`, as a { from, to } UTC range. */
function monthRange(reference) {
  const ref = startOfDay(reference);
  return {
    from: new Date(Date.UTC(ref.getUTCFullYear(), ref.getUTCMonth(), 1)),
    to: addDays(new Date(Date.UTC(ref.getUTCFullYear(), ref.getUTCMonth() + 1, 1)), -1),
  };
}

/**
 * Both dates or neither: the summary always describes one closed period, so a
 * half-supplied range is a caller mistake rather than something to guess at.
 * With neither, the current calendar month is reported.
 */
function resolveRange(from, to) {
  const fromInput = String(from || '').trim();
  const toInput = String(to || '').trim();
  if (!fromInput && !toInput) return monthRange(today());
  if (!fromInput || !toInput) {
    throw new ValidationError([
      { field: fromInput ? 'to' : 'from', message: 'Send both from and to (YYYY-MM-DD)' },
    ]);
  }
  const parsedFrom = parseDateInput(fromInput);
  const parsedTo = parseDateInput(toInput);
  if (!parsedFrom || !parsedTo) {
    throw new ValidationError([
      { field: 'to', message: 'Give a valid from and to date (YYYY-MM-DD)' },
    ]);
  }
  if (parsedFrom > parsedTo) {
    throw new ValidationError([
      { field: 'to', message: 'to must be on or after from' },
    ]);
  }
  return { from: startOfDay(parsedFrom), to: startOfDay(parsedTo) };
}

/**
 * Unpaid rent carried over from cycles that have already ended, or null when
 * the member owes nothing overdue. Shared by the room cards and search results.
 */
function buildOverdue(lapsed) {
  if (!lapsed || !lapsed.length) return null;
  return {
    period: overduePeriodLabel(lapsed),
    amt: sum(lapsed, (p) => p.pendingAmount),
  };
}

/**
 * Which field a room matched on, or null. Room numbers are matched as a prefix
 * because they are short and typed from the start ('1' should find 101, 102,
 * 105), so free-text substring matching would swamp them with 110-119.
 */
function matchesRoom(room, term) {
  if (String(room.roomNumber).toLowerCase().startsWith(term)) return 'roomNumber';
  if (room.notes && String(room.notes).toLowerCase().includes(term)) return 'notes';
  return null;
}

/**
 * Which field a member matched on, or null. Mobile is matched as a substring so
 * a partial number still finds the member.
 */
function matchesMember(member, term) {
  if (String(member.name).toLowerCase().includes(term)) return 'name';
  if (String(member.mobile).includes(term)) return 'mobile';
  if (member.aadhaarNumber && String(member.aadhaarNumber).includes(term)) return 'aadhaarNumber';
  return null;
}

/**
 * One member row for the current cycle, with the member's own details alongside
 * the rent snapshot. [lapsed] is every unpaid cycle that has already ended, so
 * the badge reports real carry-over rather than this month's remainder.
 */
function memberRow(member, period, lapsed) {
  return {
    id: member._id,
    name: member.name,
    mobile: member.mobile,
    aadhaarNumber: member.aadhaarNumber || '',
    monthlyRent: member.monthlyRent || 0,
    rentStartDate: member.rentStartDate || null,
    joiningDate: member.joiningDate || null,
    // A member with no cycle running today owes nothing right now, so the rent
    // figures stay at zero instead of pretending the monthly rent is unpaid.
    rent: period ? period.rentAmount : 0,
    paid: period ? period.paidAmount : 0,
    pending: period ? period.pendingAmount : 0,
    status: period ? period.status : 'No period',
    dueDate: period ? period.endDate : null,
    overdue: buildOverdue(lapsed),
  };
}

/**
 * Every room with its members, always on the cycle running today. There is no
 * date filter and no text filter here by design: this is the live "who owes
 * what" view. Historical figures come from summary(), and finding anything by
 * name/number comes from search().
 *
 * Query: status (room status), paymentState (Fully Paid/Partial/Pending/Overdue).
 */
async function listRooms({ status = 'All', paymentState = 'All', ownerId = null } = {}) {
  const owner = requireOwnerId(ownerId);
  const reference = today();
  await ensurePeriodsForActiveMembers({ reference, ownerId: owner });

  const rooms = await Room.find({ ownerId: owner }).sort({ roomNumber: 1 }).lean();
  const roomIds = rooms.map((r) => r._id);

  const [members, periods, lapsedPeriods] = await Promise.all([
    roomIds.length
      ? Member.find({ ownerId: owner, roomId: { $in: roomIds }, status: 'active' })
        .select('roomId name mobile aadhaarNumber monthlyRent rentStartDate joiningDate')
        .sort({ name: 1 })
        .lean()
      : [],
    roomIds.length
      ? RentPeriod.find({
        ownerId: owner,
        roomId: { $in: roomIds },
        startDate: { $lte: reference },
        endDate: { $gte: reference },
      })
        .sort({ startDate: 1 })
        .select('memberId roomId startDate endDate rentAmount paidAmount pendingAmount status')
        .lean()
      : [],
    // Lapsed cycles need their own query: a member several months behind has no
    // cycle containing today, so the current-cycle query never returns it.
    // Keyed off endDate + pending rather than the stored status, which is a
    // cached flag that can lag behind an unrecorded payment.
    roomIds.length
      ? RentPeriod.find({
        ownerId: owner,
        roomId: { $in: roomIds },
        endDate: { $lt: reference },
        pendingAmount: { $gt: 0 },
      })
        .sort({ startDate: 1 })
        .select('memberId startDate endDate pendingAmount')
        .lean()
      : [],
  ]);

  const membersByRoom = groupByRoom(members);
  const periodsByMember = selectPeriodsByMember(periods, reference);
  const lapsedByMember = groupByMember(lapsedPeriods);

  const allRows = rooms.map((room) => {
    const roomMembers = membersByRoom.get(room._id.toString()) || [];
    // One cycle per member. Summing every overlapping cycle would double-count,
    // but here the query already pins each member to the cycle covering today.
    const roomPeriods = roomMembers
      .map((m) => periodsByMember.get(m._id.toString()))
      .filter(Boolean);
    const rollup = summarise(
      roomPeriods.map((p) => ({
        rent: p.rentAmount,
        paid: p.paidAmount,
        pending: p.pendingAmount,
        status: p.status,
      }))
    );
    const capacity = room.capacity || roomMembers.length;
    return {
      ...publicRoom(room),
      memberCount: roomMembers.length,
      capacity,
      isFull: roomMembers.length >= capacity,
      totalRent: rollup.totalRent,
      totalPaid: rollup.totalPaid,
      totalPending: rollup.totalPending,
      paymentState: rollup.paymentState,
      members: roomMembers.map((m) => memberRow(
        m,
        periodsByMember.get(m._id.toString()),
        lapsedByMember.get(m._id.toString())
      )),
    };
  });

  let rows = allRows;
  if (status !== 'All' && ROOM_STATUSES.includes(status)) {
    rows = rows.filter((r) => r.status === status);
  }
  if (paymentState !== 'All' && PAYMENT_FILTERS.includes(paymentState)) {
    rows = rows.filter((r) => r.paymentState === paymentState);
  }
  return rows;
}

/**
 * Portfolio totals up to today ("till date"). This is what the home dashboard
 * asks for now that it has no month picker:
 *
 *   totalRent  - rent billed on every cycle that has started, all time
 *   collected  - rent paid on those cycles, all time
 *   due        - unpaid on the cycles still running today
 *   overdue    - unpaid on cycles that have already ended
 *
 * Invariant: totalRent = collected + due + overdue. `notYetDue` is 0 by
 * definition here, because cycles that start after today are not billed yet.
 */
async function tillDateSummary({ owner }) {
  const now = startOfDay(today());
  await ensurePeriodsForActiveMembers({ reference: now, ownerId: owner });

  const rooms = await Room.find({ ownerId: owner }).select('roomNumber status').lean();
  const roomIds = rooms.map((r) => r._id);

  const [members, periods, payments] = await Promise.all([
    roomIds.length
      ? Member.find({ ownerId: owner, roomId: { $in: roomIds }, status: 'active' })
        .select('roomId')
        .lean()
      : [],
    // Every cycle that has started. A cycle cannot be billed before it begins.
    roomIds.length
      ? RentPeriod.find({ ownerId: owner, roomId: { $in: roomIds }, startDate: { $lte: now } })
        .select('startDate endDate rentAmount paidAmount pendingAmount')
        .lean()
      : [],
    // Cash actually received, which is not the same as rent collected when one
    // payment settles several cycles.
    roomIds.length
      ? Payment.find({ ownerId: owner, roomId: { $in: roomIds }, paymentDate: { $lte: now } })
        .select('amount')
        .lean()
      : [],
  ]);

  const ended = periods.filter((p) => startOfDay(p.endDate) < now);
  const running = periods.filter((p) => startOfDay(p.endDate) >= now);
  const earliest = periods.reduce(
    (min, p) => (!min || p.startDate < min ? p.startDate : min),
    null
  );

  return {
    from: toDateInput(earliest || now),
    to: toDateInput(now),
    totalRent: sum(periods, (p) => p.rentAmount),
    collected: sum(periods, (p) => p.paidAmount),
    due: sum(running, (p) => p.pendingAmount),
    overdue: sum(ended.filter((p) => p.pendingAmount > 0), (p) => p.pendingAmount),
    expense: 0,
    totalRooms: rooms.length,
    totalMembers: members.length,
    notYetDue: 0,
    receivedInRange: sum(payments, (p) => p.amount),
    paymentCount: payments.length,
  };
}

/**
 * Portfolio totals. With from/to it describes that period; with neither it is a
 * running total up to today, which is the dashboard default.
 *
 * Rent figures are read from one cycle per member - the one running on the
 * period being reported - so a member whose cycle straddles the month boundary
 * is counted once, not twice.
 *
 * Outstanding money is split by whether the cycle has started:
 *   due        - unpaid on a cycle that has already begun, i.e. rent owed now
 *   notYetDue  - unpaid on a cycle that has not begun yet, i.e. next month's
 *                rent. Never counted as due, so a 12 Nov cycle cannot surface
 *                as due in the October view.
 *   overdue    - unpaid on cycles that have already ended, the carry-over from
 *                previous months. It sits outside this period's rent by design.
 *
 * Invariant: totalRent = collected + due + notYetDue.
 */
async function summary({ from = null, to = null, ownerId = null } = {}) {
  const owner = requireOwnerId(ownerId);
  // No range at all means "everything up to today"; a half range is still a
  // caller mistake and resolveRange() rejects it.
  if (!String(from || '').trim() && !String(to || '').trim()) {
    return tillDateSummary({ owner });
  }
  const range = resolveRange(from, to);
  const now = today();
  await ensurePeriodsForActiveMembers({ reference: range.to, ownerId: owner });

  const rooms = await Room.find({ ownerId: owner }).select('roomNumber status').sort({ roomNumber: 1 }).lean();
  const roomIds = rooms.map((r) => r._id);

  const [members, overlapping, lapsedPeriods, paymentsInRange] = await Promise.all([
    roomIds.length
      ? Member.find({ ownerId: owner, roomId: { $in: roomIds }, status: 'active' }).select('roomId').lean()
      : [],
    roomIds.length
      ? RentPeriod.find({
        ownerId: owner,
        roomId: { $in: roomIds },
        startDate: { $lte: range.to },
        endDate: { $gte: range.from },
      })
        .sort({ startDate: 1 })
        .select('memberId roomId startDate endDate rentAmount paidAmount pendingAmount status')
        .lean()
      : [],
    // Overdue is a carry-over balance, so it is measured against today rather
    // than the reported period: looking back at September must not erase rent
    // that is still unpaid today.
    roomIds.length
      ? RentPeriod.find({
        ownerId: owner,
        roomId: { $in: roomIds },
        endDate: { $lt: now },
        pendingAmount: { $gt: 0 },
      })
        .select('roomId pendingAmount')
        .lean()
      : [],
    roomIds.length
      ? Payment.find({
        ownerId: owner,
        roomId: { $in: roomIds },
        paymentDate: { $gte: range.from, $lte: range.to },
      })
        .select('amount')
        .lean()
      : [],
  ]);

  // While the reported period covers today, report the cycle running today so a
  // freshly started cycle shows up immediately; otherwise report the cycle
  // active at the end of the period.
  const inRange = startOfDay(now) >= range.from && startOfDay(now) <= range.to;
  const cycles = [...selectPeriodsByMember(overlapping, inRange ? now : range.to).values()];

  const started = cycles.filter((p) => startOfDay(p.startDate) <= now);
  const notStarted = cycles.filter((p) => startOfDay(p.startDate) > now);

  return {
    from: toDateInput(range.from),
    to: toDateInput(range.to),
    totalRent: sum(cycles, (p) => p.rentAmount),
    collected: sum(cycles, (p) => p.paidAmount),
    due: sum(started, (p) => p.pendingAmount),
    overdue: sum(lapsedPeriods, (p) => p.pendingAmount),
    // There is no expense model in this project yet, so there is nothing to
    // total. Kept in the response so the dashboard has a real field to grow
    // into instead of a hard-coded zero in the UI.
    expense: 0,
    totalRooms: rooms.length,
    totalMembers: members.length,
    // Reported alongside due so totalRent always reconciles: a future cycle's
    // rent is shown, just never as something the landlord is owed today.
    notYetDue: sum(notStarted, (p) => p.pendingAmount),
    // Cash view of the period: what actually came in, which is not the same as
    // `collected` when someone pays an old cycle during this month.
    receivedInRange: sum(paymentsInRange, (p) => p.amount),
    paymentCount: paymentsInRange.length,
  };
}

const MEMBER_FIELDS =
  'roomId name mobile aadhaarNumber monthlyRent rentStartDate joiningDate vacatingDate status';

/**
 * Search rooms and members by one free-text term, with no period: every hit
 * carries whatever is current today.
 *
 * Matching rules (the same ones the room list's `search` param uses):
 *   room    - room number as a prefix, or the notes text
 *   member  - name, mobile or aadhaar, each as a substring
 *
 * Vacated members are searchable too, flagged with status 'inactive' and their
 * vacating date, so an old tenant can still be looked up by number.
 *
 * Results are one flat list, rooms first then members, each tagged with `type`
 * and `matchedOn` so the caller can render one hit list and label the hits.
 */
async function search({
  search: searchTerm = '',
  q = '',
  limit = DEFAULT_SEARCH_LIMIT,
  ownerId = null,
} = {}) {
  const owner = requireOwnerId(ownerId);
  const raw = String(searchTerm || q || '').trim();
  const term = raw.toLowerCase();
  const max = Math.min(Math.max(Number(limit) || DEFAULT_SEARCH_LIMIT, 1), MAX_SEARCH_LIMIT);

  // An empty box is not a client error, it just has nothing to show yet.
  if (!term) return { query: raw, results: [], roomCount: 0, memberCount: 0, truncated: false };

  const reference = today();
  await ensurePeriodsForActiveMembers({ reference, ownerId: owner });

  const rooms = await Room.find({ ownerId: owner }).sort({ roomNumber: 1 }).lean();
  const roomIds = rooms.map((r) => r._id);

  const matchedRooms = [];
  for (const room of rooms) {
    const matchedOn = matchesRoom(room, term);
    if (matchedOn) matchedRooms.push({ room, matchedOn });
  }

  // Deliberately not filtered on status: vacated members stay findable.
  const members = roomIds.length
    ? await Member.find({ ownerId: owner, roomId: { $in: roomIds } })
      .select(MEMBER_FIELDS)
      .sort({ name: 1 })
      .lean()
    : [];

  const matchedMembers = [];
  for (const member of members) {
    const matchedOn = matchesMember(member, term);
    if (matchedOn) matchedMembers.push({ member, matchedOn });
  }

  // Only the hits need their rent history, so this stays small even on a large
  // portfolio where the search itself matched a lot.
  const hitIds = matchedMembers.map((m) => m.member._id);
  const periods = hitIds.length
    ? await RentPeriod.find({ ownerId: owner, memberId: { $in: hitIds } })
      .sort({ startDate: 1 })
      .select('memberId startDate endDate rentAmount paidAmount pendingAmount status')
      .lean()
    : [];
  const periodsByMember = groupByMember(periods);
  const roomsById = new Map(rooms.map((r) => [r._id.toString(), r]));

  const memberHits = matchedMembers.map(({ member, matchedOn }) => {
    const own = periodsByMember.get(member._id.toString()) || [];
    // An active member is shown on the cycle running today. A vacated member has
    // none, so fall back to the last cycle that actually started.
    const current = member.status === 'active'
      ? own.find(
        (p) => startOfDay(p.startDate) <= reference && startOfDay(p.endDate) >= reference
      ) || null
      : own.filter((p) => startOfDay(p.endDate) <= reference).slice(-1)[0] || null;
    const room = roomsById.get(member.roomId.toString());
    return {
      type: 'member',
      id: member._id,
      name: member.name,
      mobile: member.mobile,
      aadhaarNumber: member.aadhaarNumber || '',
      monthlyRent: member.monthlyRent || 0,
      rentStartDate: member.rentStartDate || null,
      joiningDate: member.joiningDate || null,
      // 'active' or 'inactive'. An inactive hit still carries their room so the
      // caller can say where they used to live.
      status: member.status,
      ...(member.vacatingDate ? { vacatingDate: member.vacatingDate } : {}),
      room: room
        ? { _id: room._id, roomNumber: room.roomNumber, status: room.status }
        : null,
      currentCycle: current
        ? {
          rent: current.rentAmount,
          paid: current.paidAmount,
          pending: current.pendingAmount,
          status: current.status,
          startDate: current.startDate,
          dueDate: current.endDate,
        }
        : null,
      overdue: buildOverdue(
        own.filter((p) => startOfDay(p.endDate) < reference && (p.pendingAmount || 0) > 0)
      ),
      matchedOn,
    };
  });

  const roomHits = matchedRooms.map(({ room, matchedOn }) => {
    const roomMembers = members.filter((m) => m.roomId.toString() === room._id.toString());
    return {
      type: 'room',
      _id: room._id,
      roomNumber: room.roomNumber,
      capacity: room.capacity,
      status: room.status,
      ...(room.notes ? { notes: room.notes } : {}),
      memberCount: roomMembers.length,
      // Enough to recognise who is in there without paying for the full rent
      // snapshot of every member in the portfolio.
      members: roomMembers.map((m) => ({
        id: m._id,
        name: m.name,
        mobile: m.mobile,
        status: m.status,
      })),
      matchedOn,
    };
  });

  return {
    query: raw,
    // Rooms first, then members, both already in natural order.
    results: [...roomHits.slice(0, max), ...memberHits.slice(0, max)],
    roomCount: roomHits.length,
    memberCount: memberHits.length,
    // True when hits were dropped, so the caller can offer to widen the search.
    truncated: roomHits.length > max || memberHits.length > max,
  };
}

module.exports = {
  PAYMENT_FILTERS,
  listRooms,
  search,
  summary,
};