'use strict';

const express = require('express');
const dashboardService = require('../services/dashboardService');
const { sendApiError, wrap } = require('../utils/http');

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

module.exports = router;