#!/bin/bash
# 01-server-setup.sh
# Запускать под root на чистом Ubuntu 24.04.
# Делает: новый пользователь -> SSH-хардненинг -> fail2ban -> базовый ufw -> Node.js -> Claude Code.
# Останавливается перед `claude login` — это ручной шаг (см. README).

set -euo pipefail
CURRENT_STEP="инициализация"
trap 'echo; echo "ОШИБКА на этапе: $CURRENT_STEP" >&2; echo "Команда завершилась с ошибкой — вывод выше содержит причину. Разберитесь и запустите скрипт заново, он безопасно повторяет уже выполненные шаги." >&2' ERR

if [[ $EUID -ne 0 ]]; then
  echo "Этот скрипт нужно запускать под root (первый вход на чистый сервер)." >&2
  exit 1
fi

SERVER_IP="$(curl -s -4 ifconfig.me 2>/dev/null || echo '<IP-сервера>')"

echo "============================================================"
echo "01-server-setup.sh — базовая настройка сервера, 6 шагов:"
echo "  1) новый пользователь          4) fail2ban"
echo "  2) перенос SSH-ключа           5) базовый firewall (ufw)"
echo "  3) SSH-хардненинг              6) Node.js + Claude Code"
echo "На шаге 3 скрипт остановится и попросит вас проверить доступ"
echo "под новым пользователем в отдельном окне терминала."
echo "============================================================"
echo

echo "=== Шаг 1/6: новый пользователь ==="
CURRENT_STEP="Шаг 1/6: новый пользователь"
read -rp "Имя нового пользователя [myuser]: " NEW_USER
NEW_USER="${NEW_USER:-myuser}"

if id "$NEW_USER" &>/dev/null; then
  echo "Пользователь $NEW_USER уже существует — пропускаю создание."
else
  adduser --disabled-password --gecos "" "$NEW_USER"
  usermod -aG sudo "$NEW_USER"
  echo "Пользователь $NEW_USER создан и добавлен в sudo."
fi

echo "=== Шаг 2/6: перенос SSH-ключа ==="
CURRENT_STEP="Шаг 2/6: перенос SSH-ключа"
SRC_AUTH_KEYS="/root/.ssh/authorized_keys"
DST_SSH_DIR="/home/$NEW_USER/.ssh"
DST_AUTH_KEYS="$DST_SSH_DIR/authorized_keys"

if [[ ! -f "$SRC_AUTH_KEYS" ]]; then
  echo "Не найден $SRC_AUTH_KEYS — похоже, вы ещё не добавили свой SSH-ключ для root." >&2
  echo "Добавьте ключ в /root/.ssh/authorized_keys и запустите скрипт заново." >&2
  exit 1
fi

mkdir -p "$DST_SSH_DIR"
cp "$SRC_AUTH_KEYS" "$DST_AUTH_KEYS"
chown -R "$NEW_USER:$NEW_USER" "$DST_SSH_DIR"
chmod 700 "$DST_SSH_DIR"
chmod 600 "$DST_AUTH_KEYS"
echo "SSH-ключ перенесён в $DST_AUTH_KEYS."

echo
echo "=== ОБЯЗАТЕЛЬНАЯ ПРОВЕРКА ДОСТУПА ==="
echo "Откройте НОВОЕ окно терминала и выполните (не закрывая текущую сессию root!):"
echo
echo "    ssh $NEW_USER@$SERVER_IP"
echo "    sudo whoami   # должно вывести: root"
echo
echo "Ключ на новом пользователе — тот же, что уже работает у вас для root"
echo "(мы скопировали именно его), поэтому SSH должен подключиться без"
echo "дополнительных флагов, теми же учётными данными, что вы используете"
echo "сейчас. Если подключение не пройдёт автоматически — укажите путь"
echo "к ключу явно: ssh -i ~/.ssh/id_ed25519 $NEW_USER@$SERVER_IP"
echo "(или ~/.ssh/id_rsa, если генерировали ключ другого типа)."
echo "Пароль по паролю тоже пока работает (мы его ещё не отключили) —"
echo "можно войти паролем, который вы задали командой adduser выше."
echo
read -rp "Подтвердите, что вход под $NEW_USER сработал (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Остановлено. Разберитесь со входом под $NEW_USER, прежде чем продолжать — SSH-хардненинг ещё не применялся, доступ по root и паролю пока не тронут." >&2
  exit 1
fi

echo "=== Шаг 3/6: SSH-хардненинг ==="
CURRENT_STEP="Шаг 3/6: SSH-хардненинг"
SSHD_CONFIG="/etc/ssh/sshd_config"
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
systemctl restart ssh 2>/dev/null || systemctl restart sshd
echo "Вход по паролю и прямой root-логин отключены."

echo "=== Шаг 4/6: fail2ban ==="
CURRENT_STEP="Шаг 4/6: fail2ban"
apt update -qq
apt install -y fail2ban
systemctl enable --now fail2ban
echo "fail2ban установлен и включён."

echo "=== Шаг 5/6: базовый ufw ==="
CURRENT_STEP="Шаг 5/6: базовый ufw"
ufw allow 22/tcp
ufw --force enable
echo "ufw включён, разрешён порт 22."

echo "=== Шаг 6/6: Node.js 22 и Claude Code ==="
CURRENT_STEP="Шаг 6/6: Node.js и Claude Code"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs
npm install -g @anthropic-ai/claude-code
echo "Установлено: $(claude --version 2>/dev/null || echo 'claude --version не сработал, проверьте вручную')"

echo
echo "============================================================"
echo "Готово. Дальше — вручную:"
echo "1. Зайдите на сервер под пользователем $NEW_USER (root по SSH больше недоступен):"
echo "     ssh $NEW_USER@$SERVER_IP"
echo "2. Выполните: claude"
echo "   — выберите вход через Claude account, авторизуйтесь (см. README про VPN)."
echo "3. После успешного логина запустите: ./scripts/02-webpanel-setup.sh"
echo "============================================================"
