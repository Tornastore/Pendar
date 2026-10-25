'use strict';

// Skill-based pairing for the Pendar queue. Pure functions: no sockets, no timers, easy to test.
// Players are matched by their *match rating* for the chosen game (a blend of game MMR and overall MMR computed by the
// client). The accepted rating gap starts tight and widens the longer someone waits, so nobody waits forever.

const MIN_RATING = 100;
const MAX_RATING = 3000;
const DEFAULT_RATING = 1000;
const BASE_WINDOW = 100;       // +/- rating points at second 0
const WINDOW_STEP = 50;        // added every STEP_MS
const STEP_MS = 4000;
const MAX_WINDOW = 800;        // after this the queue accepts anyone that is left
const ANYONE_AFTER_MS = 70000;

function clampRating(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return DEFAULT_RATING;
  return Math.max(MIN_RATING, Math.min(MAX_RATING, Math.trunc(number)));
}

function clampLeague(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0;
  return Math.max(0, Math.min(7, Math.trunc(number)));
}

function searchWindow(waitMs) {
  const waited = Math.max(0, Number(waitMs) || 0);
  if (waited >= ANYONE_AFTER_MS) return Infinity;
  return Math.min(MAX_WINDOW, BASE_WINDOW + Math.floor(waited / STEP_MS) * WINDOW_STEP);
}

// entries: [{ rating, joinedAt }]. Returns [indexA, indexB] or null.
// The longest-waiting player is served first; they get the closest rated partner that fits either player's window
// (the larger of the two windows is used so a long wait is never blocked by a newcomer's tight window).
function findBestPair(entries, now) {
  if (!Array.isArray(entries) || entries.length < 2) return null;
  const order = entries.map((entry, index) => index).sort((a, b) => entries[a].joinedAt - entries[b].joinedAt || a - b);
  for (const a of order) {
    const waitA = now - entries[a].joinedAt;
    let best = -1;
    let bestGap = Infinity;
    for (const b of order) {
      if (a === b) continue;
      const gap = Math.abs(entries[a].rating - entries[b].rating);
      const allowed = Math.max(searchWindow(waitA), searchWindow(now - entries[b].joinedAt));
      if (gap <= allowed && gap < bestGap) {
        best = b;
        bestGap = gap;
      }
    }
    if (best >= 0) return [a, best];
  }
  return null;
}

// Picks `size` players for a multiplayer room around the longest-waiting player. When `force` is true the window is
// ignored (used after the queue grace period) but the closest ratings are still preferred.
function pickGroup(entries, size, now, force = false) {
  if (!Array.isArray(entries) || size < 2 || entries.length < size) return null;
  const anchor = entries.map((entry, index) => index).sort((a, b) => entries[a].joinedAt - entries[b].joinedAt || a - b)[0];
  const window = searchWindow(now - entries[anchor].joinedAt);
  const others = entries
    .map((entry, index) => ({ index, gap: Math.abs(entry.rating - entries[anchor].rating) }))
    .filter(item => item.index !== anchor)
    .sort((a, b) => a.gap - b.gap || a.index - b.index)
    .slice(0, size - 1);
  if (others.length < size - 1) return null;
  if (!force && others.some(item => item.gap > window)) return null;
  return [anchor, ...others.map(item => item.index)];
}

function averageRating(values) {
  if (!values.length) return DEFAULT_RATING;
  return clampRating(Math.round(values.reduce((sum, value) => sum + value, 0) / values.length));
}

module.exports = {
  MIN_RATING, MAX_RATING, DEFAULT_RATING, BASE_WINDOW, MAX_WINDOW, ANYONE_AFTER_MS,
  clampRating, clampLeague, searchWindow, findBestPair, pickGroup, averageRating
};
