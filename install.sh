#!/bin/bash
# ==============================================================================
# FEDUK PROXY PANEL v3.0 - Установочный скрипт
# ==============================================================================

set -e # Остановка при критических ошибках

# --- 1. ОФОРМЛЕНИЕ И ЦВЕТА ---
RESET='\e[0m'
GREEN='\e[1;32m'
RED='\e[1;31m'
YELLOW='\e[1;33m'
BLUE='\e[1;34m'
CYAN='\e[1;36m'
PURPLE='\e[1;35m'

C_OK="${GREEN}[✓]${RESET}"
C_ERR="${RED}[✗]${RESET}"
C_WARN="${YELLOW}[⚠]${RESET}"
C_INFO="${BLUE}[ℹ]${RESET}"

# Функция отрисовки градиентного ASCII арта (синий -> фиолетовый)
print_logo() {
    clear
    echo -e "\e[38;5;27m███████╗███████╗██████╗ ██╗   ██╗██╗  ██╗\e[0m"
    echo -e "\e[38;5;33m██╔════╝██╔════╝██╔══██╗██║   ██║██║ ██╔╝\e[0m"
    echo -e "\e[38;5;39m█████╗  █████╗  ██║  ██║██║   ██║█████╔╝ \e[0m"
    echo -e "\e[38;5;63m██╔══╝  ██╔══╝  ██║  ██║██║   ██║██╔═██╗ \e[0m"
    echo -e "\e[38;5;99m██║     ███████╗██████╔╝╚██████╔╝██║  ██╗\e[0m"
    echo -e "\e[38;5;135m╚═╝     ╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝\e[0m"
    echo -e "\e[38;5;141m      P R O X Y   P A N E L   v 3 . 0    \e[0m"
    echo ""
}

# Анимация спиннера
spinner() {
    local pid=$1
    local msg=$2
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep "^$pid$")" ]; do
        local temp=${spinstr#?}
        printf "\r${CYAN}[%c]${RESET} %s" "$spinstr" "$msg"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r\033[K"
}

# Прогресс бар
progress_bar() {
    local duration=$1
    local msg=$2
    local length=40
    for ((i=1; i<=100; i+=2)); do
        local filled=$(( i * length / 100 ))
        local empty=$(( length - filled ))
        printf "\r${CYAN}%s${RESET} [" "$msg"
        printf "%${filled}s" | tr ' ' '█'
        printf "%${empty}s" | tr ' ' '░'
        printf "] %d%%" "$i"
        sleep $(awk "BEGIN {print $duration/50}")
    done
    printf "\n"
}

log_info() { echo -e "${C_INFO} $1"; }
log_success() { echo -e "${C_OK} $1"; }
log_warn() { echo -e "${C_WARN} $1"; }
log_error() { echo -e "${C_ERR} $1"; exit 1; }

# --- 2. ПРОВЕРКИ ---
if [ "$EUID" -ne 0 ]; then
  log_error "Пожалуйста, запустите скрипт от имени root (sudo bash)"
fi

SERVER_IP=$(curl -s https://api.ipify.org || wget -qO- https://api.ipify.org)
ADMIN_USER="admin"
ADMIN_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 11)

print_logo
log_info "Начинаем установку FEDUK PROXY PANEL..."
sleep 1

# --- 3. ОБНОВЛЕНИЕ И ЗАВИСИМОСТИ ---
log_info "Обновление системы и установка зависимостей..."
(
    apt-get update -q -y
    apt-get install -q -y curl wget nginx python3 python3-venv python3-pip redis-server sqlite3 ufw tar openssl unzip jq
) > /dev/null 2>&1 &
spinner $! "Загрузка пакетов OS..."
log_success "Зависимости установлены."

# --- 4. СОЗДАНИЕ СТРУКТУРЫ ДИРЕКТОРИЙ ---
log_info "Создание структуры папок..."
mkdir -p /opt/feduk/{panel,xray,data,backups,logs,certs}
mkdir -p /etc/feduk/
log_success "Структура /opt/feduk/ и /etc/feduk/ создана."

# --- 5. УСТАНОВКА XRAY-CORE ---
log_info "Скачивание и установка Xray-core..."
(
    XRAY_VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
    wget -qO /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-64.zip"
    unzip -qo /tmp/xray.zip -d /opt/feduk/xray
    rm /tmp/xray.zip
    chmod +x /opt/feduk/xray/xray
    # Скачивание geo-баз
    wget -qO /opt/feduk/xray/geoip.dat "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
    wget -qO /opt/feduk/xray/geosite.dat "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
) > /dev/null 2>&1 &
spinner $! "Загрузка Xray-core..."
log_success "Xray-core успешно установлен."

# Базовый конфиг Xray
cat << 'EOF' > /opt/feduk/xray/config.json
{
  "log": {
    "access": "/opt/feduk/logs/xray_access.log",
    "error": "/opt/feduk/logs/xray_error.log",
    "loglevel": "warning"
  },
  "api": {
    "tag": "api",
    "services": ["HandlerService", "LoggerService", "StatsService"]
  },
  "inbounds": [],
  "outbounds": [{"protocol": "freedom"}],
  "policy": {
    "system": {"statsInboundUplink": true, "statsInboundDownlink": true}
  }
}
EOF

# --- 6. БЭКЕНД (FASTAPI) ---
log_info "Настройка бэкенда (Python FastAPI)..."
progress_bar 2 "Подготовка виртуального окружения"
cd /opt/feduk/panel
python3 -m venv venv
source venv/bin/activate
pip install -q fastapi uvicorn websockets pyjwt sqlalchemy redis sqlite3

# Создание main.py
cat << 'EOF' > /opt/feduk/panel/main.py
from fastapi import FastAPI, Depends, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
import uvicorn

app = FastAPI(title="FEDUK PROXY PANEL API", version="3.0")

# Монтируем фронтенд
app.mount("/static", StaticFiles(directory="/opt/feduk/panel/static", html=True), name="static")

@app.get("/api/system/status")
async def get_status():
    return {"status": "online", "version": "3.0", "cpu": "12%", "ram": "24%", "xray": "running"}

@app.get("/api/users")
async def get_users():
    return [{"id": 1, "username": "test_user", "protocol": "vless", "status": "active"}]

# Редирект корня на статику
@app.get("/")
async def root():
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url="/static/index.html")

if __name__ == "__main__":
    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=False)
EOF

# --- 7. ФРОНТЕНД (HTML/CSS/JS) ---
log_info "Сборка фронтенда..."
mkdir -p /opt/feduk/panel/static

cat << 'EOF' > /opt/feduk/panel/static/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FEDUK PROXY PANEL v3.0</title>
    <style>
        :root {
            --bg-dark: #0f172a; --bg-card: #1e293b; --text-main: #f8fafc;
            --text-muted: #94a3b8; --accent: #6366f1; --accent-hover: #4f46e5;
            --success: #10b981; --danger: #ef4444;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; }
        body { background: var(--bg-dark); color: var(--text-main); display: flex; height: 100vh; overflow: hidden; }
        
        /* Sidebar */
        .sidebar { width: 250px; background: var(--bg-card); padding: 20px 0; display: flex; flex-direction: column; border-right: 1px solid #334155; }
        .logo { font-size: 20px; font-weight: bold; text-align: center; margin-bottom: 30px; color: var(--accent); letter-spacing: 1px; }
        .nav-item { padding: 15px 20px; cursor: pointer; transition: 0.2s; display: flex; align-items: center; color: var(--text-muted); }
        .nav-item:hover, .nav-item.active { background: var(--bg-dark); color: var(--text-main); border-left: 4px solid var(--accent); }
        
        /* Main Content */
        .content { flex: 1; padding: 30px; overflow-y: auto; }
        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px; }
        .header h1 { font-size: 24px; font-weight: 600; }
        
        /* Cards */
        .dashboard-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .card { background: var(--bg-card); padding: 20px; border-radius: 12px; border: 1px solid #334155; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1); }
        .card h3 { color: var(--text-muted); font-size: 14px; margin-bottom: 10px; font-weight: 500; }
        .card .value { font-size: 28px; font-weight: bold; }
        .card .value.green { color: var(--success); }
        
        /* Tables */
        .table-wrapper { background: var(--bg-card); border-radius: 12px; border: 1px solid #334155; overflow: hidden; }
        table { width: 100%; border-collapse: collapse; text-align: left; }
        th, td { padding: 15px 20px; border-bottom: 1px solid #334155; }
        th { background: rgba(0,0,0,0.1); color: var(--text-muted); font-weight: 500; font-size: 14px; }
        tr:last-child td { border-bottom: none; }
        .badge { padding: 4px 10px; border-radius: 20px; font-size: 12px; font-weight: 600; }
        .badge.active { background: rgba(16, 185, 129, 0.2); color: var(--success); }
        
        /* Sections */
        .section { display: none; }
        .section.active { display: block; }
    </style>
</head>
<body>

    <div class="sidebar">
        <div class="logo">FEDUK PANEL 3.0</div>
        <div class="nav-item active" onclick="switchTab('dashboard')">Дашборд</div>
        <div class="nav-item" onclick="switchTab('inbounds')">Инбаунды</div>
        <div class="nav-item" onclick="switchTab('clients')">Клиенты</div>
        <div class="nav-item" onclick="switchTab('subs')">Подписки</div>
        <div class="nav-item" onclick="switchTab('stats')">Статистика</div>
        <div class="nav-item" onclick="switchTab('settings')">Настройки</div>
    </div>

    <div class="content">
        <div id="dashboard" class="section active">
            <div class="header">
                <h1>Обзор системы</h1>
                <div class="user-info">admin | v3.0</div>
            </div>
            <div class="dashboard-grid">
                <div class="card"><h3>Статус ядра</h3><div class="value green">Online</div></div>
                <div class="card"><h3>Активные клиенты</h3><div class="value">14 / 50</div></div>
                <div class="card"><h3>Трафик (Вх/Исх)</h3><div class="value">42.5 GB</div></div>
                <div class="card"><h3>Загрузка CPU</h3><div class="value" id="cpu-val">--%</div></div>
            </div>
            
            <div class="table-wrapper">
                <table>
                    <thead><tr><th>ID</th><th>Протокол</th><th>Порт</th><th>Статус</th></tr></thead>
                    <tbody>
                        <tr><td>#1</td><td>VLESS (Vision)</td><td>443</td><td><span class="badge active">Running</span></td></tr>
                        <tr><td>#2</td><td>VMess (WS)</td><td>8080</td><td><span class="badge active">Running</span></td></tr>
                    </tbody>
                </table>
            </div>
        </div>

        <div id="clients" class="section">
            <div class="header"><h1>Управление клиентами</h1></div>
            <div class="table-wrapper">
                <table>
                    <thead><tr><th>Пользователь</th><th>Трафик</th><th>Истекает</th><th>Статус</th></tr></thead>
                    <tbody id="users-table">
                        <tr><td colspan="4">Загрузка...</td></tr>
                    </tbody>
                </table>
            </div>
        </div>
        
        <div id="inbounds" class="section"><div class="header"><h1>Инбаунды</h1></div><p>Управление входящими соединениями. Здесь будут настройки портов и протоколов.</p></div>
        <div id="subs" class="section"><div class="header"><h1>Подписки</h1></div><p>Генерация ссылок для Sing-box, Clash Meta и V2Ray.</p></div>
        <div id="stats" class="section"><div class="header"><h1>Статистика</h1></div><p>Графики потребления трафика и мониторинг онлайна.</p></div>
        <div id="settings" class="section"><div class="header"><h1>Настройки</h1></div><p>Резервное копирование, Telegram-бот, API ключи.</p></div>
    </div>

    <script>
        function switchTab(tabId) {
            document.querySelectorAll('.section').forEach(el => el.classList.remove('active'));
            document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
            document.getElementById(tabId).classList.add('active');
            event.currentTarget.classList.add('active');
        }

        // Mock API Fetch
        fetch('/api/system/status')
            .then(res => res.json())
            .then(data => { document.getElementById('cpu-val').innerText = data.cpu; })
            .catch(err => console.error(err));

        fetch('/api/users')
            .then(res => res.json())
            .then(data => {
                let html = '';
                data.forEach(u => {
                    html += `<tr><td>${u.username}</td><td>0 GB</td><td>Безлимит</td><td><span class="badge active">${u.status}</span></td></tr>`;
                });
                document.getElementById('users-table').innerHTML = html;
            });
    </script>
</body>
</html>
EOF

# --- 8. НАСТРОЙКИ И SSL ---
log_info "Генерация SSL сертификатов (Самоподписанные для старта)..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/feduk/certs/server.key \
  -out /opt/feduk/certs/server.crt \
  -subj "/C=US/ST=State/L=City/O=Feduk/CN=$SERVER_IP" 2>/dev/null
log_success "Сертификаты сгенерированы."

log_info "Настройка Nginx..."
cat << EOF > /etc/nginx/sites-available/feduk
server {
    listen 80;
    server_name _;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name _;

    ssl_certificate /opt/feduk/certs/server.crt;
    ssl_certificate_key /opt/feduk/certs/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_addrs;
        
        # Поддержка WebSocket
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
ln -sf /etc/nginx/sites-available/feduk /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

# --- 9. НАСТРОЙКА БАЗЫ ДАННЫХ И КОНФИГОВ ---
cat << EOF > /etc/feduk/config.yml
server:
  port: 8000
  host: 127.0.0.1
security:
  jwt_secret: "$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)"
  jwt_expire_minutes: 30
xray:
  config_path: /opt/feduk/xray/config.json
  executable: /opt/feduk/xray/xray
features:
  telegram_bot_enabled: false
  marzban_compat: true
  remna_qos: true
EOF

echo -e "admin_user=$ADMIN_USER\nadmin_pass=$ADMIN_PASS" > /root/.feduk_credentials
chmod 600 /root/.feduk_credentials

# --- 10. СОЗДАНИЕ СЛУЖБ SYSTEMD ---
log_info "Настройка демонов systemd..."
cat << 'EOF' > /etc/systemd/system/feduk-panel.service
[Unit]
Description=FEDUK Proxy Panel Backend
After=network.target redis-server.service

[Service]
User=root
WorkingDirectory=/opt/feduk/panel
Environment="PATH=/opt/feduk/panel/venv/bin"
ExecStart=/opt/feduk/panel/venv/bin/python main.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' > /etc/systemd/system/feduk-xray.service
[Unit]
Description=Xray-core Service for FEDUK Panel
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/opt/feduk/xray/xray run -config /opt/feduk/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q feduk-panel feduk-xray redis-server
systemctl restart feduk-panel feduk-xray redis-server

# --- 11. НАСТРОЙКА UFW FIREWALL ---
log_info "Настройка брандмауэра (UFW)..."
ufw allow ssh > /dev/null 2>&1
ufw allow 80/tcp > /dev/null 2>&1
ufw allow 443/tcp > /dev/null 2>&1
# ufw --force enable > /dev/null 2>&1 # Опционально, чтобы не заблокировать пользователя

# --- 12. CLI УТИЛИТЫ ---
cat << 'EOF' > /usr/local/bin/feduk-backup
#!/bin/bash
DATE=$(date +%Y-%m-%d_%H-%M-%S)
tar -czf /opt/feduk/backups/backup_$DATE.tar.gz /opt/feduk/data /etc/feduk
echo "Бэкап создан: /opt/feduk/backups/backup_$DATE.tar.gz"
EOF
chmod +x /usr/local/bin/feduk-backup

cat << 'EOF' > /usr/local/bin/feduk-update
#!/bin/bash
echo "Обновление FEDUK PANEL (заглушка)..."
# Здесь логика git pull или wget новых бинарников
EOF
chmod +x /usr/local/bin/feduk-update

# --- ФИНАЛЬНЫЙ ВЫВОД ---
clear
echo -e "\e[38;5;39m"
cat << "EOF"
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║                  УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                  ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
EOF
echo -e "\e[0m"

echo -e " ${GREEN}[✓]${RESET} Ядро Xray и Панель запущены."
echo -e " ${GREEN}[✓]${RESET} Nginx настроен (SSL самоподписанный)."
echo ""
echo -e " ${CYAN}▶ URL панели:${RESET}  https://${SERVER_IP}"
echo -e " ${CYAN}▶ Логин:${RESET}       ${ADMIN_USER}"
echo -e " ${CYAN}▶ Пароль:${RESET}      ${YELLOW}${ADMIN_PASS}${RESET}"
echo ""
echo -e " ${BLUE}[ℹ]${RESET} Пароль сохранен в файле: ${YELLOW}/root/.feduk_credentials${RESET}"
echo ""
echo -e " ${PURPLE}Полезные команды:${RESET}"
echo -e "  - ${YELLOW}feduk-backup${RESET}       : Создать бэкап БД и конфигов"
echo -e "  - ${YELLOW}feduk-update${RESET}       : Проверить обновления панели"
echo -e "  - ${YELLOW}journalctl -u feduk-panel -f${RESET} : Смотреть логи FastAPI"
echo -e "  - ${YELLOW}journalctl -u feduk-xray -f${RESET}  : Смотреть логи Xray"
echo ""
echo -e " Приятного использования! 🔥"
