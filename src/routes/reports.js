'use strict';

const express = require('express');
const reportService = require('../services/reportService');
const Room = require('../models/Room');
const { sendApiError, wrap } = require('../utils/http');
const { parseDateInput, toDateInput } = require('../utils/dates');
const { ValidationError } = require('../utils/validate');

const router = express.Router();

/** Report for an explicit date range. Query: ?from=&to=&roomId= */
router.get(
  '/',
  wrap(async (req, res) => {
    try {
      const rooms = await Room.find().select('roomNumber status').sort({ roomNumber: 1 }).lean();
      const roomId = String(req.query.roomId || '').trim();
      const fromInput = String(req.query.from || '').trim();
      const toInput = String(req.query.to || '').trim();

      let range;
      if (fromInput && toInput) {
        const from = parseDateInput(fromInput);
        const to = parseDateInput(toInput);
        if (!from || !to) {
          throw new ValidationError([{ field: 'from', message: 'Enter a valid start and end date' }]);
        }
        if (from > to) {
          throw new ValidationError([{ field: 'to', message: 'End date must be on or after the start date' }]);
        }
        range = { from, to };
      } else {
        range = await reportService.defaultRange();
      }

      const report = await reportService.buildReport({
        from: range.from,
        to: range.to,
        roomId: roomId || null,
      });
      return res.json({
        report,
        rooms,
        filters: {
          from: toDateInput(report.range.from),
          to: toDateInput(report.range.to),
          roomId,
        },
      });
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

module.exports = router;
