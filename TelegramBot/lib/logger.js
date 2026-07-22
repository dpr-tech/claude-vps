// lib/logger.js
// Простое логирование вопросов/ответов в файл для отладки, плюс дублирование
// в stdout (его подхватит journald через systemd).

const fs = require('fs');
const path = require('path');
const config = require('../config');

function ensureLogDir() {
  fs.mkdirSync(path.dirname(config.logFile), { recursive: true });
}

function write(line) {
  ensureLogDir();
  const stamped = `[${new Date().toISOString()}] ${line}`;
  console.log(stamped);
  fs.appendFile(config.logFile, stamped + '\n', (err) => {
    if (err) console.error('Не удалось записать в лог-файл:', err.message);
  });
}

module.exports = {
  info: (msg) => write(`INFO  ${msg}`),
  warn: (msg) => write(`WARN  ${msg}`),
  error: (msg) => write(`ERROR ${msg}`),
};
