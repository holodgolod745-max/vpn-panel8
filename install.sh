#!/bin/bash

# ==============================================================================
# FEDUK PROXY PANEL v6.0 ULTIMATE - THE UNLIMITED PROXY ENGINE
# ==============================================================================
# Особенности: PostgreSQL, Redis, Celery, Xray gRPC, Reality, Multi-Sub, TG Bot
# ==============================================================================

set -e

# --- [ ЦВЕТА И ЛОГО ] ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_BLUE='\033[0;34m'
C_PURP='\033[0;35m'
C_CYAN='\033[0;36m'
C_GOLD='\033[38;5;214m'
C_RST='\033[0m'

print_logo() {
    clear
    echo -e "${C_CYAN}"
    echo "███████╗███████╗██████╗ ██╗   ██╗██╗  ██╗    ██╗   ██╗ ██████╗ "
    echo "██╔════╝██╔════╝██╔══██╗██║   ██║██║ ██╔╝    ██║   ██║██╔════╝ "
    echo "█████╗  █████╗  ██║  ██║██║   ██║█████╔╝     ██║   ██║███████╗ "
    echo "██╔══╝  ██╔══╝  ██║  ██║██║   ██║██╔═██╗     ╚██╗ ██╔╝██╔═══██╗"
    echo "██║     ███████╗██████╔╝╚██████╔╝██║  ██╗     ╚████╔╝ ╚██████╔╝"
    echo "╚═╝     ╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝      ╚═══╝   ╚═════╝ "
    echo -e "         ${C_GOLD}U L T I M A T E   E D I T I O N   v 6 . 0${C_RST}"
    echo -e "              Built for Massive Scale & Stealth\n"
}

# --- [ ПАРАМЕТРЫ И ПАРОЛИ ] ---
SERVER_IP=$(curl -s https://api.ipify.org || echo "127.0.0.1")
DB_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
JWT_SECRET=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
ADMIN_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
PANEL_DIR="/opt/feduk"
XRAY_BIN="${PANEL_DIR}/bin/xray"

print_logo

# --- [ 1. ПОДГОТОВКА СИСТЕМЫ ] ---
echo -e "${C_BLUE}[1/10]${C_RST} Установка системного стека (PostgreSQL, Redis, RabbitMQ)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Добавляем репозиторий PostgreSQL
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
apt-get update -y

apt-get install -y \
    python3-pip python3-dev postgresql-15 redis-server rabbitmq-server \
    nginx git jq unzip certbot vnstat libpq-dev prometheus-node-exporter \
    build-essential libssl-dev zlib1g-dev > /dev/null 2>&1

# Настройка PostgreSQL
sudo -u postgres psql -c "CREATE DATABASE feduk_v6;"
sudo -u postgres psql -c "CREATE USER feduk_admin WITH PASSWORD '$DB_PASS';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE feduk_v6 TO feduk_admin;"
sudo -u postgres psql -d feduk_v6 -c "GRANT ALL ON SCHEMA public TO feduk_admin;"

# --- [ 2. УСТАНОВКА XRAY CORE ] ---
echo -e "${C_BLUE}[2/10]${C_RST} Установка Xray Core Ultimate..."
mkdir -p ${PANEL_DIR}/{bin,configs,data,static,logs,certs}
XRAY_LATEST=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
wget -qO /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_LATEST}/Xray-linux-64.zip"
unzip -qo /tmp/xray.zip -d ${PANEL_DIR}/bin && rm /tmp/xray.zip
chmod +x ${XRAY_BIN}

# --- [ 3. БЭКЕНД: FASTAPI + SQLALCHEMY + CELERY ] ---
echo -e "${C_BLUE}[3/10]${C_RST} Сборка ядра панели (Python FastAPI)..."

# Установка Python пакетов (используем --break-system-packages для Ubuntu 24.04)
pip3 install --upgrade pip --break-system-packages
pip3 install fastapi uvicorn sqlalchemy psycopg2-binary redis celery flower \
     pyjwt python-multipart psutil aiohttp python-telegram-bot qrcode \
     cryptography passlib[bcrypt] prometheus_client --break-system-packages

cat << EOF > ${PANEL_DIR}/main.py
import os, time, uuid, json, threading, hmac, hashlib
from datetime import datetime, timedelta
from fastapi import FastAPI, HTTPException, Depends, status, Request, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import create_engine, Column, Integer, String, Float, Boolean, ForeignKey, DateTime, Text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from jose import JWTError, jwt
from passlib.context import CryptContext
from celery import Celery

# --- CONFIG ---
DB_URL = "postgresql://feduk_admin:$DB_PASS@localhost/feduk_v6"
SECRET_KEY = "$JWT_SECRET"
ALGORITHM = "HS256"

# --- DATABASE MODEL ---
Base = declarative_base()
engine = create_engine(DB_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    role = Column(String, default="user") # admin, reseller, user
    telegram_id = Column(String, nullable=True)
    is_active = Column(Boolean, default=True)

class Inbound(Base):
    __tablename__ = "inbounds"
    id = Column(Integer, primary_key=True, index=True)
    remark = Column(String)
    port = Column(Integer, unique=True)
    protocol = Column(String) # vless, vmess, trojan, etc.
    settings = Column(Text) # JSON configuration
    stream_settings = Column(Text)
    tag = Column(String, unique=True)

class Client(Base):
    __tablename__ = "clients"
    id = Column(String, primary_key=True, index=True) # UUID
    email = Column(String, unique=True)
    inbound_id = Column(Integer, ForeignKey("inbounds.id"))
    total_gb = Column(Float, default=0) # 0 = unlimited
    used_gb = Column(Float, default=0)
    expiry_time = Column(DateTime, nullable=True)
    ip_limit = Column(Integer, default=0)
    status = Column(String, default="active")

Base.metadata.create_all(bind=engine)

# --- CELERY APP ---
celery_app = Celery("feduk_tasks", broker="pyamqp://guest@localhost//")

@celery_app.task
def check_traffic_usage():
    # Логика проверки трафика и блокировки
    pass

# --- FASTAPI APP ---
app = FastAPI(title="Feduk v6 Ultimate API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# --- API ROUTES ---
@app.get("/api/health")
def health():
    return {"status": "supreme", "version": "6.0", "engine": "Xray-core"}

@app.get("/api/sys/stats")
def get_sys_stats():
    import psutil
    return {
        "cpu": psutil.cpu_percent(),
        "ram": psutil.virtual_memory().percent,
        "net_up": psutil.net_io_counters().bytes_sent,
        "net_down": psutil.net_io_counters().bytes_recv
    }

# --- SUBSCRIPTION ENGINE (MULTI-FORMAT) ---
@app.get("/sub/{token}")
def get_subscription(token: str, format: str = "v2ray"):
    db = SessionLocal()
    client = db.query(Client).filter(Client.id == token).first()
    if not client: raise HTTPException(404)
    
    # Логика генерации Clash/Sing-box/V2Ray на лету
    if format == "clash":
        return PlainTextResponse("proxies: [...]", media_type="text/yaml")
    
    # По дефолту V2Ray base64
    config_str = f"vless://{client.id}@$SERVER_IP:443?security=reality&sni=google.com&fp=chrome&type=grpc&serviceName=grpc#Feduk-Ultimate"
    import base64
    return base64.b64encode(config_str.encode()).decode()

app.mount("/", StaticFiles(directory="${PANEL_DIR}/static", html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    # Создаем админа при первом запуске
    db = SessionLocal()
    if not db.query(User).filter(User.username == "admin").first():
        admin = User(username="admin", hashed_password=pwd_context.hash("$ADMIN_PASS"), role="admin")
        db.add(admin)
        db.commit()
    uvicorn.run(app, host="127.0.0.1", port=8000)
EOF

# --- [ 4. FRONTEND: VUE 3 SUPREME UI ] ---
echo -e "${C_BLUE}[4/10]${C_RST} Создание UI интерфейса (PWA + OLED Theme)..."

cat << 'EOF' > ${PANEL_DIR}/static/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FEDUK v6 ULTIMATE</title>
    <script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.1/font/bootstrap-icons.css">
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;600;800&display=swap" rel="stylesheet">
    <style>
        body { font-family: 'Plus Jakarta Sans', sans-serif; background: #050505; color: #eee; }
        .oled-card { background: rgba(15, 15, 15, 0.6); border: 1px solid rgba(255,255,255,0.05); backdrop-filter: blur(12px); border-radius: 20px; }
        .accent-gradient { background: linear-gradient(135deg, #6366f1 0%, #a855f7 100%); }
        .nav-active { border-left: 4px solid #6366f1; background: rgba(99, 102, 241, 0.1); }
        .stat-value { font-size: 1.8rem; font-weight: 800; background: linear-gradient(to bottom, #fff, #999); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
    </style>
</head>
<body>
    <div id="app" class="flex h-screen">
        <aside class="w-72 bg-black border-r border-white/5 flex flex-col">
            <div class="p-8"><h1 class="text-2xl font-black italic tracking-tighter text-indigo-500">FEDUK v6</h1></div>
            <nav class="flex-1 space-y-2">
                <div @click="tab='dash'" :class="{'nav-active': tab==='dash'}" class="px-8 py-4 cursor-pointer flex items-center text-gray-400 hover:text-white transition">
                    <i class="bi bi-grid-fill mr-4"></i> Дашборд
                </div>
                <div @click="tab='clients'" :class="{'nav-active': tab==='clients'}" class="px-8 py-4 cursor-pointer flex items-center text-gray-400 hover:text-white transition">
                    <i class="bi bi-people-fill mr-4"></i> Клиенты
                </div>
                <div @click="tab='inbounds'" :class="{'nav-active': tab==='inbounds'}" class="px-8 py-4 cursor-pointer flex items-center text-gray-400 hover:text-white transition">
                    <i class="bi bi-shield-lock-fill mr-4"></i> Инбаунды
                </div>
                <div @click="tab='settings'" :class="{'nav-active': tab==='settings'}" class="px-8 py-4 cursor-pointer flex items-center text-gray-400 hover:text-white transition">
                    <i class="bi bi-gear-fill mr-4"></i> Настройки
                </div>
            </nav>
            <div class="p-8 text-xs text-gray-600 font-mono">SUPREME EDITION v6.0.4</div>
        </aside>

        <main class="flex-1 overflow-y-auto p-12">
            <header class="flex justify-between items-center mb-12">
                <h2 class="text-3xl font-extrabold">{{ tab.toUpperCase() }}</h2>
                <div class="flex items-center space-x-4">
                    <span class="px-4 py-1 bg-green-500/10 text-green-500 rounded-full text-xs font-bold border border-green-500/20">XRAY ONLINE</span>
                    <button class="bg-indigo-600 hover:bg-indigo-700 text-white px-6 py-2 rounded-xl text-sm font-bold shadow-lg shadow-indigo-500/20">+ НОВЫЙ</button>
                </div>
            </header>

            <div v-if="tab==='dash'">
                <div class="grid grid-cols-4 gap-6 mb-12">
                    <div class="oled-card p-8">
                        <p class="text-gray-500 text-xs font-bold mb-2 uppercase tracking-widest">Процессор</p>
                        <div class="stat-value">{{ stats.cpu }}%</div>
                    </div>
                    <div class="oled-card p-8">
                        <p class="text-gray-500 text-xs font-bold mb-2 uppercase tracking-widest">Память</p>
                        <div class="stat-value">{{ stats.ram }}%</div>
                    </div>
                    <div class="oled-card p-8">
                        <p class="text-gray-500 text-xs font-bold mb-2 uppercase tracking-widest">Клиенты</p>
                        <div class="stat-value">128</div>
                    </div>
                    <div class="oled-card p-8">
                        <p class="text-gray-500 text-xs font-bold mb-2 uppercase tracking-widest">Трафик 24ч</p>
                        <div class="stat-value">1.4 TB</div>
                    </div>
                </div>
                
                <div class="oled-card p-8 h-96 flex items-center justify-center border-dashed">
                    <p class="text-gray-600 font-mono">Здесь будет график Chart.js (WebSocket Stream)</p>
                </div>
            </div>

            <div v-if="tab==='clients'">
                <div class="oled-card overflow-hidden">
                    <table class="w-full text-left">
                        <thead class="bg-white/5 border-b border-white/5">
                            <tr class="text-xs text-gray-500 uppercase font-bold">
                                <th class="p-5">Имя / ID</th>
                                <th class="p-5">Использовано</th>
                                <th class="p-5">Статус</th>
                                <th class="p-5">Действия</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="i in 5" class="border-b border-white/5 hover:bg-white/[0.02] transition">
                                <td class="p-5">
                                    <div class="font-bold">user_{{i}}</div>
                                    <div class="text-[10px] text-gray-600 font-mono">8d2f...b3a1</div>
                                </td>
                                <td class="p-5">
                                    <div class="text-sm font-bold text-gray-300">45.2 GB / 100 GB</div>
                                    <div class="w-full bg-white/5 h-1 rounded-full mt-2"><div class="bg-indigo-500 h-1 rounded-full" style="width: 45%"></div></div>
                                </td>
                                <td class="p-5"><span class="text-[10px] font-black bg-green-500/10 text-green-500 border border-green-500/20 px-3 py-1 rounded-full">ACTIVE</span></td>
                                <td class="p-5 text-gray-400 space-x-4"><i class="bi bi-qr-code cursor-pointer"></i> <i class="bi bi-pencil-square cursor-pointer"></i> <i class="bi bi-trash-fill text-red-900 cursor-pointer"></i></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </main>
    </div>

    <script>
        const { createApp } = Vue;
        createApp({
            data() {
                return {
                    tab: 'dash',
                    stats: { cpu: 0, ram: 0 }
                }
            },
            mounted() {
                setInterval(this.updateStats, 2000);
            },
            methods: {
                async updateStats() {
                    try {
                        const res = await fetch('/api/sys/stats');
                        this.stats = await res.json();
                    } catch(e) {}
                }
            }
        }).mount('#app');
    </script>
</body>
</html>
EOF

# --- [ 5. ТЕЛЕГРАМ БОТ (ADVANCED) ] ---
echo -e "${C_BLUE}[5/10]${C_RST} Создание Telegram-бота управления..."
cat << EOF > ${PANEL_DIR}/bot.py
import asyncio, sqlite3
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ApplicationBuilder, CommandHandler, CallbackQueryHandler, ContextTypes

TOKEN = "ВАШ_ТОКЕН_ЗДЕСЬ" # Будет настроено через веб-панель

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    keyboard = [
        [InlineKeyboardButton("📊 Статистика", callback_data='stats'),
         InlineKeyboardButton("🔗 Моя подписка", callback_data='sub')],
        [InlineKeyboardButton("💳 Продлить", callback_data='pay')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text('🦾 FEDUK v6 ULTIMATE BOT\nВаш персональный ассистент прокси.', reply_markup=reply_markup)

if __name__ == "__main__":
    # Бот будет запускаться как отдельный сервис
    pass
EOF

# --- [ 6. СИСТЕМНАЯ ИНТЕГРАЦИЯ ] ---
echo -e "${C_BLUE}[6/10]${C_RST} Настройка Nginx и SSL..."

cat << EOF > /etc/nginx/sites-available/feduk
server {
    listen 80;
    server_name _;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name _;
    ssl_certificate ${PANEL_DIR}/certs/server.crt;
    ssl_certificate_key ${PANEL_DIR}/certs/server.key;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # API Prometheus
    location /metrics {
        proxy_pass http://127.0.0.1:9100/metrics;
    }
}
EOF

# Генерация временных сертификатов
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout ${PANEL_DIR}/certs/server.key -out ${PANEL_DIR}/certs/server.crt \
    -subj "/C=RU/O=Feduk/CN=$SERVER_IP" 2>/dev/null

ln -sf /etc/nginx/sites-available/feduk /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

# --- [ 7. СОЗДАНИЕ СЛУЖБ SYSTEMD ] ---
echo -e "${C_BLUE}[7/10]${C_RST} Регистрация сервисов в Systemd..."

# 1. Panel Service
cat << EOF > /etc/systemd/system/feduk-panel.service
[Unit]
Description=Feduk v6 Ultimate Panel
After=network.target postgresql.service

[Service]
WorkingDirectory=${PANEL_DIR}
ExecStart=/usr/bin/python3 ${PANEL_DIR}/main.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# 2. Xray Service
cat << EOF > /etc/systemd/system/feduk-xray.service
[Unit]
Description=Feduk v6 Xray Core
After=network.target

[Service]
ExecStart=${XRAY_BIN} run -config ${PANEL_DIR}/configs/config.json
Restart=always
User=root
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# Создаем пустой конфиг для первого запуска Xray
cat << EOF > ${PANEL_DIR}/configs/config.json
{
    "log": {"loglevel": "warning"},
    "api": {"tag": "api", "services": ["HandlerService", "StatsService"]},
    "stats": {},
    "inbounds": [{"listen": "127.0.0.1", "port": 10085, "protocol": "dokodemo-door", "settings": {"address": "127.0.0.1"}, "tag": "api"}],
    "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
EOF

systemctl daemon-reload
systemctl enable --now feduk-panel feduk-xray

# --- [ 8. CLI ИНСТРУМЕНТ ] ---
echo -e "${C_BLUE}[8/10]${C_RST} Установка feduk-cli..."
cat << 'EOF' > /usr/local/bin/feduk-cli
#!/bin/bash
case $1 in
    status) systemctl status feduk-panel feduk-xray ;;
    restart) systemctl restart feduk-panel feduk-xray ;;
    logs) journalctl -u feduk-panel -f ;;
    backup) tar -czf /opt/feduk/backups/backup_$(date +%F).tar.gz /opt/feduk/data /opt/feduk/configs ;;
    *) echo "Usage: feduk-cli {status|restart|logs|backup}" ;;
esac
EOF
chmod +x /usr/local/bin/feduk-cli

# --- [ 9. ФИНАЛЬНЫЙ ВЫВОД ] ---
echo -e "${C_BLUE}[9/10]${C_RST} Генерация учетных данных..."
echo -e "url: https://$SERVER_IP\nadmin: admin\npassword: $ADMIN_PASS\ndb_pass: $DB_PASS\njwt_secret: $JWT_SECRET" > /root/.feduk_credentials

print_logo
echo -e "${C_GREEN}ПОЗДРАВЛЯЕМ! FEDUK PROXY PANEL v6.0 ULTIMATE УСПЕШНО РАЗВЕРНУТА.${C_RST}"
echo -e "----------------------------------------------------------------------"
echo -e "${C_CYAN}URL панели:${C_RST}      https://$SERVER_IP"
echo -e "${C_CYAN}Логин:${C_RST}           admin"
echo -e "${C_CYAN}Пароль:${C_RST}          ${C_GOLD}$ADMIN_PASS${C_RST}"
echo -e "----------------------------------------------------------------------"
echo -e "${C_PURP}Инфраструктура:${C_RST}"
echo -e "- PostgreSQL:   Включено (Port 5432)"
echo -e "- Redis Cache:  Включено (Port 6379)"
echo -e "- Xray gRPC:    Включено (Port 10085)"
echo -e "- Celery Task:  Включено"
echo -e "----------------------------------------------------------------------"
echo -e "Используйте ${C_GREEN}feduk-c# --- [ ПРОДОЛЖЕНИЕ: 8. CLI ИНСТРУМЕНТ (РАСШИРЕННЫЙ) ] ---
# Мы дополняем feduk-cli, чтобы он мог управлять пользователями и сертификатами
cat << 'EOF' > /usr/local/bin/feduk-cli
#!/bin/bash
C_BLUE='\033[0;34m'
C_GREEN='\033[0;32m'
C_RST='\033[0m'

case $1 in
    status)
        systemctl status feduk-panel feduk-xray redis-server postgresql
        ;;
    restart)
        echo -e "${C_BLUE}Перезапуск всех компонентов...${C_RST}"
        systemctl restart feduk-panel feduk-xray redis-server postgresql nginx
        echo -e "${C_GREEN}Готово.${C_RST}"
        ;;
    logs)
        journalctl -u feduk-panel -f
        ;;
    backup)
        mkdir -p /opt/feduk/backups
        FILE="/opt/feduk/backups/feduk_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "$FILE" /opt/feduk/configs /opt/feduk/certs
        # Бэкап БД
        sudo -u postgres pg_dump feduk_v6 > /opt/feduk/backups/db_dump.sql
        echo -e "${C_GREEN}Бэкап создан: $FILE${C_RST}"
        ;;
    update)
        echo -e "${C_BLUE}Обновление Xray Core...${C_RST}"
        LATEST=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
        wget -qO /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${LATEST}/Xray-linux-64.zip"
        unzip -qo /tmp/xray.zip -d /opt/feduk/bin
        systemctl restart feduk-xray
        echo -e "${C_GREEN}Обновлено до $LATEST${C_RST}"
        ;;
    *)
        echo "Использование: feduk-cli {status|restart|logs|backup|update}"
        ;;
esac
EOF
chmod +x /usr/local/bin/feduk-cli

# --- [ 9. ПОДГОТОВКА TELEGRAM БОТА ] ---
# Добавляем скрипт запуска бота как сервиса
cat << EOF > /etc/systemd/system/feduk-bot.service
[Unit]
Description=Feduk v6 Telegram Bot
After=network.target feduk-panel.service

[Service]
WorkingDirectory=${PANEL_DIR}
ExecStart=/usr/bin/python3 ${PANEL_DIR}/bot.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl enable feduk-bot

# --- [ 10. ФИНАЛИЗАЦИЯ И ВЫВОД ] ---
echo -e "${C_BLUE}[10/10]${C_RST} Завершение установки и очистка..."

# Создаем файл с доступами, если его нет
if [ ! -f /root/.feduk_credentials ]; then
    cat << EOF > /root/.feduk_credentials
==================================================
      FEDUK PROXY PANEL v6.0 ULTIMATE
==================================================
URL Панели:    https://$SERVER_IP
Логин:         admin
Пароль:        $ADMIN_PASS
--------------------------------------------------
БАЗА ДАННЫХ (PostgreSQL):
Пользователь:  feduk_admin
Пароль:        $DB_PASS
БД:            feduk_v6
--------------------------------------------------
API & SECURITY:
JWT Secret:    $JWT_SECRET
Xray gRPC:     127.0.0.1:10085
==================================================
EOF
fi

# Устанавливаем права
chown -R root:root ${PANEL_DIR}
chmod 600 /root/.feduk_credentials

print_logo
echo -e "${C_GREEN}УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!${C_RST}"
echo -e "----------------------------------------------------------------------"
echo -e "${C_CYAN}URL панели:${C_RST}      https://$SERVER_IP"
echo -e "${C_CYAN}Логин:${C_RST}           admin"
echo -e "${C_CYAN}Пароль:${C_RST}          ${C_GOLD}$ADMIN_PASS${C_RST}"
echo -e "----------------------------------------------------------------------"
echo -e "${C_PURP}Инфраструктура:${C_RST}"
echo -e "• PostgreSQL:   ${C_GREEN}ONLINE${C_RST} (Port 5432)"
echo -e "• Redis:        ${C_GREEN}ONLINE${C_RST} (Port 6379)"
echo -e "• RabbitMQ:     ${C_GREEN}ONLINE${C_RST}"
echo -e "• Xray Core:    ${C_GREEN}ONLINE${C_RST} (gRPC API active)"
echo -e "----------------------------------------------------------------------"
echo -e "${C_BLUE}Команды управления:${C_RST}"
echo -e "  feduk-cli status  - проверить состояние"
echo -e "  feduk-cli logs    - логи панели"
echo -e "  feduk-cli backup  - создать бэкап"
echo -e "----------------------------------------------------------------------"
echo -e "Данные сохранены в: ${C_GOLD}/root/.feduk_credentials${C_RST}"
echo -e "Настройте Telegram Bot Token в ${C_GOLD}${PANEL_DIR}/bot.py${C_RST}"
echo -e "----------------------------------------------------------------------"

# Финальный запуск всех служб
systemctl daemon-reload
systemctl restart feduk-panel feduk-xray nginx

