#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║          FEDUK PROXY PANEL  —  Auto Installer               ║
# ║    Ubuntu 20.04 / 22.04 / 24.04  |  Debian 11 / 12         ║
# ╚══════════════════════════════════════════════════════════════╝

# Используем set -eo pipefail (без -u, чтобы избежать проблем с пустыми переменными)
set -eo pipefail

# ─────────────────────────────────────────────
#  ЦВЕТА
# ─────────────────────────────────────────────
R="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
WHITE="\033[37m"
C1="\033[38;5;27m"
C2="\033[38;5;33m"
C3="\033[38;5;57m"
C4="\033[38;5;93m"
C5="\033[38;5;129m"
C6="\033[38;5;165m"

# ─────────────────────────────────────────────
#  ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# ─────────────────────────────────────────────
PANEL_VERSION="3.1.0"
INSTALL_DIR="/opt/feduk"
CONFIG_DIR="/etc/feduk"
LOG_FILE="/var/log/feduk_install.log"
CRED_FILE="/root/.feduk_credentials"

PANEL_PORT="443"
HTTP_PORT="80"
ADMIN_USER="admin"
ADMIN_PASS=""
SERVER_IP=""
DOMAIN=""           # домен для Let's Encrypt (пусто = self-signed)
USE_LETSENCRYPT=false
XRAY_ARCH="64"
SPINNER_PID=""
CURRENT_STEP=0
TOTAL_STEPS=16

# ─────────────────────────────────────────────
#  ЛОГИРОВАНИЕ
# ─────────────────────────────────────────────
_ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log_info()  { echo "[$(_ts)] INFO:  $*" >> "$LOG_FILE"; }
log_warn()  { echo "[$(_ts)] WARN:  $*" >> "$LOG_FILE"; }
log_error() { echo "[$(_ts)] ERROR: $*" >> "$LOG_FILE"; }
log_ok()    { echo "[$(_ts)] OK:    $*" >> "$LOG_FILE"; }

print_ok()   { echo -e " ${GREEN}${BOLD}[✓]${R} $*"; }
print_err()  { echo -e " ${RED}${BOLD}[✗]${R} $*"; }
print_warn() { echo -e " ${YELLOW}${BOLD}[⚠]${R} $*"; }
print_info() { echo -e " ${C2}${BOLD}[ℹ]${R} $*"; }
print_step() { echo -e "\n${C3}${BOLD}▸ $*${R}"; }

die() {
    stop_spinner
    print_err "$*"
    log_error "FATAL: $*"
    echo -e "\n${RED}Установка прервана. Лог: ${LOG_FILE}${R}\n"
    exit 1
}

# ─────────────────────────────────────────────
#  СПИННЕР (race-condition safe)
# ─────────────────────────────────────────────
FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

start_spinner() {
    local msg="${1:-Загрузка...}"
    # Убиваем предыдущий спиннер если есть
    stop_spinner
    (
        local i=0
        while true; do
            printf "\r ${C4}${FRAMES[$i]}${R}  ${DIM}%s${R}   " "$msg"
            i=$(( (i+1) % ${#FRAMES[@]} ))
            sleep 0.1
        done
    ) </dev/null &
    SPINNER_PID=$!
    # disown нужен: без него завершение дочернего процесса посылает SIGCHLD
    # родителю, что при set -e может вызвать ложный выход
    disown "$SPINNER_PID" 2>/dev/null || true
}

stop_spinner() {
    local pid="${SPINNER_PID:-}"
    SPINNER_PID=""
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        # Не ждём — wait может блокировать
    fi
    printf "\r\033[K"
}

# Запуск команды со спиннером. Не бросает ошибку при неудаче (soft).
run_step() {
    local msg="$1"; shift
    start_spinner "$msg"
    local rc=0
    if "$@" >> "$LOG_FILE" 2>&1; then
        stop_spinner; print_ok "$msg"; log_ok "$msg"
    else
        rc=$?
        stop_spinner; print_err "$msg (код: $rc)"; log_error "$msg (код: $rc)"
        return $rc
    fi
}

# Запуск команды со спиннером без проверки кода возврата.
run_step_soft() {
    local msg="$1"; shift
    start_spinner "$msg"
    "$@" >> "$LOG_FILE" 2>&1 || true
    stop_spinner; print_ok "$msg"
}

# ─────────────────────────────────────────────
#  ПРОГРЕСС БАР
# ─────────────────────────────────────────────
progress_bar() {
    CURRENT_STEP=$(( CURRENT_STEP + 1 ))
    local pct=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
    local filled=$(( pct * 34 / 100 ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=filled; i<34; i++)); do bar+="░"; done
    printf "  ${C2}[${bar}]${R} ${BOLD}%3d%%${R}  %d/%d\n" "$pct" "$CURRENT_STEP" "$TOTAL_STEPS"
}

# ─────────────────────────────────────────────
#  БАННЕР
# ─────────────────────────────────────────────
show_banner() {
    clear
    echo
    echo -e "${C1}${BOLD}  ███████╗███████╗██████╗ ██╗   ██╗██╗  ██╗${R}"
    echo -e "${C2}${BOLD}  ██╔════╝██╔════╝██╔══██╗██║   ██║██║ ██╔╝${R}"
    echo -e "${C3}${BOLD}  █████╗  █████╗  ██║  ██║██║   ██║█████╔╝ ${R}"
    echo -e "${C4}${BOLD}  ██╔══╝  ██╔══╝  ██║  ██║██║   ██║██╔═██╗ ${R}"
    echo -e "${C5}${BOLD}  ██║     ███████╗██████╔╝╚██████╔╝██║  ██╗${R}"
    echo -e "${C6}${BOLD}  ╚═╝     ╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝${R}"
    echo
    echo -e "${C2}${BOLD}  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░${R}"
    echo -e "${C3}${BOLD}  ▒▒   P R O X Y   P A N E L  v 3 . 1  ▒▒${R}"
    echo -e "${C4}${BOLD}  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░${R}"
    echo
    echo -e "${C3}  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄${R}"
    echo -e "${C4}  █  VMess · VLESS · Trojan · Shadowsocks   █${R}"
    echo -e "${C5}  █  WireGuard · SOCKS5 · HTTP · Reality    █${R}"
    echo -e "${C3}  ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀${R}"
    echo
    echo -e "  ${DIM}Лог установки: ${LOG_FILE}${R}"
    echo -e "  ${DIM}$(date '+%A, %d %B %Y %H:%M:%S %Z')${R}"
    echo
}

# ─────────────────────────────────────────────
#  ШАГ 1: ПРОВЕРКИ + КОНФИГУРАЦИЯ
# ─────────────────────────────────────────────
preflight() {
    print_step "Проверка системы"

    [[ $EUID -ne 0 ]] && die "Запустите от root: sudo bash install.sh"
    print_ok "Root — OK"

    [[ ! -f /etc/os-release ]] && die "Не удалось определить ОС"
    # shellcheck source=/dev/null
    source /etc/os-release
    case "${ID:-}" in
        ubuntu|debian) print_ok "ОС: ${PRETTY_NAME}" ;;
        *) die "Неподдерживаемая ОС: ${ID:-unknown}. Нужен Ubuntu или Debian." ;;
    esac

    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  XRAY_ARCH="64" ;;
        aarch64) XRAY_ARCH="arm64-v8a" ;;
        armv7l)  XRAY_ARCH="arm32-v7a" ;;
        *) die "Неподдерживаемая архитектура: $arch" ;;
    esac
    print_ok "Архитектура: ${arch}"

    # Получаем IP — пробуем несколько сервисов
    SERVER_IP=""
    for url in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
        SERVER_IP=$(curl -s4 --max-time 8 --retry 2 "$url" 2>/dev/null | tr -d '[:space:]') || true
        [[ -n "$SERVER_IP" ]] && break
    done
    # Fallback на локальный IP
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    [[ -z "$SERVER_IP" ]] && die "Не удалось определить IP сервера"
    print_ok "IP сервера: ${SERVER_IP}"

    # Генерируем пароль: только ASCII буквы и цифры, 16 символов
    # Используем подоболочку без pipefail — иначе SIGPIPE от head убивает скрипт
    ADMIN_PASS=$(set +o pipefail; tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    print_ok "Пароль сгенерирован"

    # Запрашиваем домен для Let's Encrypt
    set +e
    echo
    echo -e "  ${C3}${BOLD}┌───────────────────────────────────────────────────┐${R}"
    echo -e "  ${C3}${BOLD}│  SSL сертификат                                    │${R}"
    echo -e "  ${C3}${BOLD}├───────────────────────────────────────────────────┤${R}"
    echo -e "  ${C3}│${R}  Let's Encrypt = бесплатный доверенный сертификат  ${C3}│${R}"
    echo -e "  ${C3}│${R}  Требует домен (A-запись → ${SERVER_IP})          ${C3}│${R}"
    echo -e "  ${C3}│${R}  ${DIM}Enter без ввода = самоподписанный сертификат${R}     ${C3}│${R}"
    echo -e "  ${C3}${BOLD}└───────────────────────────────────────────────────┘${R}"
    echo
    # Проверяем доступность /dev/tty (может быть недоступен при piped-запуске)
    if [[ -t 0 ]] || [[ -c /dev/tty ]]; then
        read -r -t 60 -p "  → Домен (например panel.example.com): " DOMAIN </dev/tty || DOMAIN=""
    else
        DOMAIN=""
        print_warn "Интерактивный ввод недоступен → самоподписанный сертификат"
    fi
    set -e
    # Убираем пробелы, табуляции, переводы строк и возврат каретки
    DOMAIN="${DOMAIN:-}"
    DOMAIN="$(printf '%s' "$DOMAIN" | tr -d '[:space:]')"
    if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_warn "IP не подходит для Let's Encrypt → self-signed"
        DOMAIN=""
    fi
    if [[ -n "$DOMAIN" ]]; then
        USE_LETSENCRYPT=true
        print_ok "Домен: ${DOMAIN} → Let's Encrypt SSL"
    else
        print_ok "Домен не указан → самоподписанный сертификат"
    fi
    echo

    # Проверяем что порт 8000 свободен
    if ss -tlnp 2>/dev/null | grep -q ':8000 '; then
        print_warn "Порт 8000 занят — пытаемся освободить"
        fuser -k 8000/tcp >> "$LOG_FILE" 2>&1 || true
        sleep 1
    fi

    log_info "Preflight OK. IP=${SERVER_IP} ARCH=${XRAY_ARCH}"
    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 2: СИСТЕМНЫЕ ПАКЕТЫ
# ─────────────────────────────────────────────
install_packages() {
    print_step "Установка системных пакетов"
    export DEBIAN_FRONTEND=noninteractive

    run_step "Обновление APT" apt-get update -qq

    run_step "Установка зависимостей" \
        apt-get install -y -qq \
            curl wget unzip git openssl ufw psmisc \
            python3 python3-pip python3-venv python3-dev \
            build-essential libssl-dev libffi-dev \
            nginx redis-server ca-certificates gnupg \
            lsb-release software-properties-common \
            jq logrotate cron net-tools

    # Node.js 20 — только если не установлен
    local node_ok=false
    if command -v node &>/dev/null; then
        local nver
        nver=$(node --version 2>/dev/null | grep -oP '\d+' | head -1)
        [[ "${nver:-0}" -ge 18 ]] && node_ok=true
    fi

    if [[ "$node_ok" == "false" ]]; then
        run_step "Установка Node.js 20" bash -c \
            "curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y -qq nodejs"
    else
        print_ok "Node.js уже установлен: $(node --version)"
    fi

    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 3: ФАЙРВОЛ UFW
# ─────────────────────────────────────────────
configure_firewall() {
    print_step "Настройка файрвола"

    # Не сбрасываем полностью — добавляем нужные правила поверх существующих
    run_step_soft "Настройка UFW" bash -c "
        ufw --force disable 2>/dev/null || true
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22/tcp  comment 'SSH'
        ufw allow ${HTTP_PORT}/tcp  comment 'HTTP'
        ufw allow ${PANEL_PORT}/tcp comment 'FEDUK Panel'
        ufw --force enable
    "
    print_ok "Открыты порты: 22, ${HTTP_PORT}, ${PANEL_PORT}"
    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 4: ДИРЕКТОРИИ
# ─────────────────────────────────────────────
create_directories() {
    print_step "Создание директорий"

    mkdir -p "${INSTALL_DIR}"/{xray/{bin,configs},panel/{static,venv},certs,data,logs,backups}
    mkdir -p "${CONFIG_DIR}"

    chmod 750 "${INSTALL_DIR}"
    chmod 700 "${INSTALL_DIR}/certs"
    chmod 750 "${INSTALL_DIR}/data"

    print_ok "Структура: ${INSTALL_DIR}"
    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 5: XRAY-CORE
# ─────────────────────────────────────────────
install_xray() {
    print_step "Установка Xray-core"

    # Получаем последнюю версию с fallback
    local latest=""
    latest=$(curl -sf --max-time 10 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" \
        | grep '"tag_name"' | cut -d'"' -f4 2>/dev/null) || true
    [[ -z "$latest" ]] && latest="v1.8.13"
    print_info "Xray версия: ${latest}"

    local tmpdir
    tmpdir=$(mktemp -d)
    # Не используем trap внутри функции — перезапишет глобальный trap EXIT
    # Явная очистка в конце функции безопаснее

    run_step "Загрузка Xray-core" \
        wget -q --show-progress \
             "https://github.com/XTLS/Xray-core/releases/download/${latest}/Xray-linux-${XRAY_ARCH}.zip" \
             -O "${tmpdir}/xray.zip"

    run_step "Распаковка Xray" \
        unzip -qo "${tmpdir}/xray.zip" -d "${tmpdir}/xray"

    install -m 755 "${tmpdir}/xray/xray" "${INSTALL_DIR}/xray/bin/xray"

    # Geo-данные — не критично, продолжаем без них
    run_step_soft "GeoIP данные" \
        wget -q "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" \
             -O "${INSTALL_DIR}/xray/configs/geoip.dat"

    run_step_soft "GeoSite данные" \
        wget -q "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
             -O "${INSTALL_DIR}/xray/configs/geosite.dat"

    print_ok "Xray-core ${latest} установлен"
    rm -rf "$tmpdir"
    progress_bar
}
# ─────────────────────────────────────────────

# Вынесена на верхний уровень — вложенные функции невидимы для run_step (exec)
_self_signed() {
    local cn="${DOMAIN:-$SERVER_IP}"
    local san="IP:${SERVER_IP}"
    [[ -n "$DOMAIN" ]] && san="DNS:${DOMAIN},IP:${SERVER_IP}"
    openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
        -keyout "${INSTALL_DIR}/certs/key.pem" \
        -out    "${INSTALL_DIR}/certs/cert.pem" \
        -subj   "/CN=${cn}/O=FEDUK/OU=Proxy/C=RU" \
        -addext "subjectAltName=${san}" >> "$LOG_FILE" 2>&1
    chmod 600 "${INSTALL_DIR}/certs/key.pem"
    chmod 644 "${INSTALL_DIR}/certs/cert.pem"
}

setup_ssl() {
    mkdir -p "${INSTALL_DIR}/certs"

    if [[ "$USE_LETSENCRYPT" == true ]] && [[ -n "$DOMAIN" ]]; then
        print_step "SSL: Let\'s Encrypt для ${DOMAIN}"

        run_step "Установка Certbot" bash -c "
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot 2>/dev/null
        "

        # Если nginx уже запущен — стоп, иначе certbot не захватит порт 80
        local nginx_was_running=false
        if systemctl is-active --quiet nginx 2>/dev/null; then
            nginx_was_running=true
            systemctl stop nginx >> "$LOG_FILE" 2>&1 || true
        fi

        print_info "Получение сертификата Let\'s Encrypt..."
        if certbot certonly \
                --standalone \
                --non-interactive \
                --agree-tos \
                --email "admin@${DOMAIN}" \
                -d "${DOMAIN}" \
                >> "$LOG_FILE" 2>&1; then

            ln -sf "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" "${INSTALL_DIR}/certs/cert.pem"
            ln -sf "/etc/letsencrypt/live/${DOMAIN}/privkey.pem"   "${INSTALL_DIR}/certs/key.pem"

            # Автообновление: раз в неделю
            ( crontab -l 2>/dev/null | grep -v "certbot renew"
              echo "0 3 * * 1 systemctl stop nginx; certbot renew --quiet --post-hook \"systemctl start nginx\""
            ) | crontab - 2>/dev/null || true

            print_ok "Let\'s Encrypt сертификат получен для ${DOMAIN}"
            log_ok "LE cert: ${DOMAIN}"
        else
            print_warn "certbot не смог получить сертификат — используем self-signed"
            log_warn "certbot failed, fallback to self-signed"
            USE_LETSENCRYPT=false
            _self_signed
            print_ok "Self-signed сертификат сгенерирован (запасной вариант)"
        fi

        [[ "$nginx_was_running" == "true" ]] && systemctl start nginx >> "$LOG_FILE" 2>&1 || true

    else
        print_step "SSL: самоподписанный сертификат (RSA-4096, 10 лет)"
        run_step "Генерация сертификата" _self_signed
        print_ok "Сертификат готов"
    fi

    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 7: КОНФИГ XRAY
# ─────────────────────────────────────────────
create_xray_config() {
    print_step "Конфигурация Xray"

    cat > "${INSTALL_DIR}/xray/configs/config.json" <<'XEOF'
{
  "log": {
    "access":   "/opt/feduk/logs/xray-access.log",
    "error":    "/opt/feduk/logs/xray-error.log",
    "loglevel": "warning"
  },
  "api": {
    "tag":      "api",
    "services": ["HandlerService", "LoggerService", "StatsService"]
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": { "statsUserUplink": true, "statsUserDownlink": true }
    },
    "system": {
      "statsInboundUplink":   true,
      "statsInboundDownlink": true,
      "statsOutboundUplink":  true,
      "statsOutboundDownlink":true
    }
  },
  "inbounds": [
    {
      "tag":      "api-inbound",
      "listen":   "127.0.0.1",
      "port":     10085,
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" }
    }
  ],
  "outbounds": [
    {
      "tag":      "direct",
      "protocol": "freedom",
      "settings": { "domainStrategy": "UseIPv4" }
    },
    {
      "tag":      "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type":        "field",
        "inboundTag":  ["api-inbound"],
        "outboundTag": "api"
      },
      {
        "type":        "field",
        "ip":          ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type":        "field",
        "domain":      ["geosite:category-ads-all"],
        "outboundTag": "blocked"
      }
    ]
  }
}
XEOF

    print_ok "Xray конфиг: ${INSTALL_DIR}/xray/configs/config.json"
    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 8: FASTAPI БЭКЕНД
#  Используем bcrypt напрямую — passlib 1.7.4 несовместима с bcrypt>=4.x
#  (bcrypt 4.x удалил __about__, из-за чего passlib падает при импорте)
# ─────────────────────────────────────────────
setup_python_backend() {
    print_step "FastAPI бэкенд"

    local VENV="${INSTALL_DIR}/panel/venv"
    local PIP="${VENV}/bin/pip"

    run_step "Python venv" python3 -m venv "$VENV"
    run_step "Обновление pip" "$PIP" install -q --upgrade pip setuptools wheel

    run_step "Python зависимости" bash -c "
        ${PIP} install -q \
            'fastapi==0.111.0' \
            'uvicorn[standard]==0.29.0' \
            'sqlalchemy==2.0.30' \
            'pydantic==2.7.1' \
            'python-jose[cryptography]==3.3.0' \
            'bcrypt==4.1.3' \
            'python-multipart==0.0.9' \
            'redis==5.0.4' \
            'httpx==0.27.0' \
            'psutil==5.9.8' \
            'PyYAML==6.0.1' \
            'loguru==0.7.2' \
            'APScheduler==3.10.4' \
            'aiofiles==23.2.1'
    "

    # Используем EOF без кавычек — переменные bash подставятся
    # Внутри Python используем только константы, не переменные bash
    cat > "${INSTALL_DIR}/panel/main.py" << 'PYEOF'
"""FEDUK Proxy Panel v3.1 — FastAPI Backend"""
import json, os, subprocess, uuid, warnings
warnings.filterwarnings("ignore")

from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

from fastapi import (
    FastAPI, Depends, HTTPException, BackgroundTasks, Request
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from pydantic import BaseModel, Field
from sqlalchemy import (
    create_engine, Column, String, Integer, BigInteger,
    Boolean, DateTime, Text, ForeignKey, func
)
from sqlalchemy.orm import declarative_base
from sqlalchemy.orm import sessionmaker, Session, relationship

# bcrypt напрямую — без passlib (passlib 1.7.4 несовместима с bcrypt>=4.x)
import bcrypt as _bcrypt

import psutil, yaml
from loguru import logger

# ── Пути ──────────────────────────────────────────────────────
BASE_DIR = Path("/opt/feduk")
DATA_DIR = BASE_DIR / "data"
XRAY_CFG = BASE_DIR / "xray" / "configs" / "config.json"

cfg_path = Path("/etc/feduk/config.yml")
cfg = yaml.safe_load(cfg_path.read_text()) if cfg_path.exists() else {}

SECRET_KEY = cfg.get("secret_key", "feduk-secret-change-me!")
ALGORITHM  = "HS256"
TOKEN_TTL  = 1440  # минут = 24ч

# ── База данных ────────────────────────────────────────────────
engine = create_engine(
    f"sqlite:///{DATA_DIR}/config.db",
    connect_args={"check_same_thread": False},
    pool_pre_ping=True,
)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
Base = declarative_base()


class Inbound(Base):
    __tablename__ = "inbounds"
    id         = Column(Integer, primary_key=True, index=True)
    tag        = Column(String(64), unique=True)
    remark     = Column(String(128))
    protocol   = Column(String(32))
    port       = Column(Integer, unique=True)
    listen     = Column(String(64), default="0.0.0.0")
    settings   = Column(Text, default="{}")
    stream     = Column(Text, default="{}")
    sniffing   = Column(Text, default="{}")
    enabled    = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    clients    = relationship("Client", back_populates="inbound", cascade="all,delete")


class Client(Base):
    __tablename__ = "clients"
    id            = Column(Integer, primary_key=True, index=True)
    inbound_id    = Column(Integer, ForeignKey("inbounds.id"))
    email         = Column(String(128), unique=True, index=True)
    uuid          = Column(String(36), default=lambda: str(uuid.uuid4()))
    password      = Column(String(64), default="")
    flow          = Column(String(32), default="")
    enabled       = Column(Boolean, default=True)
    traffic_up    = Column(BigInteger, default=0)
    traffic_down  = Column(BigInteger, default=0)
    traffic_limit = Column(BigInteger, default=0)
    expire_date   = Column(DateTime, nullable=True)
    created_at    = Column(DateTime, default=datetime.utcnow)
    inbound       = relationship("Inbound", back_populates="clients")


class AdminUser(Base):
    __tablename__ = "admin_users"
    id            = Column(Integer, primary_key=True)
    username      = Column(String(64), unique=True, index=True)
    password_hash = Column(String(128))
    is_active     = Column(Boolean, default=True)
    created_at    = Column(DateTime, default=datetime.utcnow)


Base.metadata.create_all(bind=engine)

# ── Auth ───────────────────────────────────────────────────────
oauth2 = OAuth2PasswordBearer(tokenUrl="/api/auth/token")


def verify_password(plain: str, hashed: str) -> bool:
    try:
        plain_bytes = plain.encode("utf-8")[:72]
        return _bcrypt.checkpw(plain_bytes, hashed.encode("utf-8"))
    except Exception:
        return False


def get_password_hash(password: str) -> str:
    pw = password.encode("utf-8")[:72]
    return _bcrypt.hashpw(pw, _bcrypt.gensalt(12)).decode("utf-8")


def create_token(username: str) -> str:
    payload = {
        "sub": username,
        "exp": datetime.utcnow() + timedelta(minutes=TOKEN_TTL),
        "iat": datetime.utcnow(),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_current_user(
    token: str = Depends(oauth2),
    db: Session = Depends(get_db)
):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub", "")
        if not username:
            raise HTTPException(status_code=401, detail="Неверный токен")
    except JWTError:
        raise HTTPException(status_code=401, detail="Неверный или истёкший токен")

    user = db.query(AdminUser).filter(AdminUser.username == username, AdminUser.is_active == True).first()
    if not user:
        raise HTTPException(status_code=401, detail="Пользователь не найден")
    return user


# ── Схемы ──────────────────────────────────────────────────────
class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class InboundCreate(BaseModel):
    remark:   str
    protocol: str
    port:     int = Field(..., ge=1, le=65535)
    listen:   str = "0.0.0.0"
    settings: dict = {}
    stream:   dict = {}


class ClientCreate(BaseModel):
    email:         str
    inbound_id:    int
    traffic_limit: int = 0
    expire_date:   Optional[datetime] = None
    flow:          str = ""


# ── Xray управление ────────────────────────────────────────────
def build_xray_config(db: Session) -> dict:
    """Генерирует полный конфиг Xray из БД."""
    base = json.loads(XRAY_CFG.read_text()) if XRAY_CFG.exists() else {}

    inbounds = base.get("inbounds", [])
    for inb in db.query(Inbound).filter(Inbound.enabled == True).all():
        settings = json.loads(inb.settings or "{}")
        clients_data = []

        for c in inb.clients:
            if not c.enabled:
                continue
            if c.expire_date and c.expire_date < datetime.utcnow():
                continue
            entry: dict = {"email": c.email}
            if inb.protocol in ("vmess", "vless"):
                entry["id"] = c.uuid
                if c.flow:
                    entry["flow"] = c.flow
            elif inb.protocol == "trojan":
                entry["password"] = c.password or c.uuid
            clients_data.append(entry)

        if inb.protocol == "shadowsocks":
            settings.setdefault("method", "chacha20-ietf-poly1305")
        else:
            settings["clients"] = clients_data

        inbound_cfg = {
            "tag":      inb.tag,
            "listen":   inb.listen,
            "port":     inb.port,
            "protocol": inb.protocol,
            "settings": settings,
            "streamSettings": json.loads(inb.stream or "{}"),
            "sniffing":       json.loads(inb.sniffing or "{}"),
        }
        inbounds.append(inbound_cfg)

    base["inbounds"] = inbounds
    return base


def xray_apply(db: Session):
    """Пишет конфиг и перезапускает Xray."""
    try:
        cfg_data = build_xray_config(db)
        XRAY_CFG.write_text(json.dumps(cfg_data, ensure_ascii=False, indent=2))
        subprocess.run(
            ["systemctl", "restart", "xray-feduk"],
            capture_output=True, timeout=15
        )
    except Exception as e:
        logger.error(f"Xray apply error: {e}")


# ── Redis (опционально) ────────────────────────────────────────
try:
    import redis as _redis
    _r = _redis.Redis(
        host="127.0.0.1", port=6379, db=0,
        decode_responses=True, socket_timeout=2
    )
    _r.ping()
    REDIS_OK = True
except Exception:
    REDIS_OK = False

# ── Приложение ─────────────────────────────────────────────────
app = FastAPI(
    title="FEDUK Proxy Panel",
    version="3.1.0",
    docs_url="/api/docs",
    redoc_url=None,
    openapi_url="/api/openapi.json",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"],
)
app.add_middleware(GZipMiddleware, minimum_size=512)


# ── Эндпоинты: Auth ────────────────────────────────────────────
@app.post("/api/auth/token", response_model=Token, tags=["Auth"])
async def login(
    form: OAuth2PasswordRequestForm = Depends(),
    db:   Session = Depends(get_db)
):
    user = db.query(AdminUser).filter(AdminUser.username == form.username).first()
    if not user or not verify_password(form.password, user.password_hash):
        raise HTTPException(status_code=400, detail="Неверный логин или пароль")
    return {"access_token": create_token(user.username), "token_type": "bearer"}


# ── Эндпоинты: Dashboard ───────────────────────────────────────
@app.get("/api/dashboard", tags=["Dashboard"])
async def dashboard(
    db: Session = Depends(get_db),
    _=Depends(get_current_user)
):
    cpu  = psutil.cpu_percent(interval=0.3)
    mem  = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    net  = psutil.net_io_counters()
    boot = datetime.utcfromtimestamp(psutil.boot_time())
    uptime = (datetime.utcnow() - boot).total_seconds()

    return {
        "system": {
            "cpu_percent":    cpu,
            "mem_percent":    mem.percent,
            "mem_total":      mem.total,
            "mem_used":       mem.used,
            "disk_percent":   disk.percent,
            "disk_total":     disk.total,
            "disk_used":      disk.used,
            "net_sent":       net.bytes_sent,
            "net_recv":       net.bytes_recv,
            "uptime_seconds": uptime,
        },
        "proxy": {
            "inbounds_total":  db.query(func.count(Inbound.id)).scalar() or 0,
            "clients_total":   db.query(func.count(Client.id)).scalar() or 0,
            "clients_active":  db.query(func.count(Client.id)).filter(Client.enabled == True).scalar() or 0,
            "traffic_up_gb":   round((db.query(func.sum(Client.traffic_up)).scalar()   or 0) / 1024 ** 3, 3),
            "traffic_down_gb": round((db.query(func.sum(Client.traffic_down)).scalar() or 0) / 1024 ** 3, 3),
        },
    }


# ── Эндпоинты: Inbounds ────────────────────────────────────────
@app.get("/api/inbounds", tags=["Inbounds"])
async def list_inbounds(
    db: Session = Depends(get_db),
    _=Depends(get_current_user)
):
    rows = db.query(Inbound).order_by(Inbound.id).all()
    return [
        {
            "id": i.id, "tag": i.tag, "remark": i.remark,
            "protocol": i.protocol, "port": i.port,
            "listen": i.listen, "enabled": i.enabled,
            "clients_count": len(i.clients),
            "created_at": i.created_at.isoformat(),
        }
        for i in rows
    ]


@app.post("/api/inbounds", tags=["Inbounds"])
async def create_inbound(
    data: InboundCreate,
    bg:   BackgroundTasks,
    db:   Session = Depends(get_db),
    _=Depends(get_current_user)
):
    if db.query(Inbound).filter(Inbound.port == data.port).first():
        raise HTTPException(400, detail=f"Порт {data.port} уже занят")

    tag = f"{data.protocol}-{data.port}"
    if db.query(Inbound).filter(Inbound.tag == tag).first():
        tag = f"{data.protocol}-{data.port}-{uuid.uuid4().hex[:4]}"

    inb = Inbound(
        tag=tag, remark=data.remark,
        protocol=data.protocol, port=data.port, listen=data.listen,
        settings=json.dumps(data.settings),
        stream=json.dumps(data.stream),
        sniffing=json.dumps({"enabled": True, "destOverride": ["http", "tls"]}),
    )
    db.add(inb); db.commit(); db.refresh(inb)
    bg.add_task(xray_apply, db)
    return {"id": inb.id, "tag": inb.tag, "ok": True}


@app.patch("/api/inbounds/{inbound_id}/toggle", tags=["Inbounds"])
async def toggle_inbound(
    inbound_id: int,
    bg: BackgroundTasks,
    db: Session = Depends(get_db),
    _=Depends(get_current_user)
):
    inb = db.query(Inbound).filter(Inbound.id == inbound_id).first()
    if not inb:
        raise HTTPException(404, detail="Inbound не найден")
    inb.enabled = not inb.enabled
    db.commit()
    bg.add_task(xray_apply, db)
    return {"enabled": inb.enabled}


@app.delete("/api/inbounds/{inbound_id}", tags=["Inbounds"])
async def delete_inbound(
    inbound_id: int,
    bg: BackgroundTasks,
    db: Session = Depends(get_db),
    _=Depends(get_current_user)
):
    inb = db.query(Inbound).filter(Inbound.id == inbound_id).first()
    if not inb:
        raise HTTPException(404, detail="Inbound не найден")
    db.delete(inb); db.commit()
    bg.add_task(xray_apply, db)
    return {"ok": True}


# ── Эндпоинты: Clients ─────────────────────────────────────────
@app.get("/api/clients", tags=["Clients"])
async def list_clients(
    db: Session = Depends(get_db),
    _=Depends(get_current_user)
):
    rows = db.query(Client).order_by(Client.id).all()
    return [
        {
            "id":            c.id,
            "email":         c.email,
            "uuid":          c.uuid,
            "inbound_id":    c.inbound_id,
            "flow":          c.flow,
            "enabled":       c.enabled,
            "traffic_up":    c.traffic_up,
            "traffic_down":  c.traffic_down,
            "traffic_limit": c.traffic_limit,
            "expire_date":   c.expire_date.isoformat() if c.expire_date else None,
            "created_at":    c.created_at.isoformat(),
        }
        for c in rows
    ]


@app.post("/api/clients", tags=["Clients"])
async def create_client(
    data: ClientCreate,
    bg:   BackgroundTasks,
    db:   Session = Depends(get_db),
    _=Depends(get_current_user)
):
    if db.query(Client).filter(Client.email == data.email).first():
        raise HTTPException(400, detail="Email уже существует")

    c = Client(
        inbound_id=data.inbound_id,
        email=data.email,
        flow=data.flow,
        traffic_limit=data.traffic_limit,
        expire_date=data.expire_date,
    )
    db.add(c); db.commit(); db.refresh(c)
    bg.add_task(xray_apply, db)
    return {"id": c.id, "uuid": c.uuid, "email": c.email, "ok": True}


@app.patch("/api/clients/{client_id}/toggle", tags=["Clients"])
async def toggle_client(
    client_id: int,
    bg: BackgroundTasks,
    db: Session = Depends(get_db),
    _=Depends(get_current_user)
):
    c = db.query(Client).filter(Client.id == client_id).first()
    if not c:
        raise HTTPException(404, detail="Клиент не найден")
    c.enabled = not c.enabled
    db.commit()
    bg.add_task(xray_apply, db)
    return {"enabled": c.enabled}


@app.delete("/api/clients/{client_id}", tags=["Clients"])
async def delete_client(
    client_id: int,
    bg: BackgroundTasks,
    db: Session = Depends(get_db),
    _=Depends(get_current_user)
):
    c = db.query(Client).filter(Client.id == client_id).first()
    if not c:
        raise HTTPException(404, detail="Клиент не найден")
    db.delete(c); db.commit()
    bg.add_task(xray_apply, db)
    return {"ok": True}


# ── Эндпоинты: System ──────────────────────────────────────────
@app.get("/api/status", tags=["System"])
async def system_status(_=Depends(get_current_user)):
    services = {}
    for svc in ["feduk", "xray-feduk", "nginx", "redis-server"]:
        try:
            r = subprocess.run(
                ["systemctl", "is-active", svc],
                capture_output=True, text=True, timeout=5
            )
            services[svc] = r.stdout.strip() == "active"
        except Exception:
            services[svc] = False
    return {"services": services, "redis": REDIS_OK}


@app.get("/api/health", tags=["System"], include_in_schema=False)
async def health():
    return {"status": "ok", "version": "3.1.0"}


class ChangePasswordRequest(BaseModel):
    old_password: str
    new_password: str


@app.post("/api/auth/change-password", tags=["Auth"])
async def change_password(
    data: ChangePasswordRequest,
    db: Session = Depends(get_db),
    user=Depends(get_current_user)
):
    if not verify_password(data.old_password, user.password_hash):
        raise HTTPException(400, detail="Неверный текущий пароль")
    if len(data.new_password) < 8:
        raise HTTPException(400, detail="Пароль минимум 8 символов")
    user.password_hash = get_password_hash(data.new_password)
    db.commit()
    return {"ok": True}


@app.post("/api/xray/restart", tags=["System"])
async def restart_xray(_=Depends(get_current_user)):
    try:
        subprocess.run(["systemctl", "restart", "xray-feduk"], capture_output=True, timeout=15)
        return {"ok": True}
    except Exception as e:
        raise HTTPException(500, detail=str(e))


# ── SPA ────────────────────────────────────────────────────────
_static = Path("/opt/feduk/panel/static")
if _static.exists():
    app.mount("/static", StaticFiles(directory=str(_static)), name="static")


@app.get("/{full_path:path}", include_in_schema=False)
async def spa(full_path: str):
    # Не перехватываем API-маршруты
    if full_path.startswith("api/"):
        raise HTTPException(status_code=404)
    idx = _static / "index.html"
    if idx.exists():
        return HTMLResponse(idx.read_text())
    return HTMLResponse("<h1>FEDUK Panel</h1><p>Frontend not found</p>", status_code=503)
PYEOF

    print_ok "FastAPI backend создан"
    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 9: ФРОНТЕНД
# ─────────────────────────────────────────────
create_frontend() {
    print_step "Создание фронтенда"

    local STATIC="${INSTALL_DIR}/panel/static"
    mkdir -p "$STATIC"

    cat > "${STATIC}/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="ru" data-theme="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>FEDUK Proxy Panel</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js"></script>
<style>
:root {
  --bg:#080b12;--bg2:#0d1117;--bg3:#131921;--bg4:#1a2233;--bghov:#1f2d44;
  --acc1:#3b82f6;--acc2:#8b5cf6;--acc3:#06b6d4;
  --ok:#10b981;--warn:#f59e0b;--err:#ef4444;
  --txt:#e2e8f0;--txt2:#94a3b8;--border:#1e3a5f;
  --grad:linear-gradient(135deg,#3b82f6,#8b5cf6);
  --grad2:linear-gradient(135deg,#06b6d4,#3b82f6);
  --shadow:0 8px 32px rgba(0,0,0,.6);
  --r:14px;--r2:8px;--mono:'JetBrains Mono',monospace;
}
[data-theme="light"] {
  --bg:#f0f4ff;--bg2:#fff;--bg3:#fff;--bg4:#e8eef8;--bghov:#dce6f7;
  --txt:#0f172a;--txt2:#475569;--border:#cbd5e1;--shadow:0 4px 20px rgba(0,0,0,.1);
}
*, *::before, *::after { margin:0; padding:0; box-sizing:border-box; }
html, body { height:100%; font-family:'Inter',system-ui,sans-serif; background:var(--bg); color:var(--txt); font-size:14px; line-height:1.6; }
::-webkit-scrollbar { width:5px; height:5px; }
::-webkit-scrollbar-track { background:var(--bg2); }
::-webkit-scrollbar-thumb { background:var(--acc1); border-radius:4px; }

.layout { display:flex; height:100vh; overflow:hidden; }
.sidebar { width:248px; min-width:248px; background:var(--bg2); border-right:1px solid var(--border); display:flex; flex-direction:column; transition:width .2s; }
.content { flex:1; overflow-y:auto; padding:28px; }

.logo-area { padding:22px 18px 18px; border-bottom:1px solid var(--border); display:flex; align-items:center; gap:12px; }
.logo-icon { font-size:28px; }
.logo-title { font-size:18px; font-weight:900; background:var(--grad); -webkit-background-clip:text; -webkit-text-fill-color:transparent; background-clip:text; }
.logo-sub { font-size:10px; color:var(--txt2); font-weight:500; }

.nav { flex:1; padding:12px 10px; overflow-y:auto; }
.nav-section { font-size:10px; text-transform:uppercase; letter-spacing:1.5px; color:var(--txt2); padding:10px 12px 4px; font-weight:600; }
.nav-item { display:flex; align-items:center; gap:10px; padding:10px 14px; border-radius:var(--r2); cursor:pointer; font-size:13px; font-weight:500; color:var(--txt2); transition:all .15s; margin-bottom:2px; user-select:none; }
.nav-item:hover { background:var(--bghov); color:var(--txt); }
.nav-item.active { background:rgba(59,130,246,.15); color:var(--acc1); font-weight:700; box-shadow:inset 3px 0 0 var(--acc1); }
.nav-item .ico { font-size:16px; width:22px; text-align:center; }
.nav-badge { margin-left:auto; background:var(--acc1); color:#fff; font-size:10px; padding:1px 7px; border-radius:12px; font-weight:700; min-width:20px; text-align:center; }

.sidebar-foot { padding:12px 10px; border-top:1px solid var(--border); }
.theme-row { display:flex; align-items:center; gap:8px; cursor:pointer; padding:9px 14px; border-radius:var(--r2); color:var(--txt2); font-size:13px; user-select:none; }
.theme-row:hover { background:var(--bghov); }
.sw { width:38px; height:21px; background:var(--bg4); border-radius:11px; position:relative; margin-left:auto; transition:background .2s; flex-shrink:0; }
.sw.on { background:var(--acc1); }
.sw-k { width:17px; height:17px; background:#fff; border-radius:50%; position:absolute; top:2px; left:2px; transition:left .2s; box-shadow:0 1px 4px rgba(0,0,0,.3); }
.sw.on .sw-k { left:19px; }

.hdr { display:flex; align-items:center; justify-content:space-between; margin-bottom:28px; flex-wrap:wrap; gap:12px; }
.page-title { font-size:22px; font-weight:800; letter-spacing:-.5px; }
.page-title span { color:var(--txt2); font-weight:400; font-size:14px; margin-left:8px; }
.hdr-actions { display:flex; gap:8px; flex-wrap:wrap; align-items:center; }

.search-box { display:flex; align-items:center; background:var(--bg3); border:1px solid var(--border); border-radius:var(--r2); padding:7px 12px; gap:8px; }
.search-box input { background:none; border:none; color:var(--txt); font-size:13px; outline:none; width:160px; font-family:inherit; }
.search-box input::placeholder { color:var(--txt2); }

.btn { display:inline-flex; align-items:center; gap:7px; padding:9px 18px; border-radius:var(--r2); border:none; cursor:pointer; font-size:13px; font-weight:600; transition:all .15s; letter-spacing:.1px; font-family:inherit; }
.btn:disabled { opacity:.5; cursor:not-allowed; }
.btn-primary { background:var(--grad); color:#fff; box-shadow:0 4px 14px rgba(59,130,246,.3); }
.btn-primary:hover:not(:disabled) { transform:translateY(-1px); box-shadow:0 6px 22px rgba(59,130,246,.4); }
.btn-secondary { background:var(--bg3); color:var(--txt); border:1px solid var(--border); }
.btn-secondary:hover:not(:disabled) { background:var(--bghov); }
.btn-danger { background:rgba(239,68,68,.12); color:var(--err); border:1px solid rgba(239,68,68,.2); }
.btn-danger:hover:not(:disabled) { background:rgba(239,68,68,.22); }
.btn-sm { padding:5px 11px; font-size:12px; }
.btn-icon { padding:6px 10px; }

.cards { display:grid; grid-template-columns:repeat(auto-fill,minmax(200px,1fr)); gap:16px; margin-bottom:28px; }
.card { background:var(--bg2); border:1px solid var(--border); border-radius:var(--r); padding:20px; transition:all .2s; position:relative; overflow:hidden; }
.card::before { content:''; position:absolute; top:0; left:0; right:0; height:3px; }
.card:nth-child(1)::before { background:linear-gradient(90deg,#3b82f6,#8b5cf6); }
.card:nth-child(2)::before { background:linear-gradient(90deg,#06b6d4,#3b82f6); }
.card:nth-child(3)::before { background:linear-gradient(90deg,#10b981,#06b6d4); }
.card:nth-child(4)::before { background:linear-gradient(90deg,#f59e0b,#ef4444); }
.card:nth-child(5)::before { background:linear-gradient(90deg,#8b5cf6,#3b82f6); }
.card:nth-child(6)::before { background:linear-gradient(90deg,#06b6d4,#10b981); }
.card:nth-child(7)::before { background:linear-gradient(90deg,#3b82f6,#06b6d4); }
.card:nth-child(8)::before { background:linear-gradient(90deg,#8b5cf6,#ef4444); }
.card:hover { border-color:rgba(59,130,246,.4); transform:translateY(-2px); box-shadow:var(--shadow); }
.card-label { font-size:11px; text-transform:uppercase; letter-spacing:1.2px; color:var(--txt2); font-weight:600; margin-bottom:10px; }
.card-value { font-size:28px; font-weight:900; line-height:1; letter-spacing:-1px; }
.card-sub { font-size:12px; color:var(--txt2); margin-top:6px; }
.card-ico { position:absolute; right:14px; top:50%; transform:translateY(-50%); font-size:36px; opacity:.06; pointer-events:none; }
.stat-bar { height:4px; background:var(--bg4); border-radius:2px; margin-top:8px; overflow:hidden; }
.stat-bar-fill { height:100%; border-radius:2px; transition:width .6s ease; }

/* NET GRAPH */
.net-card { background:var(--bg2); border:1px solid var(--border); border-radius:var(--r); padding:20px; margin-bottom:28px; }
.net-card-hdr { display:flex; justify-content:space-between; align-items:center; margin-bottom:16px; }
.net-card-title { font-weight:700; font-size:15px; }
.net-legend { display:flex; gap:16px; font-size:12px; color:var(--txt2); }
.net-legend span { display:flex; align-items:center; gap:6px; }
.net-legend i { width:16px; height:3px; border-radius:2px; display:inline-block; }
canvas#net-canvas { width:100%; height:120px; display:block; }

.tbl-wrap { background:var(--bg2); border:1px solid var(--border); border-radius:var(--r); overflow:hidden; margin-bottom:24px; }
.tbl-hdr { display:flex; justify-content:space-between; align-items:center; padding:16px 22px; border-bottom:1px solid var(--border); flex-wrap:wrap; gap:12px; }
.tbl-title { font-weight:800; font-size:15px; }
.tbl-sub { font-size:12px; color:var(--txt2); margin-top:2px; }
.tbl-scroll { overflow-x:auto; }
table { width:100%; border-collapse:collapse; min-width:500px; }
th { background:rgba(255,255,255,.02); color:var(--txt2); font-size:11px; text-transform:uppercase; letter-spacing:1px; font-weight:600; padding:12px 20px; text-align:left; white-space:nowrap; }
td { padding:13px 20px; border-top:1px solid var(--border); font-size:13px; }
tr:hover td { background:rgba(255,255,255,.02); }
.td-actions { display:flex; gap:6px; flex-wrap:wrap; }

.badge { display:inline-flex; align-items:center; gap:4px; padding:3px 9px; border-radius:20px; font-size:11px; font-weight:700; white-space:nowrap; }
.b-green { background:rgba(16,185,129,.12); color:var(--ok); }
.b-red { background:rgba(239,68,68,.12); color:var(--err); }
.b-blue { background:rgba(59,130,246,.12); color:var(--acc1); }
.b-purple { background:rgba(139,92,246,.12); color:var(--acc2); }
.b-cyan { background:rgba(6,182,212,.12); color:var(--acc3); }
.b-yellow { background:rgba(245,158,11,.12); color:var(--warn); }

.modal-ov { display:none; position:fixed; inset:0; background:rgba(0,0,0,.75); z-index:1000; align-items:center; justify-content:center; backdrop-filter:blur(6px); padding:16px; }
.modal-ov.open { display:flex; }
.modal { background:var(--bg2); border:1px solid var(--border); border-radius:var(--r); padding:30px; width:100%; max-width:520px; box-shadow:var(--shadow); animation:popIn .22s cubic-bezier(.34,1.56,.64,1); max-height:90vh; overflow-y:auto; }
@keyframes popIn { from { transform:scale(.92) translateY(12px); opacity:0; } to { transform:scale(1) translateY(0); opacity:1; } }
.modal-title { font-size:18px; font-weight:800; margin-bottom:22px; display:flex; justify-content:space-between; align-items:center; }
.modal-close { cursor:pointer; color:var(--txt2); font-size:20px; line-height:1; padding:4px 8px; border-radius:6px; }
.modal-close:hover { background:var(--bghov); color:var(--txt); }
.modal-foot { display:flex; gap:10px; justify-content:flex-end; margin-top:22px; flex-wrap:wrap; }

.fg { margin-bottom:16px; }
.fl { display:block; font-size:12px; font-weight:600; color:var(--txt2); text-transform:uppercase; letter-spacing:.8px; margin-bottom:7px; }
.fi, .fs { width:100%; background:var(--bg); border:1px solid var(--border); border-radius:var(--r2); padding:10px 14px; color:var(--txt); font-size:14px; outline:none; transition:border-color .2s, box-shadow .2s; font-family:inherit; }
.fi:focus, .fs:focus { border-color:var(--acc1); box-shadow:0 0 0 3px rgba(59,130,246,.12); }
.proto-hint { font-size:12px; color:var(--txt2); margin-top:6px; padding:8px 12px; background:var(--bg4); border-radius:var(--r2); border-left:3px solid var(--acc1); }
.fg-row { display:grid; grid-template-columns:1fr 1fr; gap:12px; }

/* QR MODAL */
.qr-wrap { display:flex; flex-direction:column; align-items:center; gap:16px; }
.qr-box { background:#fff; padding:16px; border-radius:12px; }
.qr-link { font-family:var(--mono); font-size:11px; background:var(--bg4); padding:10px 14px; border-radius:var(--r2); word-break:break-all; color:var(--acc3); cursor:pointer; border:1px solid var(--border); width:100%; text-align:left; }
.qr-link:hover { border-color:var(--acc1); }

/* SETTINGS */
.settings-section { background:var(--bg2); border:1px solid var(--border); border-radius:var(--r); padding:24px; margin-bottom:20px; }
.settings-title { font-size:15px; font-weight:700; margin-bottom:18px; display:flex; align-items:center; gap:10px; }
.settings-row { display:flex; justify-content:space-between; align-items:center; padding:14px 0; border-bottom:1px solid var(--border); }
.settings-row:last-child { border-bottom:none; padding-bottom:0; }
.settings-label { font-size:13px; font-weight:600; }
.settings-sub { font-size:12px; color:var(--txt2); margin-top:3px; }
.settings-val { font-family:var(--mono); font-size:12px; color:var(--acc3); cursor:pointer; background:var(--bg4); padding:5px 10px; border-radius:6px; border:1px solid var(--border); }
.settings-val:hover { border-color:var(--acc1); }

/* LOGIN */
.login-wrap { min-height:100vh; display:flex; align-items:center; justify-content:center; background:var(--bg); background-image: radial-gradient(ellipse at 20% 50%,rgba(59,130,246,.1) 0%,transparent 60%), radial-gradient(ellipse at 80% 20%,rgba(139,92,246,.1) 0%,transparent 60%); }
.login-card { background:var(--bg2); border:1px solid var(--border); border-radius:20px; padding:44px 40px; width:100%; max-width:380px; box-shadow:var(--shadow); }
.login-logo { text-align:center; margin-bottom:36px; }
.login-logo .ico { font-size:52px; margin-bottom:12px; display:block; }
.login-logo h1 { font-size:28px; font-weight:900; background:var(--grad); -webkit-background-clip:text; -webkit-text-fill-color:transparent; background-clip:text; }
.login-logo p { color:var(--txt2); font-size:13px; margin-top:6px; }
.login-btn { width:100%; padding:14px; font-size:15px; font-weight:800; background:var(--grad); color:#fff; border:none; border-radius:var(--r2); cursor:pointer; transition:all .2s; font-family:inherit; margin-top:6px; }
.login-btn:hover { transform:translateY(-1px); box-shadow:0 6px 24px rgba(59,130,246,.4); }
.login-btn.loading { opacity:.7; cursor:wait; }
.login-err { color:var(--err); font-size:13px; text-align:center; margin-top:14px; min-height:20px; font-weight:500; }

#toast-container { position:fixed; top:20px; right:20px; z-index:9999; display:flex; flex-direction:column; gap:8px; pointer-events:none; }
.toast { background:var(--bg2); border:1px solid var(--border); border-radius:var(--r2); padding:12px 16px; display:flex; align-items:center; gap:10px; min-width:240px; max-width:360px; box-shadow:var(--shadow); font-size:13px; font-weight:500; animation:slideIn .25s ease; pointer-events:auto; }
@keyframes slideIn { from { transform:translateX(110%); opacity:0; } to { transform:translateX(0); opacity:1; } }
.toast.out { animation:slideOut .3s ease forwards; }
@keyframes slideOut { to { transform:translateX(110%); opacity:0; } }
.toast.success { border-left:3px solid var(--ok); }
.toast.error   { border-left:3px solid var(--err); }
.toast.info    { border-left:3px solid var(--acc1); }
.toast.warning { border-left:3px solid var(--warn); }

.mono { font-family:var(--mono); font-size:11px; color:var(--acc1); cursor:pointer; }
.mono:hover { text-decoration:underline; }
.empty-state { text-align:center; padding:60px 20px; color:var(--txt2); }
.empty-state .ico { font-size:52px; opacity:.2; margin-bottom:14px; display:block; }
.empty-state p { font-size:14px; }
.loading-row td { text-align:center; padding:40px; color:var(--txt2); }
.text-ok { color:var(--ok); } .text-err { color:var(--err); } .text-warn { color:var(--warn); }

/* TRAFFIC BAR */
.traf-bar { height:6px; background:var(--bg4); border-radius:3px; margin-top:4px; overflow:hidden; min-width:80px; }
.traf-fill { height:100%; border-radius:3px; background:var(--grad); transition:width .5s; }

@media (max-width:700px) {
  .sidebar { width:60px; min-width:60px; }
  .sidebar .logo-title, .sidebar .logo-sub, .sidebar .nav-section,
  .nav-item span:last-child, .nav-badge, .theme-row span:first-child + span { display:none; }
  .nav-item { justify-content:center; padding:12px; }
  .content { padding:16px; }
  .cards { grid-template-columns:repeat(2,1fr); }
  .fg-row { grid-template-columns:1fr; }
}
</style>
</head>
<body>
<div id="toast-container"></div>

<!-- LOGIN -->
<div id="pg-login" class="login-wrap">
  <div class="login-card">
    <div class="login-logo">
      <span class="ico">⚡</span>
      <h1>FEDUK Panel</h1>
      <p>Proxy Management System v3.1</p>
    </div>
    <div class="fg">
      <label class="fl">Логин</label>
      <input type="text" id="u-login" class="fi" value="admin" autocomplete="username">
    </div>
    <div class="fg">
      <label class="fl">Пароль</label>
      <input type="password" id="u-pass" class="fi" placeholder="••••••••" autocomplete="current-password">
    </div>
    <button class="login-btn" id="login-btn" onclick="doLogin()">Войти →</button>
    <div id="login-err" class="login-err"></div>
  </div>
</div>

<!-- APP -->
<div id="pg-app" class="layout" style="display:none">
  <nav class="sidebar">
    <div class="logo-area">
      <div class="logo-icon">⚡</div>
      <div>
        <div class="logo-title">FEDUK</div>
        <div class="logo-sub">Proxy Panel v3.1</div>
      </div>
    </div>
    <div class="nav">
      <div class="nav-section">Главное</div>
      <div class="nav-item active" data-page="dashboard"><span class="ico">📊</span><span>Дашборд</span></div>
      <div class="nav-item" data-page="inbounds"><span class="ico">🔌</span><span>Inbounds</span><span class="nav-badge" id="nb-inb">0</span></div>
      <div class="nav-item" data-page="clients"><span class="ico">👥</span><span>Клиенты</span><span class="nav-badge" id="nb-cli">0</span></div>
      <div class="nav-section">Система</div>
      <div class="nav-item" data-page="status"><span class="ico">🔧</span><span>Сервисы</span></div>
      <div class="nav-item" data-page="settings"><span class="ico">⚙️</span><span>Настройки</span></div>
      <div class="nav-item" onclick="logout()"><span class="ico">🚪</span><span>Выйти</span></div>
    </div>
    <div class="sidebar-foot">
      <div class="theme-row" onclick="toggleTheme()">
        <span>🌙</span><span>Тема</span>
        <div class="sw" id="theme-sw"><div class="sw-k"></div></div>
      </div>
    </div>
  </nav>

  <main class="content">
    <!-- DASHBOARD -->
    <div id="pg-dashboard">
      <div class="hdr">
        <div class="page-title">Дашборд <span>состояние системы</span></div>
        <div class="hdr-actions">
          <button class="btn btn-secondary" onclick="loadDashboard()">↻ Обновить</button>
        </div>
      </div>
      <div class="cards">
        <div class="card">
          <div class="card-label">CPU</div>
          <div class="card-value" id="d-cpu">—</div>
          <div class="card-sub">загрузка процессора</div>
          <div class="stat-bar"><div class="stat-bar-fill" id="d-cpu-bar" style="width:0;background:var(--acc1)"></div></div>
          <div class="card-ico">💻</div>
        </div>
        <div class="card">
          <div class="card-label">RAM</div>
          <div class="card-value" id="d-ram">—</div>
          <div class="card-sub" id="d-ram-sub">память</div>
          <div class="stat-bar"><div class="stat-bar-fill" id="d-ram-bar" style="width:0;background:var(--acc2)"></div></div>
          <div class="card-ico">🧠</div>
        </div>
        <div class="card">
          <div class="card-label">Диск</div>
          <div class="card-value" id="d-disk">—</div>
          <div class="card-sub" id="d-disk-sub">хранилище</div>
          <div class="stat-bar"><div class="stat-bar-fill" id="d-disk-bar" style="width:0;background:var(--ok)"></div></div>
          <div class="card-ico">💾</div>
        </div>
        <div class="card">
          <div class="card-label">Аптайм</div>
          <div class="card-value" id="d-uptime">—</div>
          <div class="card-sub">без перезагрузки</div>
          <div class="card-ico">⏱</div>
        </div>
        <div class="card">
          <div class="card-label">Inbounds</div>
          <div class="card-value" id="d-inb">—</div>
          <div class="card-sub">активных каналов</div>
          <div class="card-ico">🔌</div>
        </div>
        <div class="card">
          <div class="card-label">Клиенты</div>
          <div class="card-value" id="d-cli">—</div>
          <div class="card-sub">активных / всего</div>
          <div class="card-ico">👥</div>
        </div>
        <div class="card">
          <div class="card-label">↑ Отдано</div>
          <div class="card-value" id="d-up">—</div>
          <div class="card-sub">исходящий трафик</div>
          <div class="card-ico">📤</div>
        </div>
        <div class="card">
          <div class="card-label">↓ Получено</div>
          <div class="card-value" id="d-down">—</div>
          <div class="card-sub">входящий трафик</div>
          <div class="card-ico">📥</div>
        </div>
      </div>
      <!-- Network graph -->
      <div class="net-card">
        <div class="net-card-hdr">
          <div class="net-card-title">📈 Сетевой трафик (реальное время)</div>
          <div class="net-legend">
            <span><i style="background:#3b82f6"></i>Отправлено</span>
            <span><i style="background:#10b981"></i>Получено</span>
          </div>
        </div>
        <canvas id="net-canvas" height="120"></canvas>
      </div>
    </div>

    <!-- INBOUNDS -->
    <div id="pg-inbounds" style="display:none">
      <div class="hdr">
        <div class="page-title">Inbounds <span>прокси каналы</span></div>
        <div class="hdr-actions">
          <div class="search-box">
            <span>🔍</span>
            <input type="text" id="search-inb" placeholder="Поиск..." oninput="filterInbounds()">
          </div>
          <button class="btn btn-secondary btn-icon" onclick="loadInbounds()" title="Обновить">↻</button>
          <button class="btn btn-primary" onclick="openModal('mo-inbound')">+ Создать</button>
        </div>
      </div>
      <div class="tbl-wrap">
        <div class="tbl-hdr">
          <div><div class="tbl-title">📡 Список inbounds</div><div class="tbl-sub">Управление прокси каналами</div></div>
        </div>
        <div class="tbl-scroll">
          <table>
            <thead><tr>
              <th>#</th><th>Название</th><th>Протокол</th><th>Порт</th>
              <th>Клиенты</th><th>Статус</th><th>Создан</th><th>Действия</th>
            </tr></thead>
            <tbody id="tb-inb"><tr class="loading-row"><td colspan="8">Загрузка...</td></tr></tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- CLIENTS -->
    <div id="pg-clients" style="display:none">
      <div class="hdr">
        <div class="page-title">Клиенты <span>пользователи</span></div>
        <div class="hdr-actions">
          <div class="search-box">
            <span>🔍</span>
            <input type="text" id="search-cli" placeholder="Поиск..." oninput="filterClients()">
          </div>
          <button class="btn btn-secondary btn-icon" onclick="loadClients()" title="Обновить">↻</button>
          <button class="btn btn-primary" onclick="openClientModal()">+ Добавить</button>
        </div>
      </div>
      <div class="tbl-wrap">
        <div class="tbl-hdr">
          <div><div class="tbl-title">👥 Список клиентов</div><div class="tbl-sub">Управление пользователями</div></div>
        </div>
        <div class="tbl-scroll">
          <table>
            <thead><tr>
              <th>#</th><th>Email</th><th>UUID</th><th>Inbound</th>
              <th>Трафик</th><th>Истекает</th><th>Статус</th><th>Действия</th>
            </tr></thead>
            <tbody id="tb-cli"><tr class="loading-row"><td colspan="8">Загрузка...</td></tr></tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- STATUS -->
    <div id="pg-status" style="display:none">
      <div class="hdr">
        <div class="page-title">Сервисы <span>системный статус</span></div>
        <div class="hdr-actions">
          <button class="btn btn-secondary" onclick="loadStatus()">↻ Обновить</button>
        </div>
      </div>
      <div class="tbl-wrap">
        <div class="tbl-hdr"><div class="tbl-title">🔧 Системные сервисы</div></div>
        <table>
          <thead><tr><th>Сервис</th><th>Описание</th><th>Статус</th></tr></thead>
          <tbody id="tb-status"><tr class="loading-row"><td colspan="3">Загрузка...</td></tr></tbody>
        </table>
      </div>
    </div>

    <!-- SETTINGS -->
    <div id="pg-settings" style="display:none">
      <div class="hdr">
        <div class="page-title">Настройки <span>конфигурация панели</span></div>
      </div>
      <div class="settings-section">
        <div class="settings-title">🔑 Данные доступа</div>
        <div class="settings-row">
          <div><div class="settings-label">Адрес панели</div><div class="settings-sub">URL для входа в браузере</div></div>
          <span class="settings-val" id="set-url" onclick="cp(this.textContent)">—</span>
        </div>
        <div class="settings-row">
          <div><div class="settings-label">Логин администратора</div><div class="settings-sub">Имя пользователя для входа</div></div>
          <span class="settings-val" id="set-user" onclick="cp(this.textContent)">admin</span>
        </div>
        <div class="settings-row">
          <div><div class="settings-label">Изменить пароль</div><div class="settings-sub">Обновить пароль администратора</div></div>
          <button class="btn btn-secondary btn-sm" onclick="openModal('mo-chpass')">Изменить</button>
        </div>
      </div>
      <div class="settings-section">
        <div class="settings-title">🌐 Сервер</div>
        <div class="settings-row">
          <div><div class="settings-label">IP сервера</div><div class="settings-sub">Публичный адрес для клиентов</div></div>
          <span class="settings-val" id="set-ip" onclick="cp(this.textContent)">—</span>
        </div>
        <div class="settings-row">
          <div><div class="settings-label">Версия панели</div><div class="settings-sub">FEDUK Proxy Panel</div></div>
          <span class="badge b-blue">v3.1.0</span>
        </div>
      </div>
      <div class="settings-section">
        <div class="settings-title">⚡ Быстрые действия</div>
        <div class="settings-row">
          <div><div class="settings-label">Перезапуск Xray</div><div class="settings-sub">Применить изменения конфигурации</div></div>
          <button class="btn btn-secondary btn-sm" onclick="restartXray()">↻ Перезапустить</button>
        </div>
        <div class="settings-row">
          <div><div class="settings-label">API Документация</div><div class="settings-sub">Swagger UI для разработчиков</div></div>
          <a href="/api/docs" target="_blank" class="btn btn-secondary btn-sm">Открыть →</a>
        </div>
      </div>
    </div>
  </main>
</div>

<!-- MODAL: INBOUND -->
<div class="modal-ov" id="mo-inbound">
  <div class="modal">
    <div class="modal-title">➕ Новый Inbound <span class="modal-close" onclick="closeModal('mo-inbound')">✕</span></div>
    <div class="fg">
      <label class="fl">Название</label>
      <input type="text" id="inb-remark" class="fi" placeholder="Например: Основной VMess">
    </div>
    <div class="fg">
      <label class="fl">Протокол</label>
      <select id="inb-proto" class="fs" onchange="updateProtoHint()">
        <option value="vmess">VMess</option>
        <option value="vless">VLESS</option>
        <option value="trojan">Trojan</option>
        <option value="shadowsocks">Shadowsocks</option>
      </select>
      <div class="proto-hint" id="proto-hint">VMess — стандартный протокол с шифрованием, широкая совместимость</div>
    </div>
    <div class="fg">
      <label class="fl">Порт (1–65535)</label>
      <input type="number" id="inb-port" class="fi" placeholder="10086" min="1" max="65535">
    </div>
    <div class="modal-foot">
      <button class="btn btn-secondary" onclick="closeModal('mo-inbound')">Отмена</button>
      <button class="btn btn-primary" onclick="createInbound()">Создать</button>
    </div>
  </div>
</div>

<!-- MODAL: CLIENT -->
<div class="modal-ov" id="mo-client">
  <div class="modal">
    <div class="modal-title">➕ Новый клиент <span class="modal-close" onclick="closeModal('mo-client')">✕</span></div>
    <div class="fg">
      <label class="fl">Email / Имя</label>
      <input type="text" id="cli-email" class="fi" placeholder="user@example.com">
    </div>
    <div class="fg">
      <label class="fl">Inbound</label>
      <select id="cli-inbound" class="fs"></select>
    </div>
    <div class="fg-row">
      <div class="fg">
        <label class="fl">Лимит трафика (GB, 0=∞)</label>
        <input type="number" id="cli-limit" class="fi" value="0" min="0" step="1">
      </div>
      <div class="fg">
        <label class="fl">Срок действия</label>
        <input type="date" id="cli-expire" class="fi">
      </div>
    </div>
    <div class="modal-foot">
      <button class="btn btn-secondary" onclick="closeModal('mo-client')">Отмена</button>
      <button class="btn btn-primary" onclick="createClient()">Создать</button>
    </div>
  </div>
</div>

<!-- MODAL: QR CODE -->
<div class="modal-ov" id="mo-qr">
  <div class="modal">
    <div class="modal-title">📱 Подключение <span class="modal-close" onclick="closeModal('mo-qr')">✕</span></div>
    <div class="qr-wrap">
      <div class="qr-box" id="qr-render"></div>
      <div style="width:100%">
        <label class="fl">Ссылка для подключения</label>
        <button class="qr-link" id="qr-link-text" onclick="cp(this.textContent)">—</button>
        <div style="font-size:12px;color:var(--txt2);margin-top:6px;text-align:center">Нажмите на ссылку чтобы скопировать</div>
      </div>
    </div>
    <div class="modal-foot">
      <button class="btn btn-secondary" onclick="closeModal('mo-qr')">Закрыть</button>
      <button class="btn btn-primary" onclick="cp($('qr-link-text').textContent)">📋 Копировать</button>
    </div>
  </div>
</div>

<!-- MODAL: CHANGE PASSWORD -->
<div class="modal-ov" id="mo-chpass">
  <div class="modal">
    <div class="modal-title">🔑 Изменить пароль <span class="modal-close" onclick="closeModal('mo-chpass')">✕</span></div>
    <div class="fg">
      <label class="fl">Текущий пароль</label>
      <input type="password" id="cp-old" class="fi" placeholder="••••••••">
    </div>
    <div class="fg">
      <label class="fl">Новый пароль</label>
      <input type="password" id="cp-new" class="fi" placeholder="мин. 8 символов">
    </div>
    <div class="fg">
      <label class="fl">Повторите новый пароль</label>
      <input type="password" id="cp-new2" class="fi" placeholder="••••••••">
    </div>
    <div class="modal-foot">
      <button class="btn btn-secondary" onclick="closeModal('mo-chpass')">Отмена</button>
      <button class="btn btn-primary" onclick="changePassword()">Сохранить</button>
    </div>
  </div>
</div>

<script>
"use strict";
const API = "/api";
let token = localStorage.getItem("feduk_token") || "";
let inbList = [], cliList = [];
let curPage = "dashboard";
let dashTimer = null;
let netHistory = { sent: Array(40).fill(0), recv: Array(40).fill(0) };
let lastNet = null;

// ── UTILS ────────────────────────────────────────────────────
function $(id) { return document.getElementById(id); }
function esc(s) {
  return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;")
    .replace(/>/g,"&gt;").replace(/"/g,"&quot;").replace(/'/g,"&#039;");
}
function fmtB(b) {
  b = Number(b)||0;
  if (b<1024) return b+" B";
  if (b<1048576) return (b/1024).toFixed(1)+" KB";
  if (b<1073741824) return (b/1048576).toFixed(1)+" MB";
  return (b/1073741824).toFixed(2)+" GB";
}
function fmtUptime(s) {
  const d=Math.floor(s/86400), h=Math.floor((s%86400)/3600), m=Math.floor((s%3600)/60);
  return `${d}д ${h}ч ${m}м`;
}
function fmtDate(d) {
  if (!d) return "—";
  try { return new Date(d).toLocaleDateString("ru-RU",{day:"2-digit",month:"2-digit",year:"numeric"}); }
  catch { return d; }
}
function cp(text) {
  navigator.clipboard.writeText(text)
    .then(() => toast("Скопировано!", "success"))
    .catch(() => toast("Не удалось скопировать", "error"));
}
function rndStr(n) {
  const chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  return Array.from(crypto.getRandomValues(new Uint8Array(n))).map(v=>chars[v%chars.length]).join("");
}

// ── API ──────────────────────────────────────────────────────
async function apiFetch(method, path, body) {
  const opts = { method, headers: { Authorization:`Bearer ${token}`, "Content-Type":"application/json" } };
  if (body !== undefined) opts.body = JSON.stringify(body);
  let r;
  try { r = await fetch(API+path, opts); }
  catch (e) { throw new Error("Нет соединения с сервером"); }
  if (r.status===401) { logout(); return null; }
  if (!r.ok) {
    let detail=r.statusText;
    try { const j=await r.json(); detail=j.detail||detail; } catch {}
    throw new Error(detail);
  }
  try { return await r.json(); } catch { return null; }
}

// ── AUTH ─────────────────────────────────────────────────────
async function doLogin() {
  const u=$("u-login").value.trim(), p=$("u-pass").value;
  if (!u||!p) { $("login-err").textContent="Введите логин и пароль"; return; }
  const btn=$("login-btn");
  btn.classList.add("loading"); btn.textContent="Вход..."; $("login-err").textContent="";
  try {
    const fd=new FormData(); fd.append("username",u); fd.append("password",p);
    const r=await fetch(`${API}/auth/token`,{method:"POST",body:fd});
    if (!r.ok) { $("login-err").textContent="Неверный логин или пароль"; return; }
    const d=await r.json();
    token=d.access_token; localStorage.setItem("feduk_token",token);
    showApp();
  } catch(e) { $("login-err").textContent=e.message; }
  finally { btn.classList.remove("loading"); btn.textContent="Войти →"; }
}

function logout() {
  token=""; localStorage.removeItem("feduk_token");
  if (dashTimer) { clearInterval(dashTimer); dashTimer=null; }
  $("pg-app").style.display="none"; $("pg-login").style.display="flex";
  $("u-pass").value=""; $("login-err").textContent="";
}

function showApp() {
  $("pg-login").style.display="none"; $("pg-app").style.display="flex";
  navigate("dashboard");
  loadSettings();
  dashTimer=setInterval(()=>{ if(curPage==="dashboard"&&token) loadDashboard(); },10000);
}

$("u-pass").addEventListener("keydown",e=>{ if(e.key==="Enter") doLogin(); });
$("u-login").addEventListener("keydown",e=>{ if(e.key==="Enter") $("u-pass").focus(); });

// ── NAVIGATION ───────────────────────────────────────────────
function navigate(page) {
  ["dashboard","inbounds","clients","status","settings"].forEach(p=>{
    $("pg-"+p).style.display=(p===page)?"":"none";
  });
  document.querySelectorAll(".nav-item[data-page]").forEach(el=>{
    el.classList.toggle("active",el.dataset.page===page);
  });
  curPage=page;
  if (page==="dashboard") loadDashboard();
  if (page==="inbounds")  loadInbounds();
  if (page==="clients")   loadClients();
  if (page==="status")    loadStatus();
}
document.querySelectorAll(".nav-item[data-page]").forEach(el=>{
  el.addEventListener("click",()=>navigate(el.dataset.page));
});

// ── NETWORK GRAPH ─────────────────────────────────────────────
const cvs = $("net-canvas");
const ctx = cvs ? cvs.getContext("2d") : null;
function drawNetGraph() {
  if (!ctx) return;
  const W=cvs.offsetWidth, H=120;
  cvs.width=W; cvs.height=H;
  ctx.clearRect(0,0,W,H);
  const maxSent=Math.max(...netHistory.sent,1);
  const maxRecv=Math.max(...netHistory.recv,1);
  const maxVal=Math.max(maxSent,maxRecv,1024);
  const pts=netHistory.sent.length;
  const drawLine=(data,color)=>{
    ctx.beginPath();
    ctx.strokeStyle=color; ctx.lineWidth=2;
    data.forEach((v,i)=>{
      const x=i*(W/(pts-1)), y=H-(v/maxVal)*(H-16)-8;
      i===0?ctx.moveTo(x,y):ctx.lineTo(x,y);
    });
    ctx.stroke();
    ctx.lineTo(W,H); ctx.lineTo(0,H); ctx.closePath();
    ctx.fillStyle=color.replace(")",",0.08)").replace("rgb","rgba").replace("#3b82f6","rgba(59,130,246").replace("#10b981","rgba(16,185,129");
    ctx.fill();
  };
  // Grid lines
  ctx.strokeStyle="rgba(255,255,255,0.04)"; ctx.lineWidth=1;
  [0.25,0.5,0.75,1].forEach(f=>{ ctx.beginPath(); ctx.moveTo(0,H*f); ctx.lineTo(W,H*f); ctx.stroke(); });
  drawLine(netHistory.sent,"#3b82f6");
  drawLine(netHistory.recv,"#10b981");
  // Labels
  ctx.fillStyle="rgba(148,163,184,0.6)"; ctx.font="10px Inter,sans-serif";
  ctx.fillText(fmtB(maxVal)+"/s",4,12);
}

// ── DASHBOARD ────────────────────────────────────────────────
async function loadDashboard() {
  try {
    const d=await apiFetch("GET","/dashboard"); if (!d) return;
    const s=d.system, p=d.proxy;
    $("d-cpu").textContent=s.cpu_percent.toFixed(1)+"%";
    setBar("d-cpu-bar",s.cpu_percent,"#3b82f6");
    $("d-ram").textContent=s.mem_percent.toFixed(1)+"%";
    $("d-ram-sub").textContent=fmtB(s.mem_used)+" / "+fmtB(s.mem_total);
    setBar("d-ram-bar",s.mem_percent,"#8b5cf6");
    $("d-disk").textContent=s.disk_percent.toFixed(1)+"%";
    $("d-disk-sub").textContent=fmtB(s.disk_used)+" / "+fmtB(s.disk_total);
    setBar("d-disk-bar",s.disk_percent,"#10b981");
    $("d-uptime").textContent=fmtUptime(s.uptime_seconds);
    $("d-inb").textContent=p.inbounds_total;
    $("d-cli").textContent=p.clients_active+"/"+p.clients_total;
    $("d-up").textContent=p.traffic_up_gb.toFixed(2)+" GB";
    $("d-down").textContent=p.traffic_down_gb.toFixed(2)+" GB";
    // Network graph update
    if (lastNet) {
      const dSent=Math.max(0,s.net_sent-lastNet.sent);
      const dRecv=Math.max(0,s.net_recv-lastNet.recv);
      netHistory.sent.push(dSent); netHistory.sent.shift();
      netHistory.recv.push(dRecv); netHistory.recv.shift();
    }
    lastNet={sent:s.net_sent,recv:s.net_recv};
    drawNetGraph();
  } catch(e) { toast("Ошибка дашборда: "+e.message,"error"); }
}
function setBar(id,pct,color) {
  const el=$(id); if(!el) return;
  el.style.width=Math.min(100,pct)+"%";
  el.style.background=pct>85?"var(--err)":pct>65?"var(--warn)":color;
}

// ── INBOUNDS ─────────────────────────────────────────────────
async function loadInbounds() {
  const tb=$("tb-inb");
  tb.innerHTML='<tr class="loading-row"><td colspan="8">Загрузка...</td></tr>';
  try {
    inbList=await apiFetch("GET","/inbounds")||[];
    $("nb-inb").textContent=inbList.length;
    renderInbounds(inbList);
  } catch(e) {
    tb.innerHTML=`<tr><td colspan="8" style="text-align:center;color:var(--err);padding:30px">${esc(e.message)}</td></tr>`;
    toast(e.message,"error");
  }
}
function renderInbounds(list) {
  const tb=$("tb-inb");
  if (!list.length) {
    tb.innerHTML=`<tr><td colspan="8"><div class="empty-state"><span class="ico">📡</span><p>Нет inbounds — создайте первый!</p></div></td></tr>`;
    return;
  }
  const PCOL={vmess:"b-blue",vless:"b-cyan",trojan:"b-purple",shadowsocks:"b-yellow"};
  tb.innerHTML=list.map((i,idx)=>`<tr>
    <td>${idx+1}</td>
    <td><strong>${esc(i.remark)}</strong><br><span style="font-size:11px;color:var(--txt2);font-family:var(--mono)">${esc(i.tag)}</span></td>
    <td><span class="badge ${PCOL[i.protocol]||'b-blue'}">${esc(i.protocol.toUpperCase())}</span></td>
    <td><strong>${i.port}</strong></td>
    <td>${i.clients_count||0}</td>
    <td><span class="badge ${i.enabled?'b-green':'b-red'}">${i.enabled?'● Активен':'● Выкл'}</span></td>
    <td>${fmtDate(i.created_at)}</td>
    <td><div class="td-actions">
      <button class="btn btn-secondary btn-sm" onclick="toggleInbound(${i.id})">${i.enabled?'Выкл':'Вкл'}</button>
      <button class="btn btn-danger btn-sm" onclick="delInbound(${i.id})">🗑</button>
    </div></td>
  </tr>`).join("");
}
function filterInbounds() {
  const q=$("search-inb").value.toLowerCase();
  const filtered=inbList.filter(i=>i.remark.toLowerCase().includes(q)||i.protocol.toLowerCase().includes(q)||String(i.port).includes(q));
  renderInbounds(filtered);
}

async function createInbound() {
  const remark=$("inb-remark").value.trim();
  const proto=$("inb-proto").value;
  const port=parseInt($("inb-port").value);
  if (!remark) { toast("Введите название","error"); return; }
  if (!port||port<1||port>65535) { toast("Введите корректный порт","error"); return; }
  const sm={vless:{clients:[],decryption:"none"},vmess:{clients:[]},trojan:{clients:[]},shadowsocks:{method:"chacha20-ietf-poly1305",password:rndStr(16),network:"tcp"}};
  try {
    await apiFetch("POST","/inbounds",{remark,protocol:proto,port,settings:sm[proto]||{}});
    closeModal("mo-inbound");
    $("inb-remark").value=""; $("inb-port").value="";
    toast("Inbound создан!","success"); loadInbounds();
  } catch(e) { toast(e.message,"error"); }
}
async function toggleInbound(id) {
  try { await apiFetch("PATCH",`/inbounds/${id}/toggle`); loadInbounds(); }
  catch(e) { toast(e.message,"error"); }
}
async function delInbound(id) {
  if (!confirm("Удалить inbound и всех его клиентов?")) return;
  try { await apiFetch("DELETE","/inbounds/"+id); toast("Inbound удалён","success"); loadInbounds(); }
  catch(e) { toast(e.message,"error"); }
}

// ── CLIENTS ──────────────────────────────────────────────────
async function loadClients() {
  const tb=$("tb-cli");
  tb.innerHTML='<tr class="loading-row"><td colspan="8">Загрузка...</td></tr>';
  try {
    cliList=await apiFetch("GET","/clients")||[];
    const active=cliList.filter(c=>c.enabled).length;
    $("nb-cli").textContent=active;
    renderClients(cliList);
  } catch(e) {
    tb.innerHTML=`<tr><td colspan="8" style="text-align:center;color:var(--err);padding:30px">${esc(e.message)}</td></tr>`;
    toast(e.message,"error");
  }
}
function renderClients(list) {
  const tb=$("tb-cli");
  if (!list.length) {
    tb.innerHTML=`<tr><td colspan="8"><div class="empty-state"><span class="ico">👥</span><p>Нет клиентов — добавьте первого!</p></div></td></tr>`;
    return;
  }
  const inbMap={}; inbList.forEach(i=>inbMap[i.id]=i);
  tb.innerHTML=list.map((c,idx)=>{
    const inb=inbMap[c.inbound_id]||{};
    const total=(c.traffic_up||0)+(c.traffic_down||0);
    const limStr=c.traffic_limit?` / ${fmtB(c.traffic_limit)}`:"";
    const pct=c.traffic_limit?Math.min(100,total/c.traffic_limit*100):0;
    return `<tr>
      <td>${idx+1}</td>
      <td><strong>${esc(c.email)}</strong></td>
      <td><span class="mono" onclick="cp('${esc(c.uuid)}')" title="Копировать UUID">${c.uuid.substring(0,13)}…</span></td>
      <td>${inb.tag?`<span class="badge b-blue">${esc(inb.tag)}</span>`:`#${c.inbound_id}`}</td>
      <td>
        ${fmtB(total)}${limStr}
        ${c.traffic_limit?`<div class="traf-bar"><div class="traf-fill" style="width:${pct}%"></div></div>`:""}
      </td>
      <td>${c.expire_date?fmtDate(c.expire_date):'<span class="badge b-green">∞</span>'}</td>
      <td><span class="badge ${c.enabled?'b-green':'b-red'}">${c.enabled?'● Активен':'● Выкл'}</span></td>
      <td><div class="td-actions">
        <button class="btn btn-secondary btn-sm btn-icon" onclick="showQR(${c.id})" title="QR-код">📱</button>
        <button class="btn btn-secondary btn-sm" onclick="toggleCli(${c.id})">${c.enabled?'Выкл':'Вкл'}</button>
        <button class="btn btn-danger btn-sm" onclick="delCli(${c.id})">🗑</button>
      </div></td>
    </tr>`;
  }).join("");
}
function filterClients() {
  const q=$("search-cli").value.toLowerCase();
  const filtered=cliList.filter(c=>c.email.toLowerCase().includes(q)||c.uuid.toLowerCase().includes(q));
  renderClients(filtered);
}

async function openClientModal() {
  if (!inbList.length) await loadInbounds();
  if (!inbList.length) { toast("Сначала создайте inbound","error"); return; }
  const sel=$("cli-inbound");
  sel.innerHTML=inbList.map(i=>`<option value="${i.id}">${esc(i.remark)} — ${esc(i.protocol.toUpperCase())} :${i.port}</option>`).join("");
  openModal("mo-client");
}
async function createClient() {
  const email=$("cli-email").value.trim();
  const inb_id=parseInt($("cli-inbound").value);
  const limit=(parseInt($("cli-limit").value)||0)*1024**3;
  const expVal=$("cli-expire").value;
  const expire=expVal?new Date(expVal).toISOString():null;
  if (!email) { toast("Введите email","error"); return; }
  try {
    await apiFetch("POST","/clients",{email,inbound_id:inb_id,traffic_limit:limit,expire_date:expire});
    closeModal("mo-client");
    $("cli-email").value=""; $("cli-expire").value="";
    toast("Клиент создан!","success"); loadClients();
  } catch(e) { toast(e.message,"error"); }
}
async function toggleCli(id) {
  try { await apiFetch("PATCH",`/clients/${id}/toggle`); loadClients(); }
  catch(e) { toast(e.message,"error"); }
}
async function delCli(id) {
  if (!confirm("Удалить клиента?")) return;
  try { await apiFetch("DELETE","/clients/"+id); toast("Клиент удалён","success"); loadClients(); }
  catch(e) { toast(e.message,"error"); }
}

// ── QR CODE ──────────────────────────────────────────────────
function showQR(clientId) {
  const c=cliList.find(x=>x.id===clientId); if (!c) return;
  const inb=inbList.find(x=>x.id===c.inbound_id)||{};
  let link="";
  const host=window.location.hostname;
  if (inb.protocol==="vless") {
    link=`vless://${c.uuid}@${host}:${inb.port}?encryption=none&type=tcp#${encodeURIComponent(c.email)}`;
  } else if (inb.protocol==="vmess") {
    const cfg={v:"2",ps:c.email,add:host,port:inb.port,id:c.uuid,aid:0,net:"tcp",type:"none",tls:""};
    link=`vmess://${btoa(JSON.stringify(cfg))}`;
  } else if (inb.protocol==="trojan") {
    link=`trojan://${c.uuid}@${host}:${inb.port}#${encodeURIComponent(c.email)}`;
  } else if (inb.protocol==="shadowsocks") {
    link=`ss://placeholder@${host}:${inb.port}#${encodeURIComponent(c.email)}`;
  } else {
    link=`${inb.protocol}://${c.uuid}@${host}:${inb.port}`;
  }
  const qrBox=$("qr-render");
  qrBox.innerHTML="";
  if (typeof QRCode !== "undefined") {
    new QRCode(qrBox,{text:link,width:200,height:200,colorDark:"#000",colorLight:"#fff",correctLevel:QRCode.CorrectLevel.M});
  } else {
    qrBox.innerHTML=`<div style="padding:20px;color:#666;font-size:12px">QR недоступен</div>`;
  }
  $("qr-link-text").textContent=link;
  openModal("mo-qr");
}

// ── STATUS ───────────────────────────────────────────────────
async function loadStatus() {
  try {
    const d=await apiFetch("GET","/status"); if (!d) return;
    const DESC={"feduk":"FastAPI панель управления","xray-feduk":"Xray-core прокси сервер","nginx":"Обратный прокси / HTTPS","redis-server":"Кэш и сессии"};
    const ICO={"feduk":"⚡","xray-feduk":"🔀","nginx":"🌐","redis-server":"🗄"};
    $("tb-status").innerHTML=Object.entries(d.services).map(([s,ok])=>`
      <tr>
        <td>${ICO[s]||"🔧"} <strong>${s}</strong></td>
        <td>${DESC[s]||""}</td>
        <td><span class="badge ${ok?'b-green':'b-red'}">${ok?'● Работает':'● Остановлен'}</span></td>
      </tr>`).join("");
  } catch(e) { toast(e.message,"error"); }
}

// ── SETTINGS ─────────────────────────────────────────────────
async function loadSettings() {
  try {
    const d=await apiFetch("GET","/dashboard"); if (!d) return;
    $("set-url").textContent=window.location.origin;
    $("set-ip").textContent=window.location.hostname;
  } catch {}
}
async function changePassword() {
  const old=$("cp-old").value, nw=$("cp-new").value, nw2=$("cp-new2").value;
  if (!old||!nw) { toast("Заполните все поля","error"); return; }
  if (nw!==nw2) { toast("Пароли не совпадают","error"); return; }
  if (nw.length<8) { toast("Пароль минимум 8 символов","error"); return; }
  try {
    await apiFetch("POST","/auth/change-password",{old_password:old,new_password:nw});
    closeModal("mo-chpass"); $("cp-old").value=""; $("cp-new").value=""; $("cp-new2").value="";
    toast("Пароль изменён!","success");
  } catch(e) { toast(e.message,"error"); }
}
async function restartXray() {
  try { await apiFetch("POST","/xray/restart"); toast("Xray перезапущен","success"); }
  catch(e) { toast(e.message,"error"); }
}

// ── MODALS ───────────────────────────────────────────────────
function openModal(id) { $(id).classList.add("open"); }
function closeModal(id) { $(id).classList.remove("open"); }
document.querySelectorAll(".modal-ov").forEach(m=>{
  m.addEventListener("click",e=>{ if(e.target===m) m.classList.remove("open"); });
});
document.addEventListener("keydown",e=>{
  if(e.key==="Escape") document.querySelectorAll(".modal-ov.open").forEach(m=>m.classList.remove("open"));
});

// ── PROTO HINT ───────────────────────────────────────────────
const HINTS={vmess:"VMess — стандартный протокол с шифрованием, широкая совместимость",vless:"VLESS — облегчённый протокол, меньше накладных расходов на CPU",trojan:"Trojan — маскируется под легитимный HTTPS трафик",shadowsocks:"Shadowsocks — простой и быстрый протокол шифрования"};
function updateProtoHint() { $("proto-hint").textContent=HINTS[$("inb-proto").value]||""; }

// ── THEME ────────────────────────────────────────────────────
function toggleTheme() {
  const isDark=document.documentElement.getAttribute("data-theme")==="dark";
  const next=isDark?"light":"dark";
  document.documentElement.setAttribute("data-theme",next);
  $("theme-sw").classList.toggle("on",!isDark);
  localStorage.setItem("feduk_theme",next);
}
(function initTheme(){
  const t=localStorage.getItem("feduk_theme")||"dark";
  document.documentElement.setAttribute("data-theme",t);
  if(t==="light") $("theme-sw")?.classList.add("on");
})();

// ── TOAST ────────────────────────────────────────────────────
function toast(msg,type="info") {
  const icons={success:"✅",error:"❌",info:"ℹ️",warning:"⚠️"};
  const el=document.createElement("div");
  el.className=`toast ${type}`;
  el.innerHTML=`<span>${icons[type]||"ℹ️"}</span><span>${esc(String(msg))}</span>`;
  $("toast-container").appendChild(el);
  setTimeout(()=>{ el.classList.add("out"); setTimeout(()=>el.remove(),300); },3500);
}

// ── INIT ─────────────────────────────────────────────────────
if (token) {
  fetch(`${API}/health`,{headers:{Authorization:`Bearer ${token}`}})
    .then(r=>r.ok?showApp():logout()).catch(()=>logout());
}
window.addEventListener("resize",drawNetGraph);
</script>
</body>
</html>
HTMLEOF

    print_ok "Фронтенд создан"
    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 10: NGINX
# ─────────────────────────────────────────────
configure_nginx() {
    print_step "Настройка Nginx"

    # Определяем синтаксис http2 по версии Nginx
    # < 1.25.1 → listen PORT ssl http2;
    # >= 1.25.1 → listen PORT ssl; + http2 on;
    local ngx_ver ngx_maj ngx_min ngx_pat
    ngx_ver=$(nginx -v 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    ngx_maj=$(echo "$ngx_ver" | cut -d. -f1)
    ngx_min=$(echo "$ngx_ver" | cut -d. -f2)
    ngx_pat=$(echo "$ngx_ver" | cut -d. -f3)
    ngx_pat="${ngx_pat:-0}"  # Защита от пустого значения

    local http2_listen http2_extra=""
    if [[ "$ngx_maj" -gt 1 ]] \
    || { [[ "$ngx_maj" -eq 1 ]] && [[ "$ngx_min" -gt 25 ]]; } \
    || { [[ "$ngx_maj" -eq 1 ]] && [[ "$ngx_min" -eq 25 ]] && [[ "$ngx_pat" -ge 1 ]]; }; then
        http2_listen="${PANEL_PORT} ssl"
        http2_extra="    http2 on;"
    else
        http2_listen="${PANEL_PORT} ssl http2"
        http2_extra=""
    fi
    log_info "Nginx ${ngx_ver}: listen='${http2_listen}' extra='${http2_extra}'"

    local NGINX_SERVER_NAME="_"
    [[ -n "$DOMAIN" ]] && NGINX_SERVER_NAME="$DOMAIN"

    cat > /etc/nginx/sites-available/feduk << NGINXEOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen ${HTTP_PORT};
    server_name ${NGINX_SERVER_NAME};
    return 301 https://\$host\$request_uri;
}

server {
    listen ${http2_listen};
${http2_extra}
    server_name ${NGINX_SERVER_NAME};

    ssl_certificate     ${INSTALL_DIR}/certs/cert.pem;
    ssl_certificate_key ${INSTALL_DIR}/certs/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
    add_header X-Content-Type-Options    nosniff                                always;
    add_header X-Frame-Options           SAMEORIGIN                             always;
    add_header X-XSS-Protection          "1; mode=block"                        always;

    access_log ${INSTALL_DIR}/logs/nginx-access.log;
    error_log  ${INSTALL_DIR}/logs/nginx-error.log warn;
    client_max_body_size 50m;

    # WebSocket поддержка
    location /ws/ {
        proxy_pass         http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection \$connection_upgrade;
        proxy_set_header   Host       \$host;
        proxy_set_header   X-Real-IP  \$remote_addr;
        proxy_read_timeout 86400;
    }

    # API и SPA
    location / {
        proxy_pass            http://127.0.0.1:8000;
        proxy_http_version    1.1;
        proxy_set_header      Host              \$host;
        proxy_set_header      X-Real-IP         \$remote_addr;
        proxy_set_header      X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header      X-Forwarded-Proto \$scheme;
        proxy_read_timeout    120s;
        proxy_connect_timeout 30s;
        proxy_send_timeout    120s;
        # Буферизация для производительности
        proxy_buffering       on;
        proxy_buffer_size     4k;
        proxy_buffers         8 4k;
    }
}
NGINXEOF

    ln -sf /etc/nginx/sites-available/feduk /etc/nginx/sites-enabled/feduk
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    nginx -t >> "$LOG_FILE" 2>&1 || die "Nginx конфиг невалидный. Лог: ${LOG_FILE}"

    systemctl enable nginx  >> "$LOG_FILE" 2>&1
    systemctl restart nginx >> "$LOG_FILE" 2>&1

    print_ok "Nginx настроен (v${ngx_ver})"
    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 11: КОНФИГ ПРИЛОЖЕНИЯ
# ─────────────────────────────────────────────
create_app_config() {
    print_step "Конфигурация приложения"

    local secret_key
    secret_key=$(openssl rand -hex 32)

    cat > "${CONFIG_DIR}/config.yml" << CFGEOF
version: "3.1"
secret_key: "${secret_key}"
admin_user: "${ADMIN_USER}"
server_host: "${SERVER_IP}"
panel_port: ${PANEL_PORT}
xray_api_host: "127.0.0.1"
xray_api_port: 10085
redis_host: "127.0.0.1"
redis_port: 6379
log_level: "info"
CFGEOF

    chmod 640 "${CONFIG_DIR}/config.yml"
    print_ok "Конфиг: ${CONFIG_DIR}/config.yml"
    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 12: REDIS
# ─────────────────────────────────────────────
configure_redis() {
    print_step "Redis"

    run_step_soft "Запуск Redis" bash -c "
        systemctl enable redis-server
        systemctl restart redis-server
    "

    # Ждём Redis до 10 секунд
    local i=0
    while [[ $i -lt 10 ]]; do
        if redis-cli ping 2>/dev/null | grep -q PONG; then
            print_ok "Redis: 127.0.0.1:6379 — OK"
            break
        fi
        sleep 1
        i=$((i+1))
    done
    if [[ $i -ge 10 ]]; then
        print_warn "Redis не отвечает — панель запустится без кэша"
    fi
    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 13: SYSTEMD СЕРВИСЫ
# ─────────────────────────────────────────────
create_systemd_services() {
    print_step "Systemd сервисы"

    cat > /etc/systemd/system/xray-feduk.service << 'XSVC'
[Unit]
Description=FEDUK Xray-core
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
ExecStart=/opt/feduk/xray/bin/xray run -config /opt/feduk/xray/configs/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
LimitNPROC=512

[Install]
WantedBy=multi-user.target
XSVC

    cat > /etc/systemd/system/feduk.service << PSVC
[Unit]
Description=FEDUK Proxy Panel
Documentation=https://github.com/XTLS/Xray-core
After=network.target redis-server.service xray-feduk.service
Wants=redis-server.service xray-feduk.service

[Service]
Type=exec
User=root
WorkingDirectory=${INSTALL_DIR}/panel
Environment="PATH=${INSTALL_DIR}/panel/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=${INSTALL_DIR}/panel/venv/bin/uvicorn main:app \\
    --host 127.0.0.1 \\
    --port 8000 \\
    --workers 2 \\
    --log-level info \\
    --no-access-log
Restart=always
RestartSec=5s
LimitNOFILE=65536
StandardOutput=append:${INSTALL_DIR}/logs/panel.log
StandardError=append:${INSTALL_DIR}/logs/panel-error.log

[Install]
WantedBy=multi-user.target
PSVC

    systemctl daemon-reload >> "$LOG_FILE" 2>&1

    run_step "Запуск Xray-core" bash -c "
        systemctl enable xray-feduk
        systemctl restart xray-feduk
    "

    run_step "Запуск FEDUK Panel" bash -c "
        systemctl enable feduk
        systemctl restart feduk
    "

    print_ok "Сервисы: xray-feduk, feduk"
    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 14: ИНИЦИАЛИЗАЦИЯ ADMIN В БД
#  Ждём реальной готовности FastAPI через /api/health
# ─────────────────────────────────────────────
init_admin_db() {
    print_step "Создание администратора"

    # Ждём готовности FastAPI (до 30 секунд)
    start_spinner "Ожидание запуска FastAPI..."
    local i=0
    local ready=false
    while [[ $i -lt 30 ]]; do
        if curl -sk --max-time 2 "http://127.0.0.1:8000/api/health" &>/dev/null; then
            ready=true
            break
        fi
        sleep 1
        i=$((i+1))
    done
    stop_spinner

    if [[ "$ready" == "false" ]]; then
        print_warn "FastAPI не ответил за 30 сек — пробуем через Python напрямую"
    fi

    local PY="${INSTALL_DIR}/panel/venv/bin/python3"

    # Записываем скрипт во временный файл — избегаем проблем с кавычками в heredoc
    local init_script
    init_script=$(mktemp /tmp/feduk_init_XXXXXX.py)

    cat > "$init_script" << INITEOF
import sys, os, warnings
warnings.filterwarnings("ignore")
sys.path.insert(0, "${INSTALL_DIR}/panel")
os.chdir("${INSTALL_DIR}/panel")

import bcrypt as _b
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Импортируем модели
from main import Base, AdminUser

engine = create_engine(
    "sqlite:///${INSTALL_DIR}/data/config.db",
    connect_args={"check_same_thread": False}
)
Base.metadata.create_all(bind=engine)
Session = sessionmaker(bind=engine)
db = Session()

pw = "${ADMIN_PASS}".encode("utf-8")[:72]
hashed = _b.hashpw(pw, _b.gensalt(12)).decode("utf-8")

existing = db.query(AdminUser).filter(AdminUser.username == "${ADMIN_USER}").first()
if existing:
    existing.password_hash = hashed
    existing.is_active = True
    db.commit()
    print("Администратор обновлён")
else:
    db.add(AdminUser(username="${ADMIN_USER}", password_hash=hashed, is_active=True))
    db.commit()
    print("Администратор создан")

# Верификация пароля
row = db.query(AdminUser).filter(AdminUser.username == "${ADMIN_USER}").first()
ok = _b.checkpw(pw, row.password_hash.encode("utf-8"))
if not ok:
    print("ОШИБКА: верификация пароля провалена!", file=sys.stderr)
    sys.exit(1)
print("Верификация: OK")
db.close()
INITEOF

    if "$PY" "$init_script" >> "$LOG_FILE" 2>&1; then
        print_ok "Администратор: ${ADMIN_USER}"
    else
        print_warn "Ошибка инициализации, перезапуск сервиса..."
        systemctl restart feduk >> "$LOG_FILE" 2>&1 || true
        sleep 5
        "$PY" "$init_script" >> "$LOG_FILE" 2>&1 \
            && print_ok "Повторная попытка: OK" \
            || print_err "Не удалось создать администратора. Смотри: ${LOG_FILE}"
    fi

    rm -f "$init_script"
    log_info "Admin DB init completed"
    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 15: УТИЛИТЫ
# ─────────────────────────────────────────────
setup_extras() {
    print_step "Утилиты и автоматизация"

    # feduk-status
    cat > /usr/local/bin/feduk-status << 'EOF'
#!/bin/bash
C="\033[38;5;33m"; G="\033[32m"; R="\033[31m"; Y="\033[33m"; X="\033[0m"; B="\033[1m"
echo -e "${C}${B}══════════════════════════════════════${X}"
echo -e "${C}${B}   FEDUK Panel — Статус сервисов       ${X}"
echo -e "${C}${B}══════════════════════════════════════${X}"
for s in feduk xray-feduk nginx redis-server; do
    if systemctl is-active --quiet "$s" 2>/dev/null; then
        echo -e " ${G}✓${X} ${B}${s}${X}"
    else
        echo -e " ${R}✗${X} ${B}${s}${X} ${Y}(остановлен)${X}"
    fi
done
echo -e "${C}──────────────────────────────────────${X}"
echo -e " CPU : $(top -bn1 | grep '%Cpu' | awk '{printf "%.1f%%", $2}' 2>/dev/null || echo '?')"
echo -e " RAM : $(free -h | awk '/^Mem/{print $3"/"$2}' 2>/dev/null || echo '?')"
echo -e " Диск: $(df -h /opt/feduk 2>/dev/null | tail -1 | awk '{print $3"/"$2" ("$5")"}')"
echo -e "${C}──────────────────────────────────────${X}"
if [[ -f /root/.feduk_credentials ]]; then
    grep -E 'PANEL_URL|ADMIN_USER|ADMIN_PASS' /root/.feduk_credentials | sed 's/^/  /'
fi
echo -e "${C}══════════════════════════════════════${X}"
EOF
    chmod +x /usr/local/bin/feduk-status

    # feduk-backup
    cat > /usr/local/bin/feduk-backup << 'EOF'
#!/bin/bash
TS=$(date +%Y%m%d_%H%M%S)
FILE="/opt/feduk/backups/backup_${TS}.tar.gz"
tar -czf "$FILE" \
    /opt/feduk/data \
    /etc/feduk \
    /opt/feduk/xray/configs \
    2>/dev/null
SIZE=$(du -sh "$FILE" 2>/dev/null | cut -f1)
echo "✓ Бэкап: ${FILE} (${SIZE})"
# Удаляем бэкапы старше 30 дней
find /opt/feduk/backups -name "backup_*.tar.gz" -mtime +30 -delete 2>/dev/null || true
EOF
    chmod +x /usr/local/bin/feduk-backup

    # feduk-log (быстрый просмотр логов)
    cat > /usr/local/bin/feduk-log << 'EOF'
#!/bin/bash
case "${1:-panel}" in
    panel)   journalctl -u feduk -f --no-pager ;;
    xray)    journalctl -u xray-feduk -f --no-pager ;;
    nginx)   tail -f /opt/feduk/logs/nginx-access.log ;;
    errors)  tail -f /opt/feduk/logs/panel-error.log ;;
    all)     journalctl -u feduk -u xray-feduk -u nginx -f --no-pager ;;
    *)       echo "Использование: feduk-log [panel|xray|nginx|errors|all]" ;;
esac
EOF
    chmod +x /usr/local/bin/feduk-log

    # Logrotate
    cat > /etc/logrotate.d/feduk << 'EOF'
/opt/feduk/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    copytruncate
    sharedscripts
    postrotate
        systemctl reload nginx 2>/dev/null || true
    endscript
}
EOF

    # Cron: бэкап в 3:00, обновление geo-данных в воскресенье 4:00
    crontab -l 2>/dev/null | grep -v feduk > /tmp/feduk_cron || true
    cat >> /tmp/feduk_cron << 'CRONEOF'
0 3 * * * /usr/local/bin/feduk-backup >> /opt/feduk/logs/backup.log 2>&1
0 4 * * 0 wget -qO /opt/feduk/xray/configs/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat && systemctl restart xray-feduk >> /opt/feduk/logs/backup.log 2>&1
CRONEOF
    crontab /tmp/feduk_cron 2>/dev/null || true
    rm -f /tmp/feduk_cron

    # Сохраняем данные доступа
    local panel_url
    if [[ -n "$DOMAIN" ]] && [[ "$USE_LETSENCRYPT" == true ]]; then
        panel_url="https://${DOMAIN}"
    else
        panel_url="https://${SERVER_IP}"
    fi
    [[ "${PANEL_PORT}" != "443" ]] && panel_url="${panel_url}:${PANEL_PORT}"

    cat > "$CRED_FILE" << CREDEOF
# ════════════════════════════════════════════════
#   FEDUK PROXY PANEL — ДАННЫЕ ДОСТУПА
#   Создано: $(date)
# ════════════════════════════════════════════════
PANEL_URL=${panel_url}
ADMIN_USER=${ADMIN_USER}
ADMIN_PASS=${ADMIN_PASS}
SERVER_IP=${SERVER_IP}
DOMAIN=${DOMAIN:-none}
SSL=${USE_LETSENCRYPT}
INSTALL_DIR=${INSTALL_DIR}
# ════════════════════════════════════════════════
CREDEOF
    chmod 600 "$CRED_FILE"

    print_ok "Команды: feduk-status, feduk-backup, feduk-log"
    print_ok "Авто-бэкап: ежедневно 03:00"
    print_ok "Данные: ${CRED_FILE}"
    progress_bar
}

# ─────────────────────────────────────────────
#  ШАГ 16: HEALTH CHECK
# ─────────────────────────────────────────────
health_check() {
    print_step "Проверка работоспособности"

    sleep 3

    for svc in feduk xray-feduk nginx redis-server; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            print_ok "Сервис: ${svc} — активен"
        else
            print_warn "Сервис: ${svc} — не запущен"
            log_warn "Service ${svc} is not active"
        fi
    done

    echo
    # Проверяем API
    sleep 2
    if curl -sk --max-time 10 "https://127.0.0.1:${PANEL_PORT}/api/health" &>/dev/null; then
        print_ok "API отвечает на порту ${PANEL_PORT} ✓"
    else
        print_warn "API ещё не готов (подождите 30–60 сек)"
    fi

    progress_bar
}

# ─────────────────────────────────────────────
#  ФИНАЛЬНЫЙ ЭКРАН
# ─────────────────────────────────────────────
show_summary() {
    local panel_url
    if [[ -n "$DOMAIN" ]] && [[ "$USE_LETSENCRYPT" == true ]]; then
        panel_url="https://${DOMAIN}"
    else
        panel_url="https://${SERVER_IP}"
    fi
    [[ "${PANEL_PORT}" != "443" ]] && panel_url="${panel_url}:${PANEL_PORT}"

    echo
    echo -e "${C1}${BOLD}╔══════════════════════════════════════════════════════════════╗${R}"
    echo -e "${C2}${BOLD}║         ✅  FEDUK PROXY PANEL — ГОТОВ К РАБОТЕ  ✅          ║${R}"
    echo -e "${C3}${BOLD}╠══════════════════════════════════════════════════════════════╣${R}"
    echo -e "${C4}${BOLD}║                                                              ║${R}"
    printf  "${C4}${BOLD}║${R}  ${GREEN}${BOLD}🌐 URL      :${R} ${WHITE}${BOLD}%-48s${C4}${BOLD}║${R}\n" "${panel_url}"
    printf  "${C4}${BOLD}║${R}  ${GREEN}${BOLD}👤 Логин    :${R} ${WHITE}${BOLD}%-48s${C4}${BOLD}║${R}\n" "${ADMIN_USER}"
    printf  "${C4}${BOLD}║${R}  ${GREEN}${BOLD}🔑 Пароль   :${R} ${WHITE}${BOLD}%-48s${C4}${BOLD}║${R}\n" "${ADMIN_PASS}"
    echo -e "${C4}${BOLD}║                                                              ║${R}"
    echo -e "${C5}${BOLD}╠══════════════════════════════════════════════════════════════╣${R}"
    printf  "${C5}${BOLD}║${R}  ${CYAN}📁 Данные   :${R} %-48s${C5}${BOLD}║${R}\n" "${CRED_FILE}"
    printf  "${C5}${BOLD}║${R}  ${CYAN}📊 Статус   :${R} %-48s${C5}${BOLD}║${R}\n" "feduk-status"
    printf  "${C5}${BOLD}║${R}  ${CYAN}💾 Бэкап    :${R} %-48s${C5}${BOLD}║${R}\n" "feduk-backup"
    printf  "${C5}${BOLD}║${R}  ${CYAN}📋 Логи     :${R} %-48s${C5}${BOLD}║${R}\n" "feduk-log [panel|xray|nginx|errors]"
    echo -e "${C6}${BOLD}╠══════════════════════════════════════════════════════════════╣${R}"
    echo -e "${C6}${BOLD}║${R}  ${DIM}VMess · VLESS · Trojan · Shadowsocks · Reality             ${C6}${BOLD}║${R}"
    echo -e "${C6}${BOLD}╚══════════════════════════════════════════════════════════════╝${R}"
    echo
    echo -e "  ${GREEN}${BOLD}Панель:${R} ${WHITE}${BOLD}${panel_url}${R}"
    if [[ "$USE_LETSENCRYPT" == true ]] && [[ -n "$DOMAIN" ]]; then
        echo -e "  ${GREEN}✅ SSL: Let's Encrypt — сертификат доверенный, браузер не предупредит${R}"
    else
        echo -e "  ${YELLOW}⚠  SSL: самоподписанный — браузер предупредит, нажмите «Продолжить»${R}"
        echo -e "  ${DIM}   Для настоящего сертификата повторите установку с доменом${R}"
    fi
    echo
}

# ─────────────────────────────────────────────
#  TRAP / CLEANUP
# ─────────────────────────────────────────────
cleanup() {
    stop_spinner
}
trap cleanup EXIT INT TERM

# ═════════════════════════════════════════════
#  MAIN
# ═════════════════════════════════════════════
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    : > "$LOG_FILE"
    log_info "FEDUK Panel installer v${PANEL_VERSION} started at $(date)"

    show_banner
    echo -e "${C3}${BOLD}  Полностью автоматическая установка...${R}\n"
    sleep 1

    preflight            # 1
    install_packages     # 2
    configure_firewall   # 3
    create_directories   # 4
    install_xray         # 5
    setup_ssl            # 6
    create_xray_config   # 7
    setup_python_backend # 8
    create_frontend      # 9
    configure_nginx      # 10
    create_app_config    # 11
    configure_redis      # 12
    create_systemd_services # 13
    init_admin_db        # 14
    setup_extras         # 15
    health_check         # 16

    show_summary
    log_info "Installation finished successfully at $(date)"
}

main "$@"
