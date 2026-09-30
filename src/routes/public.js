'use strict';

const express = require('express');

const router = express.Router();

/** Public endpoints: the offline shell used by the service worker. */
router.get('/offline', (req, res) => {
  res.set('Cache-Control', 'public, max-age=0, must-revalidate');
  res.render('offline', { title: 'Offline' });
});

router.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

module.exports = router;
