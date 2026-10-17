'use strict';

const express = require('express');
const roomService = require('../services/roomService');
const memberService = require('../services/memberService');
const { sendApiError, wrap } = require('../utils/http');
const { parseDateInput, startOfDay } = require('../utils/dates');

const router = express.Router();

router.post(
  '/',
  wrap(async (req, res) => {
    try {
      const room = await roomService.createRoom(req.body, req.user._id);
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
      const detail = await roomService.roomDetail(req.params.id, selected, req.user._id);
      return res.json(detail);
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

router.patch(
  '/:id',
  wrap(async (req, res) => {
    try {
      const room = await roomService.updateRoom(req.params.id, req.body, req.user._id);
      return res.json({ room, message: `Room ${room.roomNumber} updated.` });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

router.delete(
  '/:id',
  wrap(async (req, res) => {
    try {
      const room = await roomService.deleteRoom(req.params.id, req.user._id);
      return res.json({ ok: true, message: `Room ${room.roomNumber} deleted.` });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** Add a member from inside a room. */
router.post(
  '/:id/members',
  wrap(async (req, res) => {
    try {
      const member = await memberService.createMember({ ...req.body, roomId: req.params.id }, req.user._id);
      return res.status(201).json({ member, message: `${member.name} added.` });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

module.exports = router;
