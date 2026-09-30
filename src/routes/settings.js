'use strict';

const express = require('express');
const Admin = require('../models/Admin');
const roomService = require('../services/roomService');
const { wrap } = require('../utils/http');
const { formatDate, toDateInput, today } = require('../utils/dates');

const router = express.Router();

router.get(
  '/',
  wrap(async (req, res) => {
    const rooms = await roomService.listRoomsWithSummary({});
    res.render('settings/index', {
      title: 'Settings',
      rooms,
      today: toDateInput(today()),
    });
  })
);

router.get(
  '/admins',
  wrap(async (req, res) => {
    const admins = await Admin.find().sort({ createdAt: 1 }).lean();
    res.render('settings/admins', {
      title: 'Admin accounts',
      admins: admins.map((a) => ({ ...a, createdAtLabel: formatDate(a.createdAt), lastLogin: a.lastLoginAt ? formatDate(a.lastLoginAt) : 'Never' })),
    });
  })
);

module.exports = router;
