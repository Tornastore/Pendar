'use strict';

const http = require('node:http');
const crypto = require('node:crypto');
const { WebSocketServer, WebSocket } = require('ws');
const {
  ALLOWED_GAMES,
  ALLOWED_EMOJIS,
  cleanUsername,
  clampLevel,
  playerCapacityForGame,
  fallbackRoomSizeForQueue,
  isActionFromSeat,
  evaluateMastermindGuess,
  rankMastermindPlayers
} = require('./lib/protocol');
const {
  clampRating, clampLeague, searchWindow, findBestPair, pickGroup, averageRating
} = require('./lib/matchmaking');

const PORT = Number(process.env.PORT || 3000);
const MAX_PAYLOAD = 16 * 1024;
const MATCH_TICK_MS = 2000;
const QUEUE_NOTICE_MS = 5000;
const QUEUE_WAIT_MS = Math.max(3000, Number(process.env.QUEUE_WAIT_MS || 12000));
const ORIGIN_ALLOWLIST = new Set(
  (process.env.ALLOWED_ORIGINS || 'https://tornastore.github.io,http://localhost:8060,http://127.0.0.1:8060')
    .split(',').map(value => value.trim()).filter(Boolean)
);
const queues = new Map();
const queueTimers = new Map();
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

function mastermindQueueKey(game, level) {
  return game === 'mastermind' ? `${game}:level-${clampLevel(level)}` : game;
}

function queueFor(key) {
  if (!queues.has(key)) queues.set(key, []);
  return queues.get(key);
}

function cleanQueue(key) {
  const queue = queueFor(key);
  for (let i = queue.length - 1; i >= 0; i -= 1) {
    const state = clients.get(queue[i]);
    if (!state || queue[i].readyState !== WebSocket.OPEN || state.state !== 'queued') queue.splice(i, 1);
  }
  return queue;
}

function publicRoster(room) {
  const players = room.players.map(player => {
    const progress = room.mastermind?.players.get(player.seat);
    if (!progress) return { seat: player.seat, username: player.username };
    return {
      seat: player.seat,
      username: player.username,
      status: progress.status,
      latest_black: progress.latestBlack,
      attempts_used: progress.attemptsUsed,
      solve_ms: progress.solveMs
    };
  });
  if (!room.mastermind) return players;
  return rankMastermindPlayers(players.map(p => {
    const { status = 'active', latest_black = 0, attempts_used = 0, solve_ms = 0, ...rest } = p;
    return { ...rest, status, latestBlack: latest_black, attemptsUsed: attempts_used, solveMs: solve_ms };
  })).map(p => ({
    seat: p.seat, username: p.username, status: p.status,
    latest_black: p.latestBlack, attempts_used: p.attemptsUsed,
    solve_ms: p.solveMs, rank: p.rank
  }));
}

function sendProgress(room) {
  if (!room.mastermind) return;
  const players = publicRoster(room);
  for (const player of room.players) send(player.socket, { type: 'mastermind_progress', room_id: room.id, players });
}

function cancelQueueTimer(key) {
  const timer = queueTimers.get(key);
  if (timer) clearTimeout(timer);
  queueTimers.delete(key);
}

function notifyRoomLeft(client, reason = 'disconnect') {
  if (!client || !client.room) return;
  const room = client.room;
  rooms.delete(room.id);
  for (const player of room.players) {
    const state = clients.get(player.socket);
    if (state) {
      state.room = null;
      state.state = 'idle';
      state.game = null;
      state.seat = -1;
    }
    if (player.socket !== client.socket) {
      send(player.socket, { type: 'opponent_left', reason, username: client.username });
    }
  }
  client.room = null;
  client.state = 'idle';
  client.game = null;
  client.seat = -1;
}

function detachFromQueue(socket) {
  const client = clients.get(socket);
  if (!client || client.state !== 'queued' || !client.queueKey) return;
  const queue = queueFor(client.queueKey);
  const index = queue.indexOf(socket);
  if (index >= 0) queue.splice(index, 1);
  const key = client.queueKey;
  client.state = 'idle';
  client.game = null;
  client.queueKey = null;
  if (queue.length === 0) cancelQueueTimer(key);
}

function leaveQueue(socket) {
  const client = clients.get(socket);
  if (!client || client.state !== 'queued') return;
  detachFromQueue(socket);
  send(socket, { type: 'queue_cancelled' });
}

function makeMastermindRoomState(players, difficulty, startedAt) {
  const codeLength = clampLevel(difficulty) + 3;
  const colorCount = clampLevel(difficulty) + 3;
  const secret = Array.from({ length: codeLength }, () => crypto.randomInt(0, colorCount));
  const playerStates = new Map();
  for (const player of players) {
    playerStates.set(player.seat, {
      attemptsUsed: 0,
      latestBlack: 0,
      status: 'active',
      solveMs: 0,
      lastGuessAt: 0
    });
  }
  return { codeLength, colorCount, secret, players: playerStates, startedAt };
}

function createRoom(sockets, game) {
  const connected = sockets.map(socket => ({ socket, state: clients.get(socket) }));
  if (connected.some(entry => !entry.state || socketClosed(entry.socket))) return false;
  const roomId = crypto.randomBytes(5).toString('hex').toUpperCase();
  const firstState = connected[0].state;
  const seed = crypto.randomInt(1, 2_147_483_647);
  const players = connected.map((entry, seat) => ({
    socket: entry.socket,
    seat,
    username: entry.state.username,
    rating: entry.state.rating,
    globalRating: entry.state.globalRating,
    league: entry.state.league
  }));
  const room = {
    id: roomId,
    game,
    seed,
    players,
    mastermindDifficulty: firstState.mastermindDifficulty,
    blockaceDifficulty: firstState.blockaceDifficulty,
    createdAt: Date.now(),
    mastermind: null
  };
  if (game === 'mastermind') {
    room.mastermind = makeMastermindRoomState(players, room.mastermindDifficulty, Date.now());
  }
  rooms.set(roomId, room);
  for (const player of players) {
    const client = clients.get(player.socket);
    client.state = 'matched';
    client.room = room;
    client.seat = player.seat;
    client.game = game;
    client.queueKey = null;
  }
  const roster = players.map(p => ({ seat: p.seat, username: p.username, rating: p.rating, league: p.league }));
  for (const player of players) {
    const otherPlayers = players.filter(p => p.seat !== player.seat);
    const others = otherPlayers.map(p => p.username);
    send(player.socket, {
      type: 'match_found', game, room_id: roomId, seat: player.seat,
      opponent_username: others.join('، '), players: roster,
      opponent_rating: averageRating(otherPlayers.map(p => p.rating)),
      opponent_global_rating: averageRating(otherPlayers.map(p => p.globalRating)),
      opponent_league: Math.round(otherPlayers.reduce((sum, p) => sum + p.league, 0) / otherPlayers.length),
      player_count: players.length, seed,
      mastermind_difficulty: room.mastermindDifficulty,
      blockace_difficulty: room.blockaceDifficulty,
      race_mode: game === 'mastermind',
      ...(room.mastermind ? { code_length: room.mastermind.codeLength, color_count: room.mastermind.colorCount } : {})
    });
  }
  if (room.mastermind) sendProgress(room);
  return true;
}

function socketClosed(socket) {
  return !socket || socket.readyState !== WebSocket.OPEN;
}

function queueEntries(queue) {
  return queue.map(socket => {
    const state = clients.get(socket);
    return { rating: state.rating, joinedAt: state.joinedAt };
  });
}

function removeIndexes(queue, indexes) {
  const sockets = indexes.map(index => queue[index]);
  indexes.slice().sort((a, b) => b - a).forEach(index => queue.splice(index, 1));
  return sockets;
}

function requeue(queue, sockets) {
  for (const socket of sockets.slice().reverse()) {
    const state = clients.get(socket);
    if (state && socket.readyState === WebSocket.OPEN && state.state === 'queued') queue.unshift(socket);
  }
}

function notifyQueue(key, queue, capacity, force = false) {
  const now = Date.now();
  queue.forEach((socket, index) => {
    const state = clients.get(socket);
    if (!state) return;
    if (!force && now - state.lastQueuedAt < QUEUE_NOTICE_MS) return;
    state.lastQueuedAt = now;
    const range = searchWindow(now - state.joinedAt);
    send(socket, {
      type: 'queued', game: state.game, position: index + 1,
      players_needed: Math.max(0, capacity - queue.length),
      search_range: Number.isFinite(range) ? range : null,
      waited_ms: now - state.joinedAt
    });
  });
}

function tryFormRooms(key, force = false, announce = true) {
  const queue = cleanQueue(key);
  if (!queue.length) {
    cancelQueueTimer(key);
    return;
  }
  const firstClient = clients.get(queue[0]);
  if (!firstClient) return;
  const game = firstClient.game;
  const capacity = playerCapacityForGame(game);
  const now = Date.now();
  const multi = game === 'mastermind' || game === 'quoridor' || game === 'uno';
  if (!multi) {
    // 1v1: closest ratings first, widening the accepted gap with waiting time.
    while (queue.length >= 2) {
      const pair = findBestPair(queueEntries(queue), now);
      if (!pair) break;
      const sockets = removeIndexes(queue, pair);
      if (!createRoom(sockets, game)) {
        requeue(queue, sockets);
        break;
      }
    }
  } else {
    while (queue.length >= capacity) {
      const group = pickGroup(queueEntries(queue), capacity, now, false);
      if (!group) break;
      const sockets = removeIndexes(queue, group);
      if (!createRoom(sockets, game)) {
        requeue(queue, sockets);
        break;
      }
    }
    if (force && queue.length >= 2) {
      const groupSize = fallbackRoomSizeForQueue(game, queue.length);
      if (groupSize >= 2) {
        const group = pickGroup(queueEntries(queue), groupSize, now, true);
        if (group) {
          const sockets = removeIndexes(queue, group);
          if (!createRoom(sockets, game)) requeue(queue, sockets);
        }
      }
    }
  }
  if (queue.length === 0) {
    cancelQueueTimer(key);
  } else if (multi) {
    scheduleQueueFlush(key);
  }
  if (announce) notifyQueue(key, queue, multi ? capacity : 2, announce === 'force');
}

function scheduleQueueFlush(key) {
  if (queueTimers.has(key)) return;
  const timer = setTimeout(() => {
    queueTimers.delete(key);
    tryFormRooms(key, true);
  }, QUEUE_WAIT_MS);
  timer.unref?.();
  queueTimers.set(key, timer);
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
  // Ratings are reported by the client (there are no server accounts yet): they only steer pairing, so a dishonest
  // client can at most pick its own opponents. They are clamped and never trusted for anything else.
  client.rating = clampRating(payload.rating);
  client.globalRating = clampRating(payload.global_rating ?? payload.rating);
  client.league = clampLeague(payload.league);
  client.joinedAt = Date.now();
  client.lastQueuedAt = 0;
  const key = mastermindQueueKey(game, client.mastermindDifficulty);
  client.queueKey = key;
  client.state = 'queued';
  const queue = queueFor(key);
  if (!queue.includes(socket)) queue.push(socket);
  tryFormRooms(key, false, 'force');
  if (game === 'mastermind' || game === 'quoridor' || game === 'uno') scheduleQueueFlush(key);
}

function sendActionToRoom(socket, payload) {
  const client = clients.get(socket);
  const room = client?.room;
  if (!client || !room || client.state !== 'matched') return;
  if (typeof payload.action !== 'string' || !Array.isArray(payload.args)) {
    error(socket, 'ساختار حرکت معتبر نیست.');
    return;
  }
  if (!isActionFromSeat(payload.action, payload.args, client.seat, room.players.length)) {
    error(socket, 'حرکت از این بازیکن یا با این اطلاعات مجاز نیست.', 'action_not_allowed');
    return;
  }
  for (const player of room.players) {
    if (player.seat !== client.seat) send(player.socket, { type: 'action', action: payload.action, args: payload.args, seat: client.seat });
  }
}

function buildRankedMastermindProgress(room) {
  const base = room.players.map(player => {
    const stat = room.mastermind.players.get(player.seat);
    return {
      seat: player.seat,
      username: player.username,
      status: stat.status,
      latestBlack: stat.latestBlack,
      attemptsUsed: stat.attemptsUsed,
      solveMs: stat.solveMs
    };
  });
  return rankMastermindPlayers(base).map(p => ({
    seat: p.seat,
    username: p.username,
    status: p.status,
    latest_black: p.latestBlack,
    attempts_used: p.attemptsUsed,
    solve_ms: p.solveMs,
    rank: p.rank
  }));
}

function allMastermindFinished(room) {
  return room.players.every(player => room.mastermind.players.get(player.seat).status !== 'active');
}

function handleMastermind(socket, client, payload) {
  const room = client.room;
  if (!room || room.game !== 'mastermind' || !room.mastermind) return;
  if (payload.type !== 'mastermind_guess') return error(socket, 'نوع پیام فکر بکر معتبر نیست.');
  const stat = room.mastermind.players.get(client.seat);
  if (!stat || stat.status !== 'active') return error(socket, 'مسابقه‌ی شما قبلاً تمام شده است.', 'race_finished');
  const now = Date.now();
  if (now - stat.lastGuessAt < 180) return error(socket, 'حدس‌ها بیش از حد سریع ارسال شدند.', 'rate_limited');
  stat.lastGuessAt = now;
  const guess = payload.guess;
  if (!Array.isArray(guess) || guess.length !== room.mastermind.codeLength || guess.some(v => !Number.isInteger(v) || v < 0 || v >= room.mastermind.colorCount)) {
    return error(socket, 'حدس نامعتبر است.');
  }
  const evaluated = evaluateMastermindGuess(room.mastermind.secret, guess);
  if (!evaluated) return error(socket, 'حدس نامعتبر است.');
  stat.attemptsUsed += 1;
  stat.latestBlack = evaluated.black;
  let solved = evaluated.black === room.mastermind.codeLength;
  let failed = false;
  if (solved) {
    stat.status = 'solved';
    stat.solveMs = Math.max(1, now - room.mastermind.startedAt);
  } else if (stat.attemptsUsed >= 10) {
    stat.status = 'failed';
    failed = true;
  }
  send(socket, {
    type: 'mastermind_feedback',
    guess,
    feedback: evaluated.feedback,
    black: evaluated.black,
    white: evaluated.white,
    attempt: stat.attemptsUsed,
    solved,
    failed,
    status: stat.status,
    solve_ms: stat.solveMs
  });
  const players = buildRankedMastermindProgress(room);
  for (const player of room.players) send(player.socket, { type: 'mastermind_progress', room_id: room.id, players });
  if (allMastermindFinished(room)) {
    for (const player of room.players) send(player.socket, { type: 'mastermind_race_over', room_id: room.id, players, secret: room.mastermind.secret });
  }
}

function handleMessage(socket, raw) {
  const client = clients.get(socket);
  if (!client) return;
  let payload;
  try { payload = JSON.parse(raw.toString()); }
  catch { return error(socket, 'پیام JSON معتبر نیست.'); }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload) || typeof payload.type !== 'string') {
    return error(socket, 'ساختار پیام نامعتبر است.');
  }
  switch (payload.type) {
    case 'join_queue': return joinQueue(socket, payload);
    case 'leave_queue': return leaveQueue(socket);
    case 'leave_match': return notifyRoomLeft(client, 'leave');
    case 'action': return sendActionToRoom(socket, payload);
    case 'emoji': {
      if (!client.room || client.state !== 'matched') return;
      const now = Date.now();
      if (now - client.lastEmojiAt < 900) return;
      if (!ALLOWED_EMOJIS.has(payload.emoji)) return;
      client.lastEmojiAt = now;
      for (const player of client.room.players) {
        if (player.seat !== client.seat) send(player.socket, { type: 'emoji', emoji: payload.emoji, seat: client.seat, username: client.username });
      }
      return;
    }
    case 'mastermind_guess': return handleMastermind(socket, client, payload);
    case 'restart_game': {
      const room = client.room;
      if (!room || client.seat !== 0) return error(socket, 'فقط میزبان می‌تواند بازی را از نو شروع کند.', 'not_host');
      if (payload.game !== room.game) return error(socket, 'بازی درخواست‌شده با اتاق یکی نیست.');
      room.seed = Number.isInteger(payload.seed) ? payload.seed : crypto.randomInt(1, 2_147_483_647);
      if (room.game === 'mastermind') room.mastermind = makeMastermindRoomState(room.players, room.mastermindDifficulty, Date.now());
      for (const player of room.players) {
        if (player.seat !== client.seat) send(player.socket, {
          type: 'restart_game', game: room.game, seed: room.seed,
          player_count: room.players.length,
          mastermind_difficulty: room.mastermindDifficulty,
          blockace_difficulty: room.blockaceDifficulty
        });
      }
      if (room.mastermind) sendProgress(room);
      return;
    }
    default: return error(socket, 'نوع پیام پشتیبانی نمی‌شود.');
  }
}

const httpServer = http.createServer((request, response) => {
  const url = new URL(request.url || '/', `http://${request.headers.host || 'localhost'}`);
  if (request.method === 'GET' && url.pathname === '/health') {
    const body = JSON.stringify({ ok: true, service: 'pendar-matchmaker', protocol: 2,
      waiting: [...queues.values()].reduce((total, queue) => total + queue.length, 0), rooms: rooms.size });
    response.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
    response.end(body);
    return;
  }
  response.writeHead(200, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
  response.end('Pendar Matchmaker is running. Connect to /ws.\n');
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

wss.on('connection', socket => {
  clients.set(socket, {
    socket, state: 'idle', username: 'بازیکن', game: null, queueKey: null,
    seat: -1, room: null, mastermindDifficulty: 3, blockaceDifficulty: 3, lastEmojiAt: 0,
    rating: 1000, globalRating: 1000, league: 0, joinedAt: 0, lastQueuedAt: 0
  });
  send(socket, { type: 'hello', protocol: 2, service: 'pendar-matchmaker' });
  socket.on('message', raw => handleMessage(socket, raw));
  socket.on('error', () => {});
  socket.on('close', () => {
    const client = clients.get(socket);
    if (!client) return;
    if (client.state === 'queued') detachFromQueue(socket);
    if (client.room) notifyRoomLeft(client, 'disconnect');
    clients.delete(socket);
  });
});

// Re-evaluate every waiting queue regularly so the accepted rating gap can widen even when nobody new joins.
const matchTick = setInterval(() => {
  for (const key of [...queues.keys()]) {
    if (queueFor(key).length) tryFormRooms(key, false, true);
  }
}, MATCH_TICK_MS);
matchTick.unref?.();

const heartbeat = setInterval(() => {
  for (const socket of wss.clients) {
    if (socket.readyState !== WebSocket.OPEN) continue;
    if (socket._mbAlive === false) { socket.terminate(); continue; }
    socket._mbAlive = false;
    socket.ping();
  }
}, 30000);
wss.on('connection', socket => {
  socket._mbAlive = true;
  socket.on('pong', () => { socket._mbAlive = true; });
});

httpServer.listen(PORT, '0.0.0.0', () => process.stdout.write(`Pendar Matchmaker listening on ${PORT}\n`));

function shutdown() {
  clearInterval(heartbeat);
  clearInterval(matchTick);
  for (const timer of queueTimers.values()) clearTimeout(timer);
  queueTimers.clear();
  for (const socket of wss.clients) socket.close(1001, 'server shutdown');
  httpServer.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5000).unref();
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
