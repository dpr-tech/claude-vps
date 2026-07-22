// lib/diskspace.js
// Проверка свободного места на разделе, где лежит WORK_DIR, через `df`.
// Используется перед обработкой файлов, чтобы не упасть посередине записи.

const { execFile } = require('child_process');
const config = require('../config');

function getFreeSpaceMb() {
  return new Promise((resolve, reject) => {
    // -P — POSIX-формат вывода (стабильные колонки), -k — блоки по 1К
    execFile('df', ['-Pk', config.workDir], (err, stdout) => {
      if (err) return reject(err);
      const lines = stdout.trim().split('\n');
      const dataLine = lines[lines.length - 1];
      const columns = dataLine.trim().split(/\s+/);
      const availableKb = parseInt(columns[3], 10);
      if (!Number.isFinite(availableKb)) {
        return reject(new Error(`Не удалось разобрать вывод df: "${dataLine}"`));
      }
      resolve(Math.floor(availableKb / 1024));
    });
  });
}

async function hasEnoughSpace() {
  const freeMb = await getFreeSpaceMb();
  return { ok: freeMb >= config.minFreeSpaceMb, freeMb };
}

module.exports = { getFreeSpaceMb, hasEnoughSpace };
