'use strict';

const express = require('express');
const roomService = require('../services/roomService');
const memberService = require('../services/memberService');
const { requireRole } = require('../middleware/auth');
const { sendApiError, wrap } = require('../utils/http');
const { parseDateInput, startOfDay } = require('../utils/dates');

const router = express.Router();

/** Room list with current-cycle totals. Query: ?search=&status=&paymentState= */
router.get(
  '/',
  wrap(async (req, res) => {
    try {
      const search = String(req.query.search || '').trim();
      const status = String(req.query.status || 'All');
      const paymentState = String(req.query.paymentState || 'All');
      const rooms = await roomService.listRoomsWithSummary({ search, status, paymentState });
      const round = (n) => Math.round(n * 100) / 100;
      return res.json({
        rooms,
        summary: {
          roomCount: rooms.length,
          memberCount: rooms.reduce((s, r) => s + r.memberCount, 0),
          totalRent: round(rooms.reduce((s, r) => s + r.totalRent, 0)),
          totalPaid: round(rooms.reduce((s, r) => s + r.totalPaid, 0)),
          totalPending: round(rooms.reduce((s, r) => s + r.totalPending, 0)),
        },
      });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

router.post(
  '/',
  requireRole('admin'),
  wrap(async (req, res) => {
    try {
      const room = await roomService.createRoom(req.body);
      return res.status(201).json({ room, message: `Room ${room.roomNumber} added.` });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** Room details with members for the selected rental period. Query: ?from=&to= */
router.get(
  '/:id',
  wrap(async (req, res) => {
    try {
      const from = parseDateInput(req.query.from);
      const to = parseDateInput(req.query.to);
      const selected = from && to && from <= to ? { start: startOfDay(from), end: startOfDay(to) } : null;
      const detail = await roomService.roomDetail(req.params.id, selected);
      return res.json(detail);
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
      const room = await roomService.updateRoom(req.params.id, req.body);
      return res.json({ room, message: `Room ${room.roomNumber} updated.` });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

router.delete(
  '/:id',
  requireRole('admin'),
  wrap(async (req, res) => {
    try {
      const room = await roomService.deleteRoom(req.params.id);
      return res.json({ ok: true, message: `Room ${room.roomNumber} deleted.` });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** Add a member from inside a room. */
router.post(
  '/:id/members',
  requireRole('admin'),
  wrap(async (req, res) => {
    try {
      const member = await memberService.createMember({ ...req.body, roomId: req.params.id });
      return res.status(201).json({ member, message: `${member.name} added.` });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

module.exports = router;
