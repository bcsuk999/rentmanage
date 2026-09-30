'use strict';

const { ValidationError } = require('./validate');

/** Wrap an async route handler so rejected promises reach the error middleware. */
function wrap(handler) {
  return (req, res, next) => Promise.resolve(handler(req, res, next)).catch(next);
}

function fieldErrors(err) {
  return err instanceof ValidationError ? err.errors : [];
}

function firstErrorMessage(err) {
  const list = fieldErrors(err);
  return list.length ? list.map((e) => e.message).join(' ') : err.message;
}

/** Keep submitted values on the form when validation fails. */
function withBody(body) {
  return { ...body };
}

module.exports = { fieldErrors, firstErrorMessage, withBody, wrap };
