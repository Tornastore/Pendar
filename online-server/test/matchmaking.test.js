'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  clampRating, clampLeague, searchWindow, findBestPair, pickGroup, averageRating, MAX_WINDOW
} = require('../lib/matchmaking');

test('clamps ratings and leagues from untrusted clients', () => {
  assert.equal(clampRating('abc'), 1000);
  assert.equal(clampRating(-5), 100);
  assert.equal(clampRating(99999), 3000);
  assert.equal(clampRating(1234.9), 1234);
  assert.equal(clampLeague(12), 7);
  assert.equal(clampLeague(-1), 0);
  assert.equal(clampLeague(undefined), 0);
});

test('search window starts tight, widens with waiting and eventually accepts anyone', () => {
  assert.equal(searchWindow(0), 100);
  assert.equal(searchWindow(4000), 150);
  assert.equal(searchWindow(20000), 350);
  assert.equal(searchWindow(60000), MAX_WINDOW);
  assert.equal(searchWindow(70000), Infinity);
});

test('pairs the closest ratings, not first-come-first-served', () => {
  const now = 1000;
  const entries = [
    { rating: 1000, joinedAt: 0 },
    { rating: 1500, joinedAt: 10 },
    { rating: 1060, joinedAt: 20 }
  ];
  const pair = findBestPair(entries, now);
  assert.deepEqual(pair.slice().sort(), [0, 2]);
});

test('does not pair players who are far apart until they have waited', () => {
  const entries = [
    { rating: 900, joinedAt: 0 },
    { rating: 1400, joinedAt: 0 }
  ];
  assert.equal(findBestPair(entries, 2000), null);
  assert.equal(findBestPair(entries, 30000), null);
  assert.notEqual(findBestPair(entries, 60000), null);
});

test('a long-waiting player is not blocked by a newcomer tight window', () => {
  const entries = [
    { rating: 1000, joinedAt: 0 },
    { rating: 1300, joinedAt: 49000 }
  ];
  assert.notEqual(findBestPair(entries, 50000), null);
});

test('returns null for fewer than two entries', () => {
  assert.equal(findBestPair([], 0), null);
  assert.equal(findBestPair([{ rating: 1000, joinedAt: 0 }], 0), null);
});

test('groups multiplayer rooms around the longest waiting player by closeness', () => {
  const entries = [
    { rating: 1000, joinedAt: 0 },
    { rating: 1900, joinedAt: 5 },
    { rating: 1040, joinedAt: 6 },
    { rating: 960, joinedAt: 7 },
    { rating: 1090, joinedAt: 8 }
  ];
  const group = pickGroup(entries, 4, 500, false);
  assert.deepEqual(group.slice().sort(), [0, 2, 3, 4]);
});

test('group requires everyone inside the window unless forced', () => {
  const entries = [
    { rating: 1000, joinedAt: 0 },
    { rating: 1900, joinedAt: 0 },
    { rating: 1950, joinedAt: 0 }
  ];
  assert.equal(pickGroup(entries, 3, 500, false), null);
  assert.equal(pickGroup(entries, 3, 500, true).length, 3);
  assert.equal(pickGroup(entries, 4, 500, true), null);
});

test('averages opponent ratings', () => {
  assert.equal(averageRating([1000, 1100, 1200]), 1100);
  assert.equal(averageRating([]), 1000);
});
