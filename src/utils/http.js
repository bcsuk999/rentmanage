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

/**
 * JSON error envelope for the API. Validation errors keep their field list so
 * clients can highlight inputs; everything else is a single message.
 */
function sendApiError(res, err) {
  const status = err && err.status ? err.status : 500;
  if (err instanceof ValidationError) {
    return res.status(status).json({ error: firstErrorMessage(err), errors: err.errors });
  }
  const message = err && err.expose && err.message ? err.message : 'An unexpected error occurred.';
  return res.status(status).json({ error: message });
}

module.exports = { fieldErrors, firstErrorMessage, sendApiError, withBody, wrap };
