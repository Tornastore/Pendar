'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ALLOWED_GAMES, ALLOWED_EMOJIS, cleanUsername, clampLevel,
  isSafeAction, isActionFromSeat, playerCapacityForGame,
  fallbackRoomSizeForQueue, rankMastermindPlayers
} = require('../lib/protocol');

test('supports every game listed in the Godot online chooser', () => {
  for (const game of ['othello', 'othello12', 'pentago', 'chess', 'domino', 'pasoor', 'quoridor', 'hokm', 'backgammon', 'gobblet', 'mastermind', 'abalone', 'blockace', 'quarto', 'uno']) {
    assert.ok(ALLOWED_GAMES.has(game), `missing ${game}`);
  }
});

test('normalizes usernames and limits to 18 code points', () => {
  assert.equal(cleanUsername('  <host>\nاسم  '), 'host اسم');
  assert.equal(Array.from(cleanUsername('😀'.repeat(30))).length, 18);
  assert.equal(cleanUsername('   '), 'بازیکن');
});

test('clamps difficulty levels to 1..6', () => {
  assert.equal(clampLevel(-4), 1);
  assert.equal(clampLevel(3.8), 3);
  assert.equal(clampLevel(99), 6);
  assert.equal(clampLevel('bad'), 3);
});

test('validates allowed moves and seat-bearing arguments', () => {
  assert.equal(isActionFromSeat('_rpc_othello_place', [3, 2], 0), true);
  assert.equal(isActionFromSeat('_rpc_dom_draw', [1], 1), true);
  assert.equal(isActionFromSeat('_rpc_dom_draw', [0], 1), false);
  assert.equal(isActionFromSeat('_rpc_gob_place', [2, 1, 3, 2], 1), true);
  assert.equal(isActionFromSeat('_rpc_resign', [0], 1), false);
  assert.equal(isSafeAction('system', []), false);
});

test('emoji choices are constrained to the expected set', () => {
  assert.ok(ALLOWED_EMOJIS.has('👍'));
  assert.ok(ALLOWED_EMOJIS.has('❤️'));
  assert.ok(!ALLOWED_EMOJIS.has('spam'));
});

test('validates incoming Mastermind feedback records before relay', () => {
  const { sanitizeMastermindGuesses } = require('../lib/protocol');
  const valid = [{ g: [0, 1, 2, 3], b: 1, w: 2, f: [2, 1, 1, 0], p: 1 }];
  assert.deepEqual(sanitizeMastermindGuesses(valid, 4, 4), valid);
  assert.equal(sanitizeMastermindGuesses([{ g: [0], b: 1, w: 0, f: [2], p: 1 }], 4, 4), null);
  assert.equal(sanitizeMastermindGuesses([{ g: [0, 1, 2, 3], b: 4, w: 2, f: [2, 2, 2, 2], p: 1 }], 4, 4), null);
});


test('LAN and online player capacity is four only for games with multiplayer rules', () => {
  assert.equal(playerCapacityForGame('mastermind'), 4);
  assert.equal(playerCapacityForGame('quoridor'), 4);
  assert.equal(playerCapacityForGame('chess'), 2);
});

test('queue matchmaking forms 2-4 player Mastermind matches and valid Quoridor sizes', () => {
  assert.equal(fallbackRoomSizeForQueue('mastermind', 1), 0);
  assert.equal(fallbackRoomSizeForQueue('mastermind', 2), 2);
  assert.equal(fallbackRoomSizeForQueue('mastermind', 3), 3);
  assert.equal(fallbackRoomSizeForQueue('mastermind', 4), 4);
  assert.equal(fallbackRoomSizeForQueue('mastermind', 6), 4);
  assert.equal(fallbackRoomSizeForQueue('quoridor', 3), 2);
  assert.equal(fallbackRoomSizeForQueue('quoridor', 4), 4);
});

test('Mastermind progress ranking changes live and solved players sort by solve time', () => {
  const ranked = rankMastermindPlayers([
    { seat: 0, status: 'active', latestBlack: 1, attemptsUsed: 2, solveMs: 0 },
    { seat: 1, status: 'active', latestBlack: 3, attemptsUsed: 5, solveMs: 0 },
    { seat: 2, status: 'solved', latestBlack: 6, attemptsUsed: 7, solveMs: 8200 },
    { seat: 3, status: 'solved', latestBlack: 6, attemptsUsed: 5, solveMs: 5100 }
  ]);
  assert.deepEqual(ranked.map(p => p.seat), [3, 2, 1, 0]);
  assert.deepEqual(ranked.map(p => p.rank), [1, 2, 3, 4]);
});


test('Quarto online actions validate seat, piece IDs and board coordinates', () => {
  assert.equal(isActionFromSeat('_rpc_quarto_choose_piece', [0, 15], 0), true);
  assert.equal(isActionFromSeat('_rpc_quarto_choose_piece', [0, 16], 0), false);
  assert.equal(isActionFromSeat('_rpc_quarto_choose_piece', [1, 2], 0), false);
  assert.equal(isActionFromSeat('_rpc_quarto_place', [1, 3, 3], 1), true);
  assert.equal(isActionFromSeat('_rpc_quarto_place', [1, 4, 3], 1), false);
  assert.equal(isActionFromSeat('_rpc_quarto_place', [1, 0, 0], 0), false);
  assert.equal(playerCapacityForGame('quarto'), 2);
});


test('UNO supports up to ten players and queue fallback rooms from two to ten', () => {
  assert.equal(playerCapacityForGame('uno'), 10);
  assert.equal(fallbackRoomSizeForQueue('uno', 1), 0);
  assert.equal(fallbackRoomSizeForQueue('uno', 2), 2);
  assert.equal(fallbackRoomSizeForQueue('uno', 7), 7);
  assert.equal(fallbackRoomSizeForQueue('uno', 13), 10);
});

test('UNO actions validate seat, card index, color and action payloads', () => {
  assert.equal(isActionFromSeat('_rpc_uno_play', [2, 111, 3, true], 2, 10), true);
  assert.equal(isActionFromSeat('_rpc_uno_play', [2, 112, 3, true], 2, 10), false);
  assert.equal(isActionFromSeat('_rpc_uno_play', [1, 2, 3, true], 2, 10), false);
  assert.equal(isActionFromSeat('_rpc_uno_draw', [4], 4, 10), true);
  assert.equal(isActionFromSeat('_rpc_uno_challenge', [4, 'true'], 4, 10), false);
  assert.equal(isActionFromSeat('_rpc_uno_next_round', [0, 123], 0, 10), true);
  assert.equal(isActionFromSeat('_rpc_uno_next_round', [1, 123], 1, 10), false);
});
