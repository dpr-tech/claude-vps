#!/bin/bash
# 02-webpanel-setup.sh
# Запускать под обычным пользователем (не root) ПОСЛЕ ручного `claude login`.
# Делает: CloudCLI -> systemd-служба -> Caddy (авто-HTTPS) -> ufw 80/443 -> проверка.

set -euo pipefail
CURRENT_STEP="инициализация"
trap 'echo; echo "ОШИБКА на этапе: $CURRENT_STEP" >&2; echo "Команда завершилась с ошибкой — вывод выше содержит причину. Разберитесь и запустите скрипт заново, он безопасно повторяет уже выполненные шаги." >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$REPO_ROOT/templates"

if [[ $EUID -eq 0 ]]; then
  echo "Этот скрипт нужно запускать НЕ под root, а под обычным пользователем с sudo." >&2
  exit 1
fi

if [[ ! -d "$HOME/.claude" ]]; then
  echo "Не найдена папка ~/.claude — похоже, вы ещё не выполнили 'claude login'." >&2
  echo "Запустите 'claude', авторизуйтесь, и только потом повторите этот скрипт." >&2
  exit 1
fi

echo "============================================================"
echo "02-webpanel-setup.sh — веб-панель, 6 шагов:"
echo "  1) CloudCLI                    4) firewall (80/443)"
echo "  2) systemd-служба панели       5) проверка SSH-хардненинга"
echo "  3) Caddy (авто-HTTPS)          6) финальная проверка служб"
echo "============================================================"
echo

echo "=== Домен ==="
read -rp "Домен для панели (вида claude.ваш-домен.ru): " DOMAIN
if [[ -z "$DOMAIN" || ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo "Домен пустой или выглядит некорректно. Проверьте и запустите скрипт заново." >&2
  exit 1
fi

CURRENT_USER="$(whoami)"

echo "=== Шаг 1/6: CloudCLI ==="
CURRENT_STEP="Шаг 1/6: CloudCLI"
if command -v cloudcli &>/dev/null; then
  echo "CloudCLI уже установлен, переустанавливаю на актуальную версию."
fi
sudo npm install -g @cloudcli-ai/cloudcli
CLOUDCLI_BIN="$(command -v cloudcli || true)"
if [[ -z "$CLOUDCLI_BIN" ]]; then
  echo "Команда cloudcli не найдена после установки — проверьте вывод npm выше." >&2
  exit 1
fi
echo "CloudCLI установлен: $CLOUDCLI_BIN"

echo "=== Шаг 2/6: systemd-служба ==="
CURRENT_STEP="Шаг 2/6: systemd-служба"
if [[ ! -f "$TEMPLATES_DIR/cloudcli.service.template" ]]; then
  echo "Не найден шаблон $TEMPLATES_DIR/cloudcli.service.template" >&2
  exit 1
fi
sed -e "s|{{USER}}|$CURRENT_USER|g" \
    -e "s|{{HOME}}|$HOME|g" \
    -e "s|{{CLOUDCLI_BIN}}|$CLOUDCLI_BIN|g" \
    "$TEMPLATES_DIR/cloudcli.service.template" | sudo tee /etc/systemd/system/cloudcli.service > /dev/null

sudo systemctl daemon-reload
sudo systemctl enable --now cloudcli
echo "Служба cloudcli запущена (слушает 127.0.0.1:3001)."

echo "=== Шаг 3/6: Caddy ==="
CURRENT_STEP="Шаг 3/6: установка Caddy"
if command -v caddy &>/dev/null; then
  echo "Caddy уже установлен, пропускаю установку — просто обновлю конфиг."
else
  sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sSLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sSLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
  sudo apt update -qq
  sudo apt install -y caddy
fi

if [[ ! -f "$TEMPLATES_DIR/Caddyfile.template" ]]; then
  echo "Не найден шаблон $TEMPLATES_DIR/Caddyfile.template" >&2
  exit 1
fi
sed "s|{{DOMAIN}}|$DOMAIN|g" "$TEMPLATES_DIR/Caddyfile.template" | sudo tee /etc/caddy/Caddyfile > /dev/null
sudo systemctl reload caddy || sudo systemctl restart caddy
echo "Caddy настроен на домен $DOMAIN, сертификат будет получен автоматически."

echo "=== Шаг 4/6: firewall ==="
CURRENT_STEP="Шаг 4/6: firewall (80/443)"
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
echo "ufw: разрешены 80 и 443."

echo "=== Шаг 5/6: проверка SSH-хардненинга (на случай, если скрипт 01 не запускался) ==="
CURRENT_STEP="Шаг 5/6: проверка SSH-хардненинга"
PW_AUTH="$(sudo grep -i '^PasswordAuthentication' /etc/ssh/sshd_config || echo 'не задано')"
ROOT_LOGIN="$(sudo grep -i '^PermitRootLogin' /etc/ssh/sshd_config || echo 'не задано')"
if [[ "$PW_AUTH" != *"no"* || "$ROOT_LOGIN" != *"no"* ]]; then
  echo "Вход по паролю и/или root-логин ещё не отключены (текущее: $PW_AUTH / $ROOT_LOGIN)."
  read -rp "Отключить сейчас? Перед этим подтвердите, что вход под $CURRENT_USER по SSH-ключу работает (yes/no): " HARDEN_NOW
  if [[ "$HARDEN_NOW" == "yes" ]]; then
    sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd
    echo "Готово."
  else
    echo "Пропущено — не забудьте сделать это вручную позже."
  fi
fi
if ! systemctl is-active --quiet fail2ban; then
  sudo apt install -y fail2ban
  sudo systemctl enable --now fail2ban
  echo "fail2ban установлен и включён."
fi

echo "=== Шаг 6/6: финальная проверка ==="
CURRENT_STEP="Шаг 6/6: финальная проверка"
echo "--- Служба cloudcli ---"
sudo systemctl status cloudcli --no-pager -l | head -5 || true
echo "--- Служба caddy ---"
sudo systemctl status caddy --no-pager -l | head -5 || true
echo
echo "Открытые порты:"
sudo ss -tulpn || true
echo
sudo ufw status || true

echo
echo "============================================================"
echo "Готово. Откройте https://$DOMAIN в браузере (с телефона или компьютера, VPN не нужен)"
echo "и НЕМЕДЛЕННО зарегистрируйте владельца панели — первый вошедший становится единственным владельцем."
echo "============================================================"
