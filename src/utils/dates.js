'use strict';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** Today at UTC midnight, derived from the local calendar date. */
function today() {
  const now = new Date();
  return new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
}

/** Normalise any date-ish value to UTC midnight. */
function startOfDay(value) {
  const d = value instanceof Date ? value : new Date(value);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

function addDays(value, days) {
  const d = startOfDay(value);
  d.setUTCDate(d.getUTCDate() + days);
  return d;
}

/** Add whole months, clamping the day to the last valid day of the target month. */
function addMonths(value, months) {
  const d = startOfDay(value);
  const targetMonth = d.getUTCMonth() + months;
  const result = new Date(Date.UTC(d.getUTCFullYear(), targetMonth, 1));
  const lastDay = new Date(
    Date.UTC(result.getUTCFullYear(), result.getUTCMonth() + 1, 0)
  ).getUTCDate();
  result.setUTCDate(Math.min(d.getUTCDate(), lastDay));
  return result;
}

/** The cycle that starts on `start`: [start, start + 1 month - 1 day]. */
function cycleEnd(start) {
  return addDays(addMonths(start, 1), -1);
}

/** The cycle index that contains `date`, given a cycle start anchor. -1 if before the anchor. */
function cycleIndexFor(anchor, date) {
  const a = startOfDay(anchor);
  const d = startOfDay(date);
  if (d < a) return -1;
  let index = 0;
  let cursor = a;
  while (cursor <= d) {
    const end = cycleEnd(cursor);
    if (d <= end) return index;
    index += 1;
    cursor = addDays(end, 1);
  }
  return index;
}

/** The [start, end] cycle of `anchor` at `index` cycles after the anchor. */
function cycleAt(anchor, index) {
  const start = addMonths(anchor, index);
  return { start, end: cycleEnd(start) };
}

function contains(start, end, date) {
  const d = startOfDay(date);
  return d >= startOfDay(start) && d <= startOfDay(end);
}

function formatDate(value) {
  if (!value) return '-';
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return '-';
  return `${String(d.getUTCDate()).padStart(2, '0')} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}

function formatDateShort(value) {
  if (!value) return '-';
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return '-';
  return `${String(d.getUTCDate()).padStart(2, '0')} ${MONTHS[d.getUTCMonth()]}`;
}

function formatDateRange(start, end) {
  return `${formatDate(start)} – ${formatDate(end)}`;
}

/** Format for <input type="date"> and for query strings. */
function toDateInput(value) {
  if (!value) return '';
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  return d.toISOString().slice(0, 10);
}

/** Parse YYYY-MM-DD (or a full ISO string) into UTC midnight. Returns null when invalid. */
function parseDateInput(value) {
  if (!value) return null;
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : startOfDay(value);
  }
  const text = String(value).trim();
  const iso = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (iso) {
    const [, y, m, d] = iso;
    const date = new Date(Date.UTC(Number(y), Number(m) - 1, Number(d)));
    if (
      date.getUTCFullYear() !== Number(y) ||
      date.getUTCMonth() !== Number(m) - 1 ||
      date.getUTCDate() !== Number(d)
    ) {
      return null;
    }
    return date;
  }
  const parsed = new Date(text);
  return Number.isNaN(parsed.getTime()) ? null : startOfDay(parsed);
}

function isValidDate(value) {
  return value instanceof Date && !Number.isNaN(value.getTime());
}

function daysInMonth(year, monthIndex) {
  return new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate();
}

function diffDays(later, earlier) {
  return Math.round((startOfDay(later) - startOfDay(earlier)) / 86400000);
}

function isOverdue(endDate, reference = today()) {
  return startOfDay(endDate) < startOfDay(reference);
}

module.exports = {
  MONTHS,
  addDays,
  addMonths,
  contains,
  cycleAt,
  cycleEnd,
  cycleIndexFor,
  daysInMonth,
  diffDays,
  formatDate,
  formatDateRange,
  formatDateShort,
  isOverdue,
  isValidDate,
  parseDateInput,
  startOfDay,
  toDateInput,
  today,
};
