'use strict';

const express = require('express');
const memberService = require('../services/memberService');
const Room = require('../models/Room');
const { requireRole } = require('../middleware/auth');
const { sendApiError, wrap } = require('../utils/http');
const { cycleEnd, parseDateInput } = require('../utils/dates');

const router = express.Router();

/** Global member search. Query: ?search=&roomId=&status= (default active). */
router.get(
  '/',
  wrap(async (req, res) => {
    try {
      const search = String(req.query.search || '').trim();
      const status = String(req.query.status || 'active');
      const roomId = String(req.query.roomId || '').trim();
      const members = await memberService.searchMembers({ search, roomId, status });
      const rooms = await Room.find().select('roomNumber').sort({ roomNumber: 1 }).lean();
      const roomMap = new Map(rooms.map((r) => [r._id.toString(), r.roomNumber]));
      return res.json({
        members: members.map((m) => ({ ...m, roomNumber: roomMap.get(m.roomId.toString()) || '-' })),
        rooms,
      });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

router.get(
  '/:id',
  wrap(async (req, res) => {
    try {
      const detail = await memberService.memberDetail(req.params.id);
      return res.json({
        ...detail,
        paymentsByPeriod: Object.fromEntries(detail.paymentsByPeriod || new Map()),
      });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

router.patch(
  '/:id',
  requireRole('admin'),
  wrap(async (req, res) => {
    try {
      const member = await memberService.updateMember(req.params.id, req.body);
      return res.json({ member, message: `${member.name} updated.` });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** Preview the first rental cycle end for a rent start date. Query: ?rentStartDate= */
router.get(
  '/meta/cycle-preview',
  wrap(async (req, res) => {
    try {
      const parsed = parseDateInput(req.query.rentStartDate);
      return res.json({ cycleEnd: parsed ? cycleEnd(parsed) : null });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

router.post(
  '/:id/vacate',
  requireRole('admin'),
  wrap(async (req, res) => {
    try {
      const result = await memberService.vacateMember(req.params.id, req.body);
      return res.json({
        member: result.member,
        outstanding: result.outstanding,
        message: `${result.member.name} marked vacated. History kept. Outstanding: ${result.outstanding}.`,
      });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

module.exports = router;
