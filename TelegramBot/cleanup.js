// cleanup.js
// Удаляет файлы из WORK_DIR/incoming старше TEMP_FILE_TTL_HOURS.
// Запускается systemd-таймером (telegram-bot-cleanup.timer), раз в сутки.
// Можно запустить и вручную: `node cleanup.js`.

const fs = require('fs');
const path = require('path');
const config = require('./config');
const log = require('./lib/logger');

function walk(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }
  const files = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walk(full));
    } else {
      files.push(full);
    }
  }
  return files;
}

function removeEmptyDirs(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    if (entry.isDirectory()) {
      const full = path.join(dir, entry.name);
      removeEmptyDirs(full);
      if (fs.readdirSync(full).length === 0) {
        fs.rmdirSync(full);
      }
    }
  }
}

function main() {
  const ttlMs = config.tempFileTtlHours * 60 * 60 * 1000;
  const cutoff = Date.now() - ttlMs;
  const files = walk(config.incomingDir);

  let removed = 0;
  for (const file of files) {
    const stat = fs.statSync(file);
    if (stat.mtimeMs < cutoff) {
      fs.unlinkSync(file);
      removed++;
    }
  }
  removeEmptyDirs(config.incomingDir);

  log.info(`Очистка временных файлов: удалено ${removed} из ${files.length} (старше ${config.tempFileTtlHours}ч).`);
}

main();
