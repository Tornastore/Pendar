'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const path = require('node:path');
const { WebSocket } = require('ws');

const PORT = 38000 + Math.floor(Math.random() * 1000);

function startServer() {
  const child = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], {
    env: { ...process.env, PORT: String(PORT) }, stdio: ['ignore', 'pipe', 'inherit']
  });
  return new Promise((resolve, reject) => {
    child.stdout.on('data', chunk => { if (String(chunk).includes('listening')) resolve(child); });
    child.on('error', reject);
    setTimeout(() => reject(new Error('server did not start')), 5000).unref();
  });
}

function connect() {
  const socket = new WebSocket(`ws://127.0.0.1:${PORT}/ws`);
  const inbox = [];
  const waiters = [];
  socket.on('message', raw => {
    const message = JSON.parse(raw.toString());
    const index = waiters.findIndex(w => w.type === message.type);
    if (index >= 0) waiters.splice(index, 1)[0].resolve(message);
    else inbox.push(message);
  });
  const ready = new Promise(resolve => socket.on('open', resolve));
  return {
    socket, ready,
    send: payload => socket.send(JSON.stringify(payload)),
    next: (type, ms = 4000) => new Promise((resolve, reject) => {
      const found = inbox.findIndex(m => m.type === type);
      if (found >= 0) return resolve(inbox.splice(found, 1)[0]);
      const waiter = { type, resolve };
      waiters.push(waiter);
      setTimeout(() => reject(new Error(`timeout waiting for ${type}`)), ms).unref();
    }),
    close: () => socket.close()
  };
}

test('pairs by closest rating and reports opponent strength', async () => {
  const server = await startServer();
  const clients = [];
  try {
    const mk = async (name, rating, league) => {
      const c = connect();
      await c.ready;
      clients.push(c);
      c.send({ type: 'join_queue', game: 'chess', username: name, rating, global_rating: rating + 10, league });
      return c;
    };
    const a = await mk('الف', 1000, 2);
    const b = await mk('ب', 1600, 5);
    const c = await mk('ج', 1060, 3);
    const foundA = await a.next('match_found');
    const foundC = await c.next('match_found');
    assert.equal(foundA.opponent_username, 'ج');
    assert.equal(foundC.opponent_username, 'الف');
    assert.equal(foundA.opponent_rating, 1060);
    assert.equal(foundA.opponent_global_rating, 1070);
    assert.equal(foundA.opponent_league, 3);
    assert.equal(foundC.opponent_rating, 1000);
    assert.equal(foundA.players.length, 2);
    assert.equal(typeof foundA.players[0].rating, 'number');
    const queued = await b.next('queued');
    assert.equal(queued.game, 'chess');
    assert.equal(queued.search_range, 100);
  } finally {
    clients.forEach(c => c.close());
    server.kill();
  }
});

test('hostile rating values are clamped', async () => {
  const server = await startServer();
  const clients = [];
  try {
    const a = connect(); const b = connect();
    clients.push(a, b);
    await Promise.all([a.ready, b.ready]);
    a.send({ type: 'join_queue', game: 'othello', username: 'x', rating: 9999999, global_rating: 'NaN', league: 99 });
    b.send({ type: 'join_queue', game: 'othello', username: 'y', rating: 3000, global_rating: 3000, league: 7 });
    const found = await a.next('match_found');
    assert.equal(found.opponent_rating, 3000);
    assert.equal(found.opponent_league, 7);
  } finally {
    clients.forEach(c => c.close());
    server.kill();
  }
});
