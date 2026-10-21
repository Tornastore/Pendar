'use strict';

const http = require('node:http');
const crypto = require('node:crypto');
const { WebSocketServer, WebSocket } = require('ws');
const {
  ALLOWED_GAMES,
  ALLOWED_EMOJIS,
  cleanUsername,
  clampLevel,
  isActionFromSeat,
  sanitizeMastermindGuesses
} = require('./lib/protocol');

const PORT = Number(process.env.PORT || 3000);
const MAX_PAYLOAD = 16 * 1024;
const ORIGIN_ALLOWLIST = new Set(
  (process.env.ALLOWED_ORIGINS || 'https://tornastore.github.io,http://localhost:8060,http://127.0.0.1:8060')
    .split(',').map(value => value.trim()).filter(Boolean)
);
const queues = new Map();
const clients = new Map();
const rooms = new Map();

function send(socket, payload) {
  if (socket && socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(payload));
    return true;
  }
  return false;
}

function error(socket, message, code = 'invalid_request') {
  send(socket, { type: 'error', code, message });
}

function queueFor(game) {
  if (!queues.has(game)) queues.set(game, []);
  return queues.get(game);
}

function detachFromQueue(socket) {
  const client = clients.get(socket);
  if (!client || client.state !== 'queued' || !client.game) return;
  const queue = queueFor(client.game);
  const index = queue.indexOf(socket);
  if (index >= 0) queue.splice(index, 1);
  client.state = 'idle';
  client.game = null;
}

function notifyOpponentLeft(client) {
  if (!client || !client.room) return;
  const room = client.room;
  const opponent = room.players.find(player => player && player.socket !== client.socket && player.socket.readyState === WebSocket.OPEN);
  rooms.delete(room.id);
  for (const player of room.players) {
    if (!player) continue;
    const state = clients.get(player.socket);
    if (state) {
      state.room = null;
      state.state = 'idle';
      state.game = null;
    }
  }
  if (opponent) {
    send(opponent.socket, { type: 'opponent_left', reason: 'disconnect' });
  }
  client.room = null;
  client.state = 'idle';
  client.game = null;
}

function leaveQueue(socket) {
  const client = clients.get(socket);
  if (!client || client.state !== 'queued') return;
  detachFromQueue(socket);
  send(socket, { type: 'queue_cancelled' });
}

function pairPlayers(firstSocket, secondSocket, game) {
  const first = clients.get(firstSocket);
  const second = clients.get(secondSocket);
  if (!first || !second || firstSocket.readyState !== WebSocket.OPEN || secondSocket.readyState !== WebSocket.OPEN) return false;

  const roomId = crypto.randomBytes(5).toString('hex').toUpperCase();
  const seed = crypto.randomInt(1, 2_147_483_647);
  const room = {
    id: roomId,
    game,
    seed,
    players: [
      { socket: firstSocket, seat: 0, username: first.username },
      { socket: secondSocket, seat: 1, username: second.username }
    ],
    mastermindDifficulty: first.mastermindDifficulty,
    blockaceDifficulty: first.blockaceDifficulty,
    mastermindCodeLength: 0,
    mastermindColorCount: 0
  };
  rooms.set(roomId, room);
  first.state = 'matched';
  first.room = room;
  first.seat = 0;
  first.game = game;
  second.state = 'matched';
  second.room = room;
  second.seat = 1;
  second.game = game;

  send(firstSocket, {
    type: 'match_found', game, room_id: roomId, seat: 0, opponent_username: second.username,
    seed, mastermind_difficulty: room.mastermindDifficulty, blockace_difficulty: room.blockaceDifficulty
  });
  send(secondSocket, {
    type: 'match_found', game, room_id: roomId, seat: 1, opponent_username: first.username,
    seed, mastermind_difficulty: room.mastermindDifficulty, blockace_difficulty: room.blockaceDifficulty
  });
  return true;
}

function joinQueue(socket, payload) {
  const client = clients.get(socket);
  if (!client) return;
  if (client.room) {
    error(socket, 'شما در حال حاضر داخل یک بازی هستید. ابتدا بازی را ترک کنید.', 'already_in_match');
    return;
  }
  if (client.state === 'queued') detachFromQueue(socket);
  const game = typeof payload.game === 'string' ? payload.game : '';
  if (!ALLOWED_GAMES.has(game)) {
    error(socket, 'این بازی برای تطبیق آنلاین فعال نیست.', 'game_not_supported');
    return;
  }
  client.game = game;
  client.username = cleanUsername(payload.username);
  client.mastermindDifficulty = clampLevel(payload.mastermind_difficulty);
  client.blockaceDifficulty = clampLevel(payload.blockace_difficulty);
  const queue = queueFor(game);
  while (queue.length && queue[0].readyState !== WebSocket.OPEN) queue.shift();
  const opponentSocket = queue.shift();
  if (opponentSocket && clients.get(opponentSocket)?.state === 'queued' && opponentSocket !== socket) {
    const paired = pairPlayers(opponentSocket, socket, game);
    if (paired) return;
    if (opponentSocket.readyState === WebSocket.OPEN && clients.get(opponentSocket)?.state === 'queued') queue.unshift(opponentSocket);
  }
  queue.push(socket);
  client.state = 'queued';
  send(socket, { type: 'queued', game, position: queue.length });
}

function sendActionToOpponent(socket, payload) {
  const client = clients.get(socket);
  if (!client || !client.room || client.state !== 'matched') return;
  if (typeof payload.action !== 'string' || !Array.isArray(payload.args)) {
    error(socket, 'ساختار حرکت معتبر نیست.');
    return;
  }
  if (!isActionFromSeat(payload.action, payload.args, client.seat)) {
    error(socket, 'حرکت از این بازیکن یا با این اطلاعات مجاز نیست.', 'action_not_allowed');
    return;
  }
  const other = client.room.players[1 - client.seat];
  if (other) send(other.socket, { type: 'action', action: payload.action, args: payload.args, seat: client.seat });
}

function handleMastermind(socket, client, payload) {
  const room = client.room;
  if (!room || room.game !== 'mastermind') return;
  const other = room.players[1 - client.seat];
  if (!other) return;
  if (payload.type === 'mastermind_secret_ready') {
    if (client.seat !== 0) return error(socket, 'فقط میزبان کد مخفی را ثبت می‌کند.', 'not_host');
    const codeLength = Number(payload.code_length);
    const colorCount = Number(payload.color_count);
    if (!Number.isInteger(codeLength) || codeLength < 4 || codeLength > 9 || !Number.isInteger(colorCount) || colorCount < 4 || colorCount > 9) {
      return error(socket, 'تنظیمات کد مخفی نامعتبر است.');
    }
    room.mastermindCodeLength = codeLength;
    room.mastermindColorCount = colorCount;
    send(other.socket, { type: 'mastermind_secret_ready', code_length: codeLength, color_count: colorCount });
    return;
  }
  if (payload.type === 'mastermind_guess') {
    if (client.seat !== 1) return error(socket, 'فقط حدس‌زن می‌تواند حدس بفرستد.', 'not_guesser');
    const guess = payload.guess;
    if (!Array.isArray(guess) || guess.length !== room.mastermindCodeLength || guess.some(value => !Number.isInteger(value) || value < 0 || value >= room.mastermindColorCount)) {
      return error(socket, 'حدس نامعتبر است.');
    }
    send(other.socket, { type: 'mastermind_guess', guess });
    return;
  }
  if (payload.type === 'mastermind_sync') {
    if (client.seat !== 0) return error(socket, 'فقط میزبان می‌تواند نتیجه‌ی حدس‌ها را بفرستد.', 'not_host');
    if (room.mastermindCodeLength < 4 || room.mastermindColorCount < 4) return error(socket, 'کد مخفی هنوز ثبت نشده است.');
    const guesses = sanitizeMastermindGuesses(payload.guesses, room.mastermindCodeLength, room.mastermindColorCount);
    if (guesses === null) return error(socket, 'وضعیت حدس‌های فکر بکر نامعتبر است.');
    const isOver = Boolean(payload.is_over);
    const winner = Number(payload.winner);
    if (![-1, 0, 1].includes(winner) || (isOver && winner === -1) || (!isOver && winner !== -1)) {
      return error(socket, 'برنده‌ی بازی نامعتبر است.');
    }
    send(other.socket, { type: 'mastermind_sync', guesses, is_over: isOver, winner });
  }
}

function handleMessage(socket, raw) {
  const client = clients.get(socket);
  if (!client) return;
  let payload;
  try {
    payload = JSON.parse(raw.toString());
  } catch {
    return error(socket, 'پیام JSON معتبر نیست.');
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload) || typeof payload.type !== 'string') {
    return error(socket, 'ساختار پیام نامعتبر است.');
  }
  switch (payload.type) {
    case 'join_queue': return joinQueue(socket, payload);
    case 'leave_queue': return leaveQueue(socket);
    case 'leave_match': return notifyOpponentLeft(client);
    case 'action': return sendActionToOpponent(socket, payload);
    case 'emoji': {
      if (!client.room || client.state !== 'matched') return;
      const now = Date.now();
      if (now - client.lastEmojiAt < 900) return;
      if (!ALLOWED_EMOJIS.has(payload.emoji)) return;
      client.lastEmojiAt = now;
      const other = client.room.players[1 - client.seat];
      if (other) send(other.socket, { type: 'emoji', emoji: payload.emoji, seat: client.seat });
      return;
    }
    case 'mastermind_secret_ready':
    case 'mastermind_guess':
    case 'mastermind_sync':
      return handleMastermind(socket, client, payload);
    case 'restart_game': {
      if (!client.room || client.seat !== 0) return error(socket, 'فقط میزبان می‌تواند بازی را از نو شروع کند.', 'not_host');
      if (payload.game !== client.room.game) return error(socket, 'بازی درخواست‌شده با اتاق یکی نیست.');
      const other = client.room.players[1];
      if (other) send(other.socket, {
        type: 'restart_game', game: client.room.game,
        seed: Number.isInteger(payload.seed) ? payload.seed : client.room.seed,
        mastermind_difficulty: client.room.mastermindDifficulty,
        blockace_difficulty: client.room.blockaceDifficulty
      });
      return;
    }
    default:
      return error(socket, 'نوع پیام پشتیبانی نمی‌شود.');
  }
}

const httpServer = http.createServer((request, response) => {
  const url = new URL(request.url || '/', `http://${request.headers.host || 'localhost'}`);
  if (request.method === 'GET' && url.pathname === '/health') {
    const body = JSON.stringify({ ok: true, service: 'mind-bastion-matchmaker', protocol: 1, waiting: [...queues.values()].reduce((total, q) => total + q.length, 0), rooms: rooms.size });
    response.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
    response.end(body);
    return;
  }
  response.writeHead(200, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
  response.end('Mind Bastion Matchmaker is running. Connect to /ws.\n');
});

const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_PAYLOAD, perMessageDeflate: false });
httpServer.on('upgrade', (request, socket, head) => {
  const url = new URL(request.url || '/', `http://${request.headers.host || 'localhost'}`);
  if (url.pathname !== '/ws') {
    socket.write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
    socket.destroy();
    return;
  }
  const origin = request.headers.origin;
  if (origin && !ORIGIN_ALLOWLIST.has(origin)) {
    socket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');
    socket.destroy();
    return;
  }
  wss.handleUpgrade(request, socket, head, websocket => wss.emit('connection', websocket, request));
});

wss.on('connection', (socket) => {
  clients.set(socket, {
    socket, state: 'idle', username: 'بازیکن', game: null,
    seat: -1, room: null, mastermindDifficulty: 3, blockaceDifficulty: 3,
    lastEmojiAt: 0
  });
  send(socket, { type: 'hello', protocol: 1, service: 'mind-bastion-matchmaker' });
  socket.on('message', raw => handleMessage(socket, raw));
  socket.on('error', () => {});
  socket.on('close', () => {
    const client = clients.get(socket);
    if (!client) return;
    if (client.state === 'queued') detachFromQueue(socket);
    if (client.room) notifyOpponentLeft(client);
    clients.delete(socket);
  });
});

const heartbeat = setInterval(() => {
  for (const socket of wss.clients) {
    if (socket.readyState !== WebSocket.OPEN) continue;
    if (socket._mbAlive === false) {
      socket.terminate();
      continue;
    }
    socket._mbAlive = false;
    socket.ping();
  }
}, 30000);

wss.on('connection', socket => {
  socket._mbAlive = true;
  socket.on('pong', () => { socket._mbAlive = true; });
});

httpServer.listen(PORT, '0.0.0.0', () => {
  process.stdout.write(`Mind Bastion Matchmaker listening on ${PORT}\n`);
});

function shutdown() {
  clearInterval(heartbeat);
  for (const socket of wss.clients) socket.close(1001, 'server shutdown');
  httpServer.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5000).unref();
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
