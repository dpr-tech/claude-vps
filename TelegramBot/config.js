// config.js
// Читает .env, проверяет обязательные переменные, отдаёт готовый объект
// конфигурации остальному коду. Никаких секретов с дефолтами — если
// TELEGRAM_BOT_TOKEN или ALLOWED_USER_ID не заданы, падаем сразу и явно,
// а не на первом сообщении в чате.

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

function required(name) {
  const value = process.env[name];
  if (!value) {
    console.error(`Не задана обязательная переменная окружения: ${name} (см. .env.example)`);
    process.exit(1);
  }
  return value;
}

function intFromEnv(name, defaultValue) {
  const raw = process.env[name];
  if (!raw) return defaultValue;
  const parsed = parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : defaultValue;
}

function parseAllowedUserIds() {
  // ALLOWED_USER_IDS — новый формат, список через запятую ("111,222").
  // ALLOWED_USER_ID — старый формат (один ID), поддерживаем для совместимости
  // с уже развёрнутыми .env, чтобы обновление кода не роняло бота.
  const raw = process.env.ALLOWED_USER_IDS || process.env.ALLOWED_USER_ID;
  if (!raw) {
    console.error('Не задана ни ALLOWED_USER_IDS, ни ALLOWED_USER_ID (см. .env.example)');
    process.exit(1);
  }
  const ids = raw
    .split(',')
    .map((s) => parseInt(s.trim(), 10))
    .filter((n) => Number.isFinite(n));
  if (ids.length === 0) {
    console.error(`ALLOWED_USER_IDS/ALLOWED_USER_ID не удалось разобрать: "${raw}"`);
    process.exit(1);
  }
  return ids;
}

const config = {
  telegramToken: required('TELEGRAM_BOT_TOKEN'),
  allowedUserIds: parseAllowedUserIds(),
  claudeBin: process.env.CLAUDE_BIN || 'claude',
  workDir: process.env.WORK_DIR || path.join(__dirname, 'data'),
  logFile: process.env.LOG_FILE || path.join(__dirname, 'data', 'bot.log'),
  requestTimeoutMs: intFromEnv('REQUEST_TIMEOUT_MS', 180000),
  minFreeSpaceMb: intFromEnv('MIN_FREE_SPACE_MB', 1024),
  tempFileTtlHours: intFromEnv('TEMP_FILE_TTL_HOURS', 72),
  // Инструменты, разрешённые Claude Code внутри сессий бота. Bash и запись
  // файлов сюда намеренно не входят — см. telegram-bot-requirements.md.
  allowedTools: ['Read', 'Grep', 'Glob', 'WebSearch'],
};

config.incomingDir = path.join(config.workDir, 'incoming');
config.sessionsFile = path.join(config.workDir, 'sessions.json');

module.exports = config;
