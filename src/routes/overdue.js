'use strict';

const express = require('express');
const { overdueReport } = require('../services/overdueService');
const { sendApiError, wrap } = require('../utils/http');

const router = express.Router();

/** Members holding overdue rent, with each overdue period and totals. */
router.get(
  '/',
  wrap(async (req, res) => {
    try {
      const report = await overdueReport(req.user._id);
      return res.json(report);
    } catch (err) {
      return sendApiError(res, err);
    }
  })
);

module.exports = router;
