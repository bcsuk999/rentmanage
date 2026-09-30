'use strict';

const express = require('express');
const memberService = require('../services/memberService');
const Room = require('../models/Room');
const { requireRole } = require('../middleware/auth');
const { fieldErrors, firstErrorMessage, wrap } = require('../utils/http');
const { cycleEnd, formatDateRange, parseDateInput, toDateInput, today } = require('../utils/dates');
const { maskAadhaar } = require('../utils/mask');
const { parseAmount } = require('../utils/format');

const router = express.Router();

function cycleEndPreviewFor(rentStartDate) {
  const parsed = parseDateInput(rentStartDate);
  return parsed ? cycleEnd(parsed) : null;
}

/** Global member search: room ID, room number, name, mobile, Aadhaar. */
router.get(
  '/',
  wrap(async (req, res) => {
    const search = String(req.query.search || '').trim();
    const status = String(req.query.status || 'active');
    const roomId = String(req.query.roomId || '').trim();
    const members = await memberService.searchMembers({ search, roomId, status });
    const rooms = await Room.find().select('roomNumber').sort({ roomNumber: 1 }).lean();
    const roomMap = new Map(rooms.map((r) => [r._id.toString(), r.roomNumber]));
    res.render('members/index', {
      title: 'Members',
      members: members.map((m) => ({ ...m, roomNumber: roomMap.get(m.roomId.toString()) || '-' })),
      rooms,
      filters: { search, status, roomId },
      maskAadhaar,
    });
  })
);

router.get(
  '/:id',
  wrap(async (req, res) => {
    const detail = await memberService.memberDetail(req.params.id);
    res.render('members/detail', {
      title: detail.member.name,
      ...detail,
      currentRangeLabel: detail.current ? formatDateRange(detail.current.startDate, detail.current.endDate) : '-',
      maskAadhaar,
      today: toDateInput(today()),
      amountValue: (v) => (Number.isNaN(parseAmount(v)) ? '' : String(v)),
    });
  })
);

router.get(
  '/:id/edit',
  requireRole('admin'),
  wrap(async (req, res) => {
    const detail = await memberService.memberDetail(req.params.id);
    res.render('members/form', {
      title: `Edit ${detail.member.name}`,
      mode: 'edit',
      room: detail.room,
      member: {
        ...detail.member,
        aadhaarNumber: detail.member.aadhaarNumber || '',
        address: detail.member.address || '',
        emergencyContact: detail.member.emergencyContact || '',
        notes: detail.member.notes || '',
        rentStartDate: toDateInput(detail.member.rentStartDate),
      },
      errors: [],
      error: null,
      cycleEndPreview: cycleEndPreviewFor(detail.member.rentStartDate),
    });
  })
);

router.post(
  '/:id',
  requireRole('admin'),
  wrap(async (req, res) => {
    try {
      const member = await memberService.updateMember(req.params.id, req.body);
      req.flash('success', `${member.name} updated.`);
      return res.redirect(`/members/${member._id}`);
    } catch (err) {
      const detail = await memberService.memberDetail(req.params.id).catch(() => null);
      return res.status(err.status || 422).render('members/form', {
        title: 'Edit member',
        mode: 'edit',
        room: detail ? detail.room : null,
        member: { ...(detail ? detail.member : {}), ...req.body },
        errors: fieldErrors(err),
        error: firstErrorMessage(err),
        cycleEndPreview: cycleEndPreviewFor(req.body.rentStartDate),
      });
    }
  })
);

router.get(
  '/:id/vacate',
  requireRole('admin'),
  wrap(async (req, res) => {
    const detail = await memberService.memberDetail(req.params.id);
    const outstanding = detail.outstanding;
    res.render('members/vacate', {
      title: `Vacate ${detail.member.name}`,
      member: detail.member,
      room: detail.room,
      current: detail.current,
      outstanding,
      form: {
        vacatingDate: toDateInput(today()),
        finalPeriod: detail.current ? toDateInput(detail.current.endDate) : '',
        outstandingAmount: String(outstanding),
        notes: '',
      },
      errors: [],
      error: null,
    });
  })
);

router.post(
  '/:id/vacate',
  requireRole('admin'),
  wrap(async (req, res) => {
    try {
      const result = await memberService.vacateMember(req.params.id, req.body);
      req.flash(
        'success',
        `${result.member.name} marked vacated. History kept. Outstanding: ${result.outstanding}.`
      );
      return res.redirect(`/members/${result.member._id}`);
    } catch (err) {
      const detail = await memberService.memberDetail(req.params.id).catch(() => null);
      return res.status(err.status || 422).render('members/vacate', {
        title: 'Vacate member',
        member: detail ? detail.member : null,
        room: detail ? detail.room : null,
        current: detail ? detail.current : null,
        outstanding: detail ? detail.outstanding : 0,
        form: req.body,
        errors: fieldErrors(err),
        error: firstErrorMessage(err),
      });
    }
  })
);

module.exports = router;
