'use strict';

const express = require('express');
const dashboardService = require('../services/dashboardService');
const roomService = require('../services/roomService');
const memberService = require('../services/memberService');
const { sendApiError, wrap } = require('../utils/http');
const { parseDateInput, startOfDay } = require('../utils/dates');

const router = express.Router();

/** Every room with its members, on the rent cycle running today.
 *  Query: ?status=&paymentState= - there is no text filter here, searching is
 *  a separate call to /search. */
router.get(
  '/rooms',
  wrap(async (req, res) => {
    try {
      const rooms = await dashboardService.listRooms({
        status: String(req.query.status || 'All'),
        paymentState: String(req.query.paymentState || 'All'),
        ownerId: req.user._id,
      });
      return res.json({ rooms });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** Search rooms and members by one term, no period. Query: ?search= (or ?q=),
 *  optional ?limit=. Every hit carries whatever is current today. */
router.get(
  '/search',
  wrap(async (req, res) => {
    try {
      return res.json(await dashboardService.search({
        search: req.query.search,
        q: req.query.q,
        limit: req.query.limit,
        ownerId: req.user._id,
      }));
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** Portfolio totals for one period. Query: ?from=&to= (YYYY-MM-DD), both or
 *  neither, defaulting to the current calendar month. */
router.get(
  '/summary',
  wrap(async (req, res) => {
    try {
      return res.json(await dashboardService.summary({
        from: req.query.from,
        to: req.query.to,
        ownerId: req.user._id,
      }));
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** One room in full: its members on the selected cycle, the member rows with
 *  their period, the cycle ranges available, and any vacated members.
 *  Query: ?from=&to= (YYYY-MM-DD) to view a month other than the current one;
 *  an absent or unusable range falls back to the cycle running today. */
router.get(
  '/room/:id',
  wrap(async (req, res) => {
    try {
      const from = parseDateInput(req.query.from);
      const to = parseDateInput(req.query.to);
      const selected = from && to && from <= to ? { start: startOfDay(from), end: startOfDay(to) } : null;
      return res.json(await roomService.roomDetail(req.params.id, selected, req.user._id));
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

/** One member in full: their details, every rent cycle, the current one, all
 *  payments, and the outstanding / paid / future split. */
router.get(
  '/member/:id',
  wrap(async (req, res) => {
    try {
      const detail = await memberService.memberDetail(req.params.id, req.user._id);
      return res.json({
        ...detail,
        // The service groups payments in a Map; JSON needs an object keyed by
        // rent period id.
        paymentsByPeriod: Object.fromEntries(detail.paymentsByPeriod || new Map()),
      });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

module.exports = router;