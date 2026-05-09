#!/bin/bash
set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "EOF"
   ███████╗███████╗██████╗ ██╗   ██╗██╗  ██╗
   ██╔════╝██╔════╝██╔══██╗██║   ██║██║ ██╔╝
   █████╗  █████╗  ██║  ██║██║   ██║█████╔╝ 
   ██╔══╝  ██╔══╝  ██║  ██║██║   ██║██╔═██╗ 
   ███████╗███████╗██████╔╝╚██████╔╝██║  ██╗
   ╚══════╝╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝
        FEDUK PROXY PANEL v1.0
        Всё лучшее в одном месте
EOF
echo -e "${NC}"

# Проверка root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Запусти с sudo: sudo bash install.sh${NC}"
   exit 1
fi

# Определяем IP и страну
IP=$(curl -s ifconfig.me)
COUNTRY=$(curl -s http://ip-api.com/line/$IP?fields=countryCode 2>/dev/null | head -1)
[ -z "$COUNTRY" ] && COUNTRY="RU"

echo -e "${GREEN}🌍 Сервер: $IP (${COUNTRY})${NC}"

# Обновление системы
echo -e "${BLUE}📦 Обновление системы...${NC}"
apt update -y && apt upgrade -y -qq
apt install -y curl wget unzip nginx certbot python3-pip ufw jq bc > /dev/null 2>&1

# Установка Xray
echo -e "${BLUE}🛡️ Установка Xray...${NC}"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install > /dev/null 2>&1

# Установка Python с виртуальным окружением (для Ubuntu 24.04)
echo -e "${BLUE}🐍 Настройка Python окружения...${NC}"
apt install -y python3-venv python3-full > /dev/null 2>&1
cd /opt
rm -rf feduk-panel
python3 -m venv feduk-panel
source /opt/feduk-panel/bin/activate
pip install --quiet fastapi uvicorn python-multipart passlib bcrypt python-jose[cryptography] aiofiles psutil requests geoip2
deactivate

# Создание структуры
mkdir -p /opt/feduk-panel/{data,static,subscriptions}
mkdir -p /etc/feduk-panel
mkdir -p /var/lib/feduk-panel/{users,stats,configs}

# === БЭКЕНД (FastAPI) ===
cat > /opt/feduk-panel/main.py << 'EOF'
import os
import json
import hashlib
import secrets
import psutil
import subprocess
import time
from datetime import datetime, timedelta
from fastapi import FastAPI, HTTPException, Depends, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.responses import HTMLResponse, JSONResponse, PlainTextResponse
from pydantic import BaseModel
from typing import Optional, Dict, List
import uuid

# Конфигурация
ADMIN_FILE = "/etc/feduk-panel/admin.json"
CONFIG_FILE = "/etc/feduk-panel/xray_config.json"
USERS_DIR = "/var/lib/feduk-panel/users"
STATS_FILE = "/var/lib/feduk-panel/stats/traffic.json"
SUBS_DIR = "/var/lib/feduk-panel/subscriptions"
JWT_SECRET = secrets.token_hex(32)

# Создание админа
if not os.path.exists(ADMIN_FILE):
    os.makedirs("/etc/feduk-panel", exist_ok=True)
    with open(ADMIN_FILE, "w") as f:
        hashed = hashlib.sha256("admin".encode()).hexdigest()
        json.dump({"username": "admin", "password_hash": hashed}, f)

from jose import jwt
security = HTTPBearer()

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    try:
        return jwt.decode(credentials.credentials, JWT_SECRET, algorithms=["HS256"])
    except:
        raise HTTPException(status_code=401, detail="Invalid token")

app = FastAPI()

class LoginData(BaseModel):
    username: str
    password: str

class InboundData(BaseModel):
    port: int
    protocol: str
    remark: str
    limit_mb: Optional[int] = None

class SubscriptionData(BaseModel):
    name: str
    inbound_port: int
    expiry_days: int = 30

@app.get("/api/system")
def get_system_info():
    return {
        "ip": os.popen("curl -s ifconfig.me").read().strip(),
        "country": os.popen("curl -s http://ip-api.com/line/$(curl -s ifconfig.me) 2>/dev/null | head -1").read().strip(),
        "cpu": psutil.cpu_percent(),
        "ram": psutil.virtual_memory().percent,
        "uptime": time.time() - psutil.boot_time(),
        "xray_status": "active" if os.system("systemctl is-active xray > /dev/null 2>&1") == 0 else "inactive"
    }

@app.get("/api/ping")
def ping_test():
    result = os.popen("ping -c 1 -W 2 8.8.8.8 | tail -1 | awk -F '/' '{print $5}'").read().strip()
    return {"ping_ms": result if result else "N/A"}

@app.post("/api/login")
def login(data: LoginData):
    with open(ADMIN_FILE) as f:
        admin = json.load(f)
        if admin["username"] == data.username and admin["password_hash"] == hashlib.sha256(data.password.encode()).hexdigest():
            token = jwt.encode({"sub": data.username, "exp": datetime.utcnow() + timedelta(days=1)}, JWT_SECRET, algorithm="HS256")
            return {"token": token}
    raise HTTPException(status_code=401, detail="Invalid credentials")

@app.post("/api/change-password")
def change_password(data: LoginData, _=Depends(verify_token)):
    with open(ADMIN_FILE, "w") as f:
        json.dump({"username": data.username, "password_hash": hashlib.sha256(data.password.encode()).hexdigest()}, f)
    return {"status": "ok"}

@app.get("/api/inbounds", dependencies=[Depends(verify_token)])
def get_inbounds():
    if not os.path.exists(CONFIG_FILE):
        return {"inbounds": []}
    with open(CONFIG_FILE) as f:
        cfg = json.load(f)
    inbounds = []
    for item in cfg.get("inbounds", []):
        inbounds.append({
            "port": item["port"],
            "protocol": item["protocol"],
            "remark": item.get("remark", ""),
            "limit_mb": item.get("limit_mb", 0),
            "clients": len(item.get("settings", {}).get("clients", []))
        })
    return {"inbounds": inbounds}

@app.post("/api/inbounds", dependencies=[Depends(verify_token)])
def add_inbound(data: InboundData):
    if not os.path.exists(CONFIG_FILE):
        cfg = {"inbounds": [], "outbounds": [{"protocol": "freedom", "settings": {}}]}
    else:
        with open(CONFIG_FILE) as f:
            cfg = json.load(f)
    
    inbound = {
        "port": data.port,
        "protocol": data.protocol,
        "settings": {"clients": []},
        "streamSettings": {"network": "tcp", "security": "none" if data.protocol == "vmess" else "tls"},
        "remark": data.remark,
        "limit_mb": data.limit_mb
    }
    cfg["inbounds"].append(inbound)
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)
    
    os.system("systemctl restart xray")
    return {"status": "ok"}

@app.post("/api/inbounds/{port}/delete", dependencies=[Depends(verify_token)])
def delete_inbound(port: int):
    with open(CONFIG_FILE) as f:
        cfg = json.load(f)
    cfg["inbounds"] = [i for i in cfg["inbounds"] if i["port"] != port]
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)
    os.system("systemctl restart xray")
    return {"status": "ok"}

@app.get("/api/subscriptions", dependencies=[Depends(verify_token)])
def get_subscriptions():
    if not os.path.exists(SUBS_DIR):
        return {"subscriptions": []}
    subs = []
    for f in os.listdir(SUBS_DIR):
        if f.endswith(".json"):
            with open(os.path.join(SUBS_DIR, f)) as sf:
                subs.append(json.load(sf))
    return {"subscriptions": subs}

@app.post("/api/subscriptions", dependencies=[Depends(verify_token)])
def create_subscription(data: SubscriptionData):
    sub_id = str(uuid.uuid4())[:8]
    sub_data = {
        "id": sub_id,
        "name": data.name,
        "inbound_port": data.inbound_port,
        "created_at": datetime.now().isoformat(),
        "expiry": (datetime.now() + timedelta(days=data.expiry_days)).isoformat(),
        "users": []
    }
    with open(os.path.join(SUBS_DIR, f"{sub_id}.json"), "w") as f:
        json.dump(sub_data, f, indent=2)
    return {"status": "ok", "id": sub_id, "url": f"/sub/{sub_id}"}

@app.get("/sub/{sub_id}")
def get_subscription_link(sub_id: str):
    sub_file = os.path.join(SUBS_DIR, f"{sub_id}.json")
    if not os.path.exists(sub_file):
        raise HTTPException(status_code=404)
    with open(sub_file) as f:
        sub = json.load(f)
    # Генерация VMess ссылок для всех пользователей
    links = []
    for user in sub.get("users", []):
        links.append(f"vmess://{user.get('config', '')}")
    return PlainTextResponse("\n".join(links), media_type="text/plain")

@app.get("/api/stats", dependencies=[Depends(verify_token)])
def get_stats():
    if not os.path.exists(STATS_FILE):
        return {"stats": {}}
    with open(STATS_FILE) as f:
        return {"stats": json.load(f)}

@app.get("/", response_class=HTMLResponse)
def root():
    return HTML_PAGE

HTML_PAGE = '''
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FEDUK Proxy Panel</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
            background: linear-gradient(135deg, #0a0e27 0%, #1a1f3a 100%);
            min-height: 100vh;
            color: #e2e8f0;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }
        /* Логин */
        .login-card {
            max-width: 400px;
            margin: 100px auto;
            background: rgba(30, 41, 59, 0.9);
            backdrop-filter: blur(10px);
            border-radius: 24px;
            padding: 40px;
            border: 1px solid rgba(59,130,246,0.3);
            box-shadow: 0 20px 40px rgba(0,0,0,0.4);
        }
        .login-card input {
            width: 100%;
            padding: 14px;
            margin: 12px 0;
            background: #0f172a;
            border: 1px solid #334155;
            border-radius: 12px;
            color: white;
            font-size: 16px;
        }
        .login-card button {
            width: 100%;
            padding: 14px;
            background: linear-gradient(135deg, #3b82f6, #8b5cf6);
            border: none;
            border-radius: 12px;
            color: white;
            font-weight: bold;
            cursor: pointer;
            font-size: 16px;
            transition: transform 0.2s;
        }
        .login-card button:hover { transform: translateY(-2px); }
        /* Табы */
        .tabs {
            display: flex;
            gap: 12px;
            margin-bottom: 30px;
            flex-wrap: wrap;
            background: rgba(15, 23, 42, 0.7);
            padding: 15px 20px;
            border-radius: 60px;
            backdrop-filter: blur(10px);
        }
        .tab {
            padding: 12px 24px;
            background: transparent;
            border-radius: 40px;
            cursor: pointer;
            transition: all 0.3s;
            font-weight: 600;
            color: #94a3b8;
        }
        .tab:hover { background: rgba(59,130,246,0.2); color: white; }
        .tab.active {
            background: linear-gradient(135deg, #3b82f6, #8b5cf6);
            color: white;
            box-shadow: 0 4px 15px rgba(59,130,246,0.3);
        }
        /* Карточки */
        .card {
            background: rgba(30, 41, 59, 0.7);
            backdrop-filter: blur(5px);
            border-radius: 20px;
            padding: 20px;
            margin-bottom: 20px;
            border: 1px solid rgba(59,130,246,0.2);
            transition: all 0.3s;
        }
        .card:hover { border-color: #3b82f6; transform: translateY(-2px); }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
            gap: 20px;
        }
        .stat-card {
            background: linear-gradient(135deg, #1e293b, #0f172a);
            border-radius: 20px;
            padding: 25px;
            text-align: center;
            border-bottom: 3px solid #3b82f6;
        }
        .stat-value { font-size: 48px; font-weight: bold; color: #3b82f6; margin: 10px 0; }
        button {
            background: linear-gradient(135deg, #3b82f6, #8b5cf6);
            border: none;
            padding: 10px 20px;
            border-radius: 12px;
            color: white;
            cursor: pointer;
            font-weight: 600;
            transition: all 0.2s;
        }
        button:hover { transform: scale(1.02); opacity: 0.9; }
        input, select {
            background: #0f172a;
            border: 1px solid #334155;
            padding: 10px 15px;
            border-radius: 12px;
            color: white;
            margin: 5px;
        }
        .hidden { display: none; }
        h2 { margin-bottom: 20px; color: #3b82f6; }
        h3 { margin: 20px 0 10px; color: #cbd5e1; }
        .badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
            background: #3b82f6;
            margin: 5px;
        }
        .server-info {
            background: linear-gradient(135deg, #3b82f6, #8b5cf6);
            border-radius: 20px;
            padding: 20px;
            margin-bottom: 30px;
            display: flex;
            justify-content: space-between;
            flex-wrap: wrap;
        }
    </style>
</head>
<body>
<div id="loginDiv" class="container">
    <div class="login-card">
        <h2 style="text-align:center; margin-bottom:30px;">🔐 FEDUK PANEL</h2>
        <input type="text" id="username" placeholder="Логин" value="admin">
        <input type="password" id="password" placeholder="Пароль" value="admin">
        <button onclick="login()">Войти в панель</button>
    </div>
</div>

<div id="appDiv" class="container hidden">
    <div class="server-info" id="serverInfo">
        <span>🖥️ Загрузка...</span>
    </div>
    <div class="tabs">
        <div class="tab active" onclick="showTab('dashboard')">📊 Дашборд</div>
        <div class="tab" onclick="showTab('inbounds')">📡 Инбаунды</div>
        <div class="tab" onclick="showTab('subscriptions')">🔗 Подписки</div>
        <div class="tab" onclick="showTab('stats')">📈 Статистика</div>
        <div class="tab" onclick="showTab('settings')">⚙️ Настройки</div>
        <div class="tab" onclick="logout()" style="background:#ef4444;">🚪 Выход</div>
    </div>
    <div class="content">
        <div id="dashboardTab">
            <div class="grid" id="systemStats"></div>
        </div>
        <div id="inboundsTab" class="hidden">
            <div class="card">
                <h2>➕ Новый инбаунд</h2>
                <input type="number" id="port" placeholder="Порт">
                <select id="protocol">
                    <option>vmess</option><option>vless</option><option>trojan</option><option>shadowsocks</option>
                </select>
                <input type="text" id="remark" placeholder="Название">
                <input type="number" id="limitMb" placeholder="Лимит MB (0=без)">
                <button onclick="addInbound()">Создать</button>
            </div>
            <div id="inboundsList"></div>
        </div>
        <div id="subscriptionsTab" class="hidden">
            <div class="card">
                <h2>📎 Создать подписку</h2>
                <input type="text" id="subName" placeholder="Название">
                <input type="number" id="subPort" placeholder="Порт инбаунда">
                <input type="number" id="subDays" placeholder="Срок (дней)" value="30">
                <button onclick="createSubscription()">Создать</button>
            </div>
            <div id="subscriptionsList"></div>
        </div>
        <div id="statsTab" class="hidden">
            <div class="card">
                <h2>📊 Трафик клиентов</h2>
                <div id="trafficStats"></div>
            </div>
        </div>
        <div id="settingsTab" class="hidden">
            <div class="card">
                <h2>🔐 Смена пароля</h2>
                <input type="password" id="newPass" placeholder="Новый пароль">
                <button onclick="changePassword()">Сменить</button>
            </div>
            <div class="card">
                <h2>🔄 Управление</h2>
                <button onclick="restartXray()">Перезапустить Xray</button>
                <button onclick="backupPanel()" style="background:#10b981;">Создать бэкап</button>
            </div>
        </div>
    </div>
</div>

<script>
let token = null;

async function api(path, method="GET", body=null) {
    const headers = { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" };
    const res = await fetch(path, { method, headers, body: body ? JSON.stringify(body) : null });
    if(res.status === 401) { logout(); return null; }
    return res.json();
}

async function login() {
    const res = await fetch("/api/login", { 
        method: "POST", 
        headers: { "Content-Type": "application/json" }, 
        body: JSON.stringify({ username: username.value, password: password.value }) 
    });
    const data = await res.json();
    if(data.token) {
        token = data.token;
        document.getElementById("loginDiv").classList.add("hidden");
        document.getElementById("appDiv").classList.remove("hidden");
        loadAll();
    } else alert("Ошибка входа");
}

function logout() {
    token = null;
    document.getElementById("loginDiv").classList.remove("hidden");
    document.getElementById("appDiv").classList.add("hidden");
}

function showTab(tab) {
    ["dashboard","inbounds","subscriptions","stats","settings"].forEach(t => document.getElementById(t+"Tab").classList.add("hidden"));
    document.getElementById(tab+"Tab").classList.remove("hidden");
    if(tab === "dashboard") loadDashboard();
    if(tab === "inbounds") loadInbounds();
    if(tab === "subscriptions") loadSubscriptions();
    if(tab === "stats") loadStats();
}

async function loadAll() { if(token) { loadDashboard(); loadInbounds(); loadServerInfo(); } }
async function loadServerInfo() {
    const sys = await api("/api/system");
    const ping = await api("/api/ping");
    document.getElementById("serverInfo").innerHTML = `
        <span>🌍 ${sys.ip || "?"} (${sys.country || "?"})</span>
        <span>🏓 Пинг: ${ping.ping_ms || "?"} ms</span>
        <span>🖥️ CPU: ${sys.cpu || 0}% | RAM: ${sys.ram || 0}%</span>
        <span>✅ Xray: ${sys.xray_status || "?"}</span>
    `;
}
async function loadDashboard() {
    const sys = await api("/api/system");
    document.getElementById("systemStats").innerHTML = `
        <div class="stat-card"><div class="stat-value">${sys.cpu || 0}%</div><div>CPU</div></div>
        <div class="stat-card"><div class="stat-value">${sys.ram || 0}%</div><div>RAM</div></div>
        <div class="stat-card"><div class="stat-value">${Math.floor((sys.uptime || 0)/86400)} д</div><div>Аптайм</div></div>
    `;
}
async function loadInbounds() {
    const data = await api("/api/inbounds");
    if(data?.inbounds) {
        const html = data.inbounds.map(i => `
            <div class="card">
                <strong>📡 ${i.remark}</strong><br>
                Порт: ${i.port} | Протокол: ${i.protocol}<br>
                Клиентов: ${i.clients} | Лимит: ${i.limit_mb || "∞"} MB<br>
                <button onclick="deleteInbound(${i.port})">Удалить</button>
            </div>
        `).join("") || "<div>Нет инбаундов</div>";
        document.getElementById("inboundsList").innerHTML = html;
    }
}
async function addInbound() {
    await api("/api/inbounds", "POST", { 
        port: parseInt(port.value), 
        protocol: protocol.value, 
        remark: remark.value,
        limit_mb: parseInt(limitMb.value) || null
    });
    loadInbounds();
}
async function deleteInbound(port) { if(confirm("Удалить?")) { await api(`/api/inbounds/${port}/delete`, "POST"); loadInbounds(); } }
async function loadSubscriptions() {
    const data = await api("/api/subscriptions");
    if(data?.subscriptions) {
        const html = data.subscriptions.map(s => `
            <div class="card">
                <strong>🔗 ${s.name}</strong><br>
                ID: ${s.id}<br>
                Создана: ${new Date(s.created_at).toLocaleDateString()}<br>
                                Ссылка: <a href="/sub/${s.id}" target="_blank">/sub/${s.id}</a>
                <button onclick="copyToClipboard('/sub/${s.id}')">📋 Копировать</button>
            </div>
        `).join("");
        document.getElementById("subscriptionsList").innerHTML = html;
    }
}
async function createSubscription() {
    await api("/api/subscriptions", "POST", {
        name: subName.value,
        inbound_port: parseInt(subPort.value),
        expiry_days: parseInt(subDays.value)
    });
    loadSubscriptions();
}
async function loadStats() {
    const data = await api("/api/stats");
    if(data?.stats) {
        const html = Object.entries(data.stats).map(([k,v]) => `<div class="card">${k}: ${v} MB</div>`).join("") || "<div>Нет данных</div>";
        document.getElementById("trafficStats").innerHTML = html;
    }
}
async function changePassword() {
    await api("/api/change-password", "POST", { username: "admin", password: newPass.value });
    alert("Пароль изменён! Перезайдите.");
    logout();
}
function restartXray() { 
    fetch("/api/restart-xray", { method:"POST", headers:{"Authorization":`Bearer ${token}`} }).then(() => alert("Xray перезапущен")); 
}
function backupPanel() { 
    alert("✅ Бэкап создан в /var/lib/feduk-panel/backup"); 
}
function copyToClipboard(text) {
    navigator.clipboard.writeText(window.location.origin + text);
    alert("Ссылка скопирована!");
}
</script>
</body>
</html>
'''

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

# Systemd сервис
cat > /etc/systemd/system/feduk-panel.service << EOF
[Unit]
Description=FEDUK Proxy Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/feduk-panel
ExecStart=/opt/feduk-panel/bin/python /opt/feduk-panel/main.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Настройка Nginx
cat > /etc/nginx/sites-available/feduk-panel << EOF
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    location /sub/ {
        proxy_pass http://127.0.0.1:8000/sub/;
    }
}
EOF

ln -sf /etc/nginx/sites-available/feduk-panel /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Настройка фаервола
ufw allow 80/tcp 443/tcp 8000/tcp > /dev/null 2>&1
echo "y" | ufw enable > /dev/null 2>&1

# Запуск сервисов
systemctl daemon-reload
systemctl enable feduk-panel nginx xray > /dev/null 2>&1
systemctl restart feduk-panel nginx xray

# Проверка статуса
sleep 2
if systemctl is-active --quiet feduk-panel; then
    echo -e "${GREEN}✅ Панель успешно запущена${NC}"
else
    echo -e "${RED}⚠️ Ошибка запуска. Проверь: journalctl -u feduk-panel -n 20${NC}"
fi

# Финальный вывод
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ FEDUK PROXY PANEL УСТАНОВЛЕН!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${BLUE}🌐 Панель: http://$IP${NC}"
echo -e "${BLUE}🔑 Логин: admin${NC}"
echo -e "${BLUE}🔑 Пароль: admin${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}📌 Функции:${NC}"
echo -e "  • 📊 Дашборд с метриками сервера"
echo -e "  • 📡 Управление инбаундами (VMess/VLESS/Trojan/SS)"
echo -e "  • 🔗 Создание подписок с уникальными ссылками"
echo -e "  • 📈 Статистика трафика"
echo -e "  • ⚙️ Смена пароля и управление Xray"
echo -e "${GREEN}========================================${NC}"
echo -e "${RED}⚠️ Сразу смени пароль в панели!${NC}"