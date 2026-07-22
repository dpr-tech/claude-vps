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

const config = {
  telegramToken: required('TELEGRAM_BOT_TOKEN'),
  allowedUserId: parseInt(required('ALLOWED_USER_ID'), 10),
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
