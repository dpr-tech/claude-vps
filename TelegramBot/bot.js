// bot.js
// Точка входа. Telegram-бот как интерфейс к Claude Code на VPS.
// Разрешённые пользователи — ALLOWED_USER_IDS. Остальным бот не отвечает
// вообще (см. telegram-bot-requirements.md). Каждый разрешённый пользователь
// получает свою собственную сессию/контекст (ключ — chat id).

const fs = require('fs');
const path = require('path');
const https = require('https');
const { Telegraf } = require('telegraf');

const config = require('./config');
const claude = require('./lib/claude');
const sessions = require('./lib/sessions');
const diskspace = require('./lib/diskspace');
const log = require('./lib/logger');

const TELEGRAM_MESSAGE_LIMIT = 4096;

fs.mkdirSync(config.workDir, { recursive: true });
fs.mkdirSync(config.incomingDir, { recursive: true });

const bot = new Telegraf(config.telegramToken);

// --- Доступ: отвечаем только из списка разрешённых, остальным — тишина ---
bot.use(async (ctx, next) => {
  const userId = ctx.from && ctx.from.id;
  if (!config.allowedUserIds.includes(userId)) {
    if (userId) {
      log.warn(`Отклонён запрос от чужого user_id=${userId} (username=${ctx.from.username || '—'})`);
    }
    return; // намеренно без ответа
  }
  return next();
});

function splitMessage(text) {
  const parts = [];
  let rest = text;
  while (rest.length > TELEGRAM_MESSAGE_LIMIT) {
    let cut = rest.lastIndexOf('\n', TELEGRAM_MESSAGE_LIMIT);
    if (cut <= 0) cut = TELEGRAM_MESSAGE_LIMIT;
    parts.push(rest.slice(0, cut));
    rest = rest.slice(cut);
  }
  if (rest.length) parts.push(rest);
  return parts;
}

async function replyLong(ctx, text) {
  for (const part of splitMessage(text)) {
    await ctx.reply(part);
  }
}

async function runPrompt(ctx, prompt) {
  const chatId = ctx.chat.id;
  const sessionId = sessions.getSession(chatId);

  const stopTyping = startTypingIndicator(ctx);
  try {
    log.info(`chat=${chatId} -> запрос: ${prompt.slice(0, 200).replace(/\n/g, ' ')}`);
    const result = await claude.ask({ prompt, sessionId, cwd: config.workDir });
    if (result.sessionId) sessions.setSession(chatId, result.sessionId);
    log.info(`chat=${chatId} <- ответ (${result.text.length} симв.)`);
    await replyLong(ctx, result.text || '(пустой ответ от Claude Code)');
  } catch (err) {
    log.error(`chat=${chatId} ошибка: ${err.message}`);
    await ctx.reply(`Ошибка при обращении к Claude Code: ${err.message}`);
  } finally {
    stopTyping();
  }
}

function startTypingIndicator(ctx) {
  ctx.sendChatAction('typing').catch(() => {});
  const interval = setInterval(() => {
    ctx.sendChatAction('typing').catch(() => {});
  }, 4500); // Telegram сам гасит индикатор через ~5с
  return () => clearInterval(interval);
}

bot.command('start', (ctx) => ctx.reply(
  'Готов. Пиши вопрос, присылай файлы или картинки — передам в Claude Code.\n' +
  '/new — начать новую сессию (сбросить контекст).'
));

bot.command('new', (ctx) => {
  sessions.resetSession(ctx.chat.id);
  return ctx.reply('Контекст сброшен, начинаем новую сессию.');
});

bot.on('text', async (ctx) => {
  const text = ctx.message.text.trim();
  if (!text || text.startsWith('/')) return;
  await runPrompt(ctx, text);
});

async function downloadTelegramFile(ctx, fileId, suggestedName) {
  const link = await ctx.telegram.getFileLink(fileId);
  const safeName = suggestedName.replace(/[^\w.\-]+/g, '_');
  const chatDir = path.join(config.incomingDir, String(ctx.chat.id));
  fs.mkdirSync(chatDir, { recursive: true });
  const destPath = path.join(chatDir, `${Date.now()}-${safeName}`);

  await new Promise((resolve, reject) => {
    const file = fs.createWriteStream(destPath);
    https.get(link.href, (response) => {
      if (response.statusCode !== 200) {
        reject(new Error(`Не удалось скачать файл из Telegram: HTTP ${response.statusCode}`));
        return;
      }
      response.pipe(file);
      file.on('finish', () => file.close(resolve));
    }).on('error', reject);
  });

  return destPath;
}

async function handleIncomingFile(ctx, fileId, suggestedName, captionPrompt) {
  const { ok, freeMb } = await diskspace.hasEnoughSpace();
  if (!ok) {
    await ctx.reply(
      `Мало места на диске (свободно ${freeMb} МБ, порог ${config.minFreeSpaceMb} МБ) — ` +
      'файл не принимаю. Освободи место на сервере и попробуй снова.'
    );
    return;
  }

  await ctx.reply('Файл получен, сохраняю...');
  let filePath;
  try {
    filePath = await downloadTelegramFile(ctx, fileId, suggestedName);
  } catch (err) {
    log.error(`Не удалось скачать файл: ${err.message}`);
    await ctx.reply(`Не удалось скачать файл: ${err.message}`);
    return;
  }

  const prompt = captionPrompt
    ? `${captionPrompt}\n\nФайл для анализа: ${filePath}`
    : `Проанализируй файл: ${filePath}`;
  await runPrompt(ctx, prompt);
}

bot.on('document', async (ctx) => {
  const doc = ctx.message.document;
  await handleIncomingFile(ctx, doc.file_id, doc.file_name || 'document', ctx.message.caption);
});

bot.on('photo', async (ctx) => {
  const photos = ctx.message.photo;
  const best = photos[photos.length - 1]; // самое большое разрешение
  await handleIncomingFile(ctx, best.file_id, 'photo.jpg', ctx.message.caption);
});

bot.catch((err, ctx) => {
  log.error(`Необработанная ошибка в апдейте ${ctx.updateType}: ${err.message}`);
});

bot.launch().then(() => {
  log.info('Бот запущен.');
});

process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
