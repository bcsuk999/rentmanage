'use strict';

const express = require('express');
const roomService = require('../services/roomService');
const memberService = require('../services/memberService');
const { ROOM_STATUSES } = require('../models/Room');
const { fieldErrors, firstErrorMessage, wrap } = require('../utils/http');
const {
  cycleEnd,
  formatDateRange,
  parseDateInput,
  startOfDay,
  toDateInput,
  today,
} = require('../utils/dates');
const { maskAadhaar } = require('../utils/mask');

const router = express.Router();

/** Preview of the first rental cycle for the form (null when the date is not valid yet). */
function cycleEndPreviewFor(rentStartDate) {
  const parsed = parseDateInput(rentStartDate);
  return parsed ? cycleEnd(parsed) : null;
}

/** Room list / dashboard: every room with its current-cycle totals. */
router.get(
  '/',
  wrap(async (req, res) => {
    const search = String(req.query.search || '').trim();
    const status = String(req.query.status || 'All');
    const paymentState = String(req.query.paymentState || 'All');
    const rooms = await roomService.listRoomsWithSummary({ search, status, paymentState });
    const round = (n) => Math.round(n * 100) / 100;
    res.render('rooms/index', {
      title: 'Rooms',
      rooms,
      grand: {
        roomCount: rooms.length,
        memberCount: rooms.reduce((s, r) => s + r.memberCount, 0),
        totalRent: round(rooms.reduce((s, r) => s + r.totalRent, 0)),
        totalPaid: round(rooms.reduce((s, r) => s + r.totalPaid, 0)),
        totalPending: round(rooms.reduce((s, r) => s + r.totalPending, 0)),
      },
      filters: { search, status, paymentState },
      statuses: ['All', ...ROOM_STATUSES],
      paymentStates: ['All', ...roomService.PAYMENT_FILTERS],
    });
  })
);

router.get('/new', (req, res) => {
  res.render('rooms/form', {
    title: 'Add room',
    mode: 'create',
    room: { roomNumber: '', status: 'Empty', notes: '' },
    statuses: ROOM_STATUSES,
    errors: [],
  });
});

router.post(
  '/',
  wrap(async (req, res) => {
    try {
      const room = await roomService.createRoom(req.body);
      req.flash('success', `Room ${room.roomNumber} added.`);
      return res.redirect(`/rooms/${room._id}`);
    } catch (err) {
      return res.status(err.status || 422).render('rooms/form', {
        title: 'Add room',
        mode: 'create',
        room: req.body,
        statuses: ROOM_STATUSES,
        errors: fieldErrors(err),
        error: firstErrorMessage(err),
      });
    }
  })
);

/** Room details with a selectable rental period. */
router.get(
  '/:id',
  wrap(async (req, res) => {
    const from = parseDateInput(req.query.from);
    const to = parseDateInput(req.query.to);
    const selected = from && to && from <= to ? { start: startOfDay(from), end: startOfDay(to) } : null;
    const detail = await roomService.roomDetail(req.params.id, selected);
    res.render('rooms/detail', {
      title: `Room ${detail.room.roomNumber}`,
      room: detail.room,
      members: detail.members,
      summary: detail.summary,
      ranges: detail.ranges,
      range: detail.range,
      historical: detail.historical,
      rangeLabel: detail.range ? formatDateRange(detail.range.start, detail.range.end) : 'No period yet',
      today: toDateInput(today()),
      maskAadhaar,
    });
  })
);

router.get(
  '/:id/edit',
  wrap(async (req, res) => {
    const { room } = await roomService.roomDetail(req.params.id, null);
    res.render('rooms/form', {
      title: `Edit Room ${room.roomNumber}`,
      mode: 'edit',
      room: { ...room, notes: room.notes || '' },
      statuses: ROOM_STATUSES,
      errors: [],
    });
  })
);

router.post(
  '/:id',
  wrap(async (req, res) => {
    try {
      const room = await roomService.updateRoom(req.params.id, req.body);
      req.flash('success', `Room ${room.roomNumber} updated.`);
      return res.redirect(`/rooms/${room._id}`);
    } catch (err) {
      const { room } = await roomService.roomDetail(req.params.id, null).catch(() => ({ room: null }));
      return res.status(err.status || 422).render('rooms/form', {
        title: 'Edit room',
        mode: 'edit',
        room: { ...(room || {}), ...req.body },
        statuses: ROOM_STATUSES,
        errors: fieldErrors(err),
        error: firstErrorMessage(err),
      });
    }
  })
);

router.post(
  '/:id/delete',
  wrap(async (req, res) => {
    try {
      const room = await roomService.deleteRoom(req.params.id);
      req.flash('success', `Room ${room.roomNumber} deleted.`);
    } catch (err) {
      req.flash('error', firstErrorMessage(err));
    }
    return res.redirect('/rooms');
  })
);

/** Add a member from inside a room. */
router.get(
  '/:id/members/new',
  wrap(async (req, res) => {
    const { room } = await roomService.roomDetail(req.params.id, null);
    res.render('members/form', {
      title: `Add member to Room ${room.roomNumber}`,
      mode: 'create',
      room,
      member: {
        name: '',
        mobile: '',
        aadhaarNumber: '',
        monthlyRent: '',
        rentStartDate: toDateInput(today()),
        address: '',
        emergencyContact: '',
        notes: '',
      },
      errors: [],
      error: null,
      cycleEndPreview: cycleEndPreviewFor(toDateInput(today())),
    });
  })
);

router.post(
  '/:id/members',
  wrap(async (req, res) => {
    try {
      const member = await memberService.createMember({ ...req.body, roomId: req.params.id });
      req.flash('success', `${member.name} added. Rent cycle starts on their rent start date.`);
      return res.redirect(`/rooms/${req.params.id}`);
    } catch (err) {
      const { room } = await roomService.roomDetail(req.params.id, null).catch(() => ({ room: null }));
      return res.status(err.status || 422).render('members/form', {
        title: 'Add member',
        mode: 'create',
        room,
        member: req.body,
        errors: fieldErrors(err),
        error: firstErrorMessage(err),
        cycleEndPreview: cycleEndPreviewFor(req.body.rentStartDate),
      });
    }
  })
);

module.exports = router;
