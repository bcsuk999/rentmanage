'use strict';

/** Store a one-shot message in the session for the next rendered page. */
function flash(req, type, message) {
  req.session.flash = { type, message };
}

const CLASSES = {
  success: 'flash flash-success',
  error: 'flash flash-error',
  info: 'flash flash-info',
  warning: 'flash flash-warning',
};

function flashFor(type) {
  return CLASSES[type] || 'flash flash-info';
}

module.exports = { flash, flashFor };
