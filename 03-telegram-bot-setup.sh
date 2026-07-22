#!/bin/bash
# 03-telegram-bot-setup.sh
# Запускать под обычным пользователем (не root), ПОСЛЕ 01-server-setup.sh
# (нужен установленный node и claude).
# Делает: изолированная директория для данных бота -> .env -> npm install ->
# systemd-служба бота + systemd-таймер очистки временных файлов.

set -euo pipefail
CURRENT_STEP="инициализация"
trap 'echo; echo "ОШИБКА на этапе: $CURRENT_STEP" >&2; echo "Команда завершилась с ошибкой — вывод выше содержит причину. Разберитесь и запустите скрипт заново, он безопасно повторяет уже выполненные шаги." >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR"
BOT_DIR="$SCRIPT_DIR/TelegramBot"

if [[ $EUID -eq 0 ]]; then
  echo "Этот скрипт нужно запускать НЕ под root, а под обычным пользователем." >&2
  exit 1
fi

if ! command -v node &>/dev/null; then
  echo "Не найден node — похоже, 01-server-setup.sh ещё не был выполнен." >&2
  exit 1
fi

if ! command -v claude &>/dev/null; then
  echo "Не найдена команда 'claude' — похоже, 01-server-setup.sh ещё не был выполнен (или PATH не подхватил ~/.npm-global/bin)." >&2
  exit 1
fi

if [[ ! -d "$BOT_DIR" ]]; then
  echo "Не найдена папка $BOT_DIR — запускайте скрипт из корня репозитория claude-vps." >&2
  exit 1
fi

CURRENT_USER="$(whoami)"
NODE_BIN="$(command -v node)"

echo "============================================================"
echo "03-telegram-bot-setup.sh — Telegram-бот, 6 шагов:"
echo "  1) проверка окружения          4) npm install"
echo "  2) изолированная директория    5) systemd (служба + таймер очистки)"
echo "  3) .env (токен, user id)       6) финальная проверка"
echo "============================================================"
echo

echo "=== Шаг 1/6: окружение ==="
CURRENT_STEP="Шаг 1/6: окружение"
echo "node: $NODE_BIN ($(node --version))"
echo "claude: $(command -v claude)"

echo "=== Шаг 2/6: изолированная рабочая директория ==="
CURRENT_STEP="Шаг 2/6: рабочая директория"
WORK_DIR="$HOME/telegram-bot-data"
mkdir -p "$WORK_DIR/incoming"
chmod 700 "$WORK_DIR"
echo "Данные бота (входящие файлы, файл сессий, лог) будут в $WORK_DIR"
echo "— отдельно от домашней папки с SSH-ключами и конфигами."

echo "=== Шаг 3/6: .env ==="
CURRENT_STEP="Шаг 3/6: .env"
ENV_FILE="$BOT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  echo ".env уже существует ($ENV_FILE) — не трогаю, чтобы не затереть текущий токен."
  echo "Чтобы поменять токен/ID/пороги вручную — отредактируйте файл и перезапустите службу:"
  echo "  sudo systemctl restart telegram-bot"
else
  echo "Токен бота от @BotFather. Если ещё не создавали — напишите @BotFather в Telegram,"
  echo "/newbot, дайте имя, получите токен. Можно оставить пустым и вписать в .env позже —"
  echo "тогда служба бота будет создана, но не запущена автоматически."
  read -rp "TELEGRAM_BOT_TOKEN [пусто, впишу позже]: " BOT_TOKEN
  echo "Твой числовой Telegram user ID — единственный, кому бот будет отвечать."
  echo "Узнать: написать @userinfobot в Telegram, он пришлёт ID в ответ."
  read -rp "ALLOWED_USER_ID [пусто, впишу позже]: " ALLOWED_USER_ID

  cat > "$ENV_FILE" <<EOF
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
ALLOWED_USER_ID=$ALLOWED_USER_ID
CLAUDE_BIN=$(command -v claude)
WORK_DIR=$WORK_DIR
LOG_FILE=$WORK_DIR/bot.log
REQUEST_TIMEOUT_MS=180000
MIN_FREE_SPACE_MB=1024
TEMP_FILE_TTL_HOURS=72
EOF
  chmod 600 "$ENV_FILE"
  echo "Создан $ENV_FILE (chmod 600)."
fi

echo "=== Шаг 4/6: npm install ==="
CURRENT_STEP="Шаг 4/6: npm install"
(cd "$BOT_DIR" && npm install --omit=dev)
echo "Зависимости установлены."

echo "=== Шаг 5/6: systemd — служба и таймер очистки ==="
CURRENT_STEP="Шаг 5/6: systemd"

sed -e "s|{{USER}}|$CURRENT_USER|g" \
    -e "s|{{BOT_DIR}}|$BOT_DIR|g" \
    -e "s|{{NODE_BIN}}|$NODE_BIN|g" \
    "$TEMPLATES_DIR/telegram-bot.service.template" | sudo tee /etc/systemd/system/telegram-bot.service > /dev/null

sed -e "s|{{USER}}|$CURRENT_USER|g" \
    -e "s|{{BOT_DIR}}|$BOT_DIR|g" \
    -e "s|{{NODE_BIN}}|$NODE_BIN|g" \
    "$TEMPLATES_DIR/telegram-bot-cleanup.service.template" | sudo tee /etc/systemd/system/telegram-bot-cleanup.service > /dev/null

sudo cp "$TEMPLATES_DIR/telegram-bot-cleanup.timer.template" /etc/systemd/system/telegram-bot-cleanup.timer

sudo systemctl daemon-reload
sudo systemctl enable --now telegram-bot-cleanup.timer
echo "Таймер очистки временных файлов включён (раз в сутки, TTL из .env)."

TOKEN_SET="$(grep -q '^TELEGRAM_BOT_TOKEN=.\+' "$ENV_FILE" && echo yes || echo no)"
USERID_SET="$(grep -q '^ALLOWED_USER_ID=.\+' "$ENV_FILE" && echo yes || echo no)"

if [[ "$TOKEN_SET" == "yes" && "$USERID_SET" == "yes" ]]; then
  sudo systemctl enable --now telegram-bot
  echo "Служба telegram-bot запущена."
else
  echo "TELEGRAM_BOT_TOKEN и/или ALLOWED_USER_ID пустые в $ENV_FILE — служба telegram-bot"
  echo "создана, но НЕ запущена. Заполните .env и выполните:"
  echo "  sudo systemctl enable --now telegram-bot"
fi

echo "=== Шаг 6/6: финальная проверка ==="
CURRENT_STEP="Шаг 6/6: финальная проверка"
echo "--- Служба telegram-bot ---"
sudo systemctl status telegram-bot --no-pager -l 2>/dev/null | head -5 || echo "(ещё не запущена)"
echo "--- Таймер telegram-bot-cleanup ---"
sudo systemctl list-timers telegram-bot-cleanup.timer --no-pager 2>/dev/null || true

echo
echo "============================================================"
echo "Готово. Данные бота: $WORK_DIR"
echo "Логи бота:  sudo journalctl -u telegram-bot -f"
echo "Логи очистки: sudo journalctl -u telegram-bot-cleanup -f"
echo "Перезапуск после правки .env: sudo systemctl restart telegram-bot"
echo "============================================================"
