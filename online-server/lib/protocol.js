'use strict';

const ALLOWED_GAMES = new Set([
  'othello', 'othello12', 'pentago', 'chess', 'domino', 'pasoor',
  'quoridor', 'hokm', 'backgammon', 'gobblet', 'mastermind', 'abalone', 'blockace'
]);

const ALLOWED_ACTIONS = new Set([
  '_rpc_othello_place', '_rpc_pent_place', '_rpc_pent_rotate',
  '_rpc_dom_play', '_rpc_dom_draw', '_rpc_dom_pass', '_rpc_chess_move',
  '_rpc_quo_action', '_rpc_pas_play', '_rpc_gob_place', '_rpc_gob_move',
  '_rpc_aba_move', '_rpc_blk_place', '_rpc_bg_step', '_rpc_hokm_play',
  '_rpc_resign'
]);

const ALLOWED_EMOJIS = new Set(['👍', '😂', '❤️', '🔥', '👏', '😮', '😢', '🤔']);

function cleanUsername(value) {
  const raw = typeof value === 'string' ? value : '';
  const cleaned = raw
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/[<>]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  const chars = Array.from(cleaned).slice(0, 18).join('');
  return chars || 'بازیکن';
}

function clampLevel(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 3;
  return Math.max(1, Math.min(6, Math.trunc(number)));
}

function isSafeAction(action, args) {
  if (!ALLOWED_ACTIONS.has(action) || !Array.isArray(args) || args.length > 10) return false;
  try {
    return Buffer.byteLength(JSON.stringify(args), 'utf8') <= 8000;
  } catch {
    return false;
  }
}

function isActionFromSeat(action, args, seat) {
  if (!isSafeAction(action, args) || ![0, 1].includes(seat)) return false;
  switch (action) {
    case '_rpc_dom_play':
    case '_rpc_dom_draw':
    case '_rpc_dom_pass':
    case '_rpc_pas_play':
    case '_rpc_hokm_play':
      return args.length > 0 && Number(args[0]) === seat;
    case '_rpc_blk_place':
      return args.length >= 6 && Number(args[5]) === seat;
    case '_rpc_gob_place':
      return args.length >= 4 && Number(args[3]) === seat + 1;
    case '_rpc_gob_move':
      return args.length >= 5 && Number(args[4]) === seat + 1;
    case '_rpc_aba_move':
      return args.length >= 4 && Number(args[3]) === seat + 1;
    case '_rpc_resign':
      return args.length > 0 && Number(args[0]) === seat;
    default:
      return true;
  }
}

module.exports = {
  ALLOWED_GAMES,
  ALLOWED_ACTIONS,
  ALLOWED_EMOJIS,
  cleanUsername,
  clampLevel,
  isSafeAction,
  isActionFromSeat,
  sanitizeMastermindGuesses
};

function sanitizeMastermindGuesses(value, codeLength, colorCount) {
  if (!Number.isInteger(codeLength) || codeLength < 4 || codeLength > 9 || !Number.isInteger(colorCount) || colorCount < 4 || colorCount > 9) return null;
  if (!Array.isArray(value) || value.length > 10) return null;
  const result = [];
  for (const entry of value) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) return null;
    const guess = entry.g;
    const feedback = entry.f;
    const black = Number(entry.b);
    const white = Number(entry.w);
    const player = Number(entry.p);
    if (!Array.isArray(guess) || guess.length !== codeLength || guess.some(v => !Number.isInteger(v) || v < 0 || v >= colorCount)) return null;
    if (!Array.isArray(feedback) || feedback.length !== codeLength || feedback.some(v => !Number.isInteger(v) || v < 0 || v > 2)) return null;
    if (!Number.isInteger(black) || black < 0 || black > codeLength || !Number.isInteger(white) || white < 0 || white > codeLength || black + white > codeLength) return null;
    if (![0, 1].includes(player)) return null;
    result.push({ g: guess, b: black, w: white, f: feedback, p: player });
  }
  return result;
}
