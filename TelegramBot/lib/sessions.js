// lib/sessions.js
// Хранит session_id Claude Code для каждого Telegram-чата в JSON-файле
// (WORK_DIR/sessions.json). /new сбрасывает сессию конкретного чата.

const fs = require('fs');
const config = require('../config');
const logger = require('./logger');

let cache = null;

function load() {
  if (cache) return cache;
  try {
    const raw = fs.readFileSync(config.sessionsFile, 'utf8');
    cache = JSON.parse(raw);
  } catch (err) {
    if (err.code !== 'ENOENT') {
      logger.warn(`Не удалось прочитать sessions.json, начинаю с чистого листа: ${err.message}`);
    }
    cache = {};
  }
  return cache;
}

function persist() {
  fs.mkdirSync(require('path').dirname(config.sessionsFile), { recursive: true });
  fs.writeFileSync(config.sessionsFile, JSON.stringify(cache, null, 2));
}

function getSession(chatId) {
  return load()[String(chatId)] || null;
}

function setSession(chatId, sessionId) {
  load()[String(chatId)] = sessionId;
  persist();
}

function resetSession(chatId) {
  const data = load();
  delete data[String(chatId)];
  persist();
}

module.exports = { getSession, setSession, resetSession };
