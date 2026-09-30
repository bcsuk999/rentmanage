'use strict';

const express = require('express');

const router = express.Router();

/** Rooms is the primary screen, so the root path lands there. */
router.get('/', (req, res) => res.redirect('/rooms'));

module.exports = router;
