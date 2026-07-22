// lib/claude.js
// Обёртка над headless-режимом Claude Code (`claude -p`).
//
// ВАЖНО, проверить на реальном сервере перед первым продакшн-запуском:
// флаги ниже (--output-format json, --resume, --allowedTools) соответствуют
// задокументированному поведению Claude Code CLI на момент написания, но
// именно версия, установленная 01-server-setup.sh на сервере, — источник
// истины. Сверить командой `claude --help` и `claude -p --help` на сервере;
// при расхождении поправить buildArgs() ниже. Флаг --allowedTools — это
// единственный механизм, который не даёт боту менять файлы или выполнять
// команды на сервере, так что перед реальным использованием стоит один раз
// вручную проверить, что Bash и Write из чата бота действительно недоступны.

const { spawn } = require('child_process');
const config = require('../config');
const logger = require('./logger');

function buildArgs({ prompt, sessionId }) {
  const args = ['-p', prompt, '--output-format', 'json'];
  if (sessionId) {
    args.push('--resume', sessionId);
  }
  for (const tool of config.allowedTools) {
    args.push('--allowedTools', tool);
  }
  return args;
}

/**
 * Отправляет промпт в Claude Code и ждёт ответа.
 * @returns {Promise<{text: string, sessionId: string}>}
 */
function ask({ prompt, sessionId, cwd }) {
  const args = buildArgs({ prompt, sessionId });

  return new Promise((resolve, reject) => {
    const child = spawn(config.claudeBin, args, {
      cwd: cwd || config.workDir,
      env: process.env,
    });

    let stdout = '';
    let stderr = '';
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGKILL');
    }, config.requestTimeoutMs);

    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });

    child.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });

    child.on('close', (code) => {
      clearTimeout(timer);

      if (timedOut) {
        return reject(new Error(`Claude Code не ответил за ${config.requestTimeoutMs} мс — прервано по таймауту`));
      }
      if (code !== 0) {
        return reject(new Error(`claude завершился с кодом ${code}: ${stderr.trim() || '(пусто)'}`));
      }

      try {
        const parsed = JSON.parse(stdout);
        // Формат ответа claude -p --output-format json: поле с текстом
        // может называться result/response в зависимости от версии —
        // подстраховываемся несколькими вариантами.
        const text = parsed.result ?? parsed.response ?? parsed.text ?? JSON.stringify(parsed);
        const newSessionId = parsed.session_id ?? parsed.sessionId ?? sessionId;
        resolve({ text: String(text), sessionId: newSessionId });
      } catch (err) {
        // Если JSON не распарсился — отдаём как есть, лучше сырой текст,
        // чем молчаливая ошибка.
        logger.warn(`Не удалось разобрать JSON-ответ claude, отдаю как есть: ${err.message}`);
        resolve({ text: stdout.trim() || '(пустой ответ)', sessionId });
      }
    });
  });
}

module.exports = { ask };
