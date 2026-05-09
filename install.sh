#!/bin/bash
set -e

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
        FEDUK PROXY PANEL v2.0
        Всё лучшее в одном месте
EOF
echo -e "${NC}"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Запусти с sudo${NC}"
   exit 1
fi

IP=$(curl -s ifconfig.me)
COUNTRY=$(curl -s http://ip-api.com/line/$IP?fields=countryCode 2>/dev/null | head -1)
[ -z "$COUNTRY" ] && COUNTRY="RU"

echo -e "${GREEN}🌍 Сервер: $IP (${COUNTRY})${NC}"

# Обновление
apt update -y && apt upgrade -y -qq
apt install -y curl wget unzip nginx ufw python3-pip jq bc > /dev/null 2>&1

# Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install > /dev/null 2>&1

# Python пакеты (без виртуалки)
pip3 install fastapi uvicorn python-multipart passlib bcrypt python-jose[cryptography] aiofiles psutil requests --break-system-packages > /dev/null 2>&1

# Структура
mkdir -p /opt/feduk-panel
mkdir -p /etc/feduk-panel
mkdir -p /var/lib/feduk-panel/{subscriptions,stats,users}

# Создаем админа
echo '{"username":"admin","password_hash":"8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918"}' > /etc/feduk-panel/admin.json

# main.py
cat > /opt/feduk-panel/main.py << 'MAINEOF'
import os, json, hashlib, secrets, psutil, time, uuid
from datetime import datetime, timedelta
from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.responses import HTMLResponse, PlainTextResponse
from pydantic import BaseModel
from typing import Optional
from jose import jwt

ADMIN_FILE = "/etc/feduk-panel/admin.json"
CONFIG_FILE = "/etc/feduk-panel/xray_config.json"
SUBS_DIR = "/var/lib/feduk-panel/subscriptions"
JWT_SECRET = secrets.token_hex(32)

app = FastAPI()
security = HTTPBearer()

def verify_token(creds: HTTPAuthorizationCredentials = Depends(security)):
    try:
        return jwt.decode(creds.credentials, JWT_SECRET, algorithms=["HS256"])
    except:
        raise HTTPException(401)

class LoginData(BaseModel):
    username: str
    password: str

class InboundData(BaseModel):
    port: int
    protocol: str
    remark: str
    limit_mb: Optional[int] = None

class SubData(BaseModel):
    name: str
    inbound_port: int
    expiry_days: int = 30

@app.get("/api/system")
def system():
    return {
        "ip": os.popen("curl -s ifconfig.me").read().strip(),
        "country": os.popen("curl -s http://ip-api.com/line/$(curl -s ifconfig.me) 2>/dev/null | head -1").read().strip(),
        "cpu": psutil.cpu_percent(),
        "ram": psutil.virtual_memory().percent,
        "uptime": time.time() - psutil.boot_time(),
        "xray": "active" if os.system("systemctl is-active xray >/dev/null 2>&1") == 0 else "inactive"
    }

@app.get("/api/ping")
def ping():
    r = os.popen("ping -c 1 -W 2 8.8.8.8 | tail -1 | awk -F '/' '{print $5}'").read().strip()
    return {"ping": r if r else "N/A"}

@app.post("/api/login")
def login(data: LoginData):
    with open(ADMIN_FILE) as f:
        admin = json.load(f)
        if admin["username"] == data.username and admin["password_hash"] == hashlib.sha256(data.password.encode()).hexdigest():
            token = jwt.encode({"sub": data.username, "exp": datetime.utcnow() + timedelta(days=1)}, JWT_SECRET, algorithm="HS256")
            return {"token": token}
    raise HTTPException(401)

@app.post("/api/change-password")
def change_pass(data: LoginData, _=Depends(verify_token)):
    with open(ADMIN_FILE, "w") as f:
        json.dump({"username": data.username, "password_hash": hashlib.sha256(data.password.encode()).hexdigest()}, f)
    return {"ok": True}

@app.get("/api/inbounds", dependencies=[Depends(verify_token)])
def get_inbounds():
    if not os.path.exists(CONFIG_FILE):
        return {"inbounds": []}
    with open(CONFIG_FILE) as f:
        cfg = json.load(f)
    inbounds = []
    for i in cfg.get("inbounds", []):
        inbounds.append({
            "port": i["port"],
            "protocol": i["protocol"],
            "remark": i.get("remark", ""),
            "limit_mb": i.get("limit_mb", 0),
            "clients": len(i.get("settings", {}).get("clients", []))
        })
    return {"inbounds": inbounds}

@app.post("/api/inbounds", dependencies=[Depends(verify_token)])
def add_inbound(data: InboundData):
    cfg = {"inbounds": [], "outbounds": [{"protocol": "freedom", "settings": {}}]}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            cfg = json.load(f)
    
    cfg["inbounds"].append({
        "port": data.port,
        "protocol": data.protocol,
        "settings": {"clients": []},
        "streamSettings": {"network": "tcp", "security": "none" if data.protocol == "vmess" else "tls"},
        "remark": data.remark,
        "limit_mb": data.limit_mb
    })
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)
    os.system("systemctl restart xray")
    return {"ok": True}

@app.delete("/api/inbounds/{port}", dependencies=[Depends(verify_token)])
def del_inbound(port: int):
    with open(CONFIG_FILE) as f:
        cfg = json.load(f)
    cfg["inbounds"] = [i for i in cfg["inbounds"] if i["port"] != port]
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)
    os.system("systemctl restart xray")
    return {"ok": True}

@app.get("/api/subscriptions", dependencies=[Depends(verify_token)])
def get_subs():
    if not os.path.exists(SUBS_DIR):
        return {"subscriptions": []}
    subs = []
    for f in os.listdir(SUBS_DIR):
        if f.endswith(".json"):
            with open(os.path.join(SUBS_DIR, f)) as sf:
                subs.append(json.load(sf))
    return {"subscriptions": subs}

@app.post("/api/subscriptions", dependencies=[Depends(verify_token)])
def create_sub(data: SubData):
    sid = str(uuid.uuid4())[:8]
    sub = {
        "id": sid,
        "name": data.name,
        "inbound_port": data.inbound_port,
        "created": datetime.now().isoformat(),
        "expiry": (datetime.now() + timedelta(days=data.expiry_days)).isoformat(),
        "users": []
    }
    with open(os.path.join(SUBS_DIR, f"{sid}.json"), "w") as f:
        json.dump(sub, f, indent=2)
    return {"id": sid, "url": f"/sub/{sid}"}

@app.get("/sub/{sid}")
def get_sub(sid: str):
    fpath = os.path.join(SUBS_DIR, f"{sid}.json")
    if not os.path.exists(fpath):
        raise HTTPException(404)
    return PlainTextResponse(f"订阅链接: /sub/{sid}\n暂未配置节点", media_type="text/plain")

@app.get("/api/stats", dependencies=[Depends(verify_token)])
def stats():
    return {"stats": {}}

@app.get("/", response_class=HTMLResponse)
def root():
    return '''
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FEDUK PANEL</title>
    <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:system-ui;background:linear-gradient(135deg,#0a0e27,#1a1f3a);min-height:100vh;color:#fff}
        .container{max-width:1400px;margin:0 auto;padding:20px}
        .login-card{max-width:400px;margin:100px auto;background:rgba(30,41,59,0.9);backdrop-filter:blur(10px);border-radius:24px;padding:40px;border:1px solid rgba(59,130,246,0.3)}
        .login-card input,.login-card button{width:100%;padding:14px;margin:12px 0;background:#0f172a;border:1px solid #334155;border-radius:12px;color:#fff}
        .login-card button{background:linear-gradient(135deg,#3b82f6,#8b5cf6);border:none;cursor:pointer;font-weight:bold}
        .tabs{display:flex;gap:12px;margin-bottom:30px;flex-wrap:wrap;background:rgba(15,23,42,0.7);padding:15px 20px;border-radius:60px}
        .tab{padding:12px 24px;border-radius:40px;cursor:pointer;font-weight:600;color:#94a3b8}
        .tab.active{background:linear-gradient(135deg,#3b82f6,#8b5cf6);color:#fff}
        .card{background:rgba(30,41,59,0.7);backdrop-filter:blur(5px);border-radius:20px;padding:20px;margin-bottom:20px;border:1px solid rgba(59,130,246,0.2)}
        .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(350px,1fr));gap:20px}
        .stat-card{background:linear-gradient(135deg,#1e293b,#0f172a);border-radius:20px;padding:25px;text-align:center}
        .stat-value{font-size:48px;font-weight:bold;color:#3b82f6;margin:10px 0}
        button{background:linear-gradient(135deg,#3b82f6,#8b5cf6);border:none;padding:10px 20px;border-radius:12px;color:#fff;cursor:pointer}
        input,select{background:#0f172a;border:1px solid #334155;padding:10px;border-radius:12px;color:#fff;margin:5px}
        .hidden{display:none}
        .server-info{background:linear-gradient(135deg,#3b82f6,#8b5cf6);border-radius:20px;padding:20px;margin-bottom:30px;display:flex;justify-content:space-between;flex-wrap:wrap}
        h2{margin-bottom:20px;color:#3b82f6}
    </style>
</head>
<body>
<div id="loginDiv" class="container">
    <div class="login-card">
        <h2 style="text-align:center">🔐 FEDUK PANEL</h2>
        <input type="text" id="username" placeholder="Логин" value="admin">
        <input type="password" id="password" placeholder="Пароль" value="admin">
        <button onclick="login()">Войти</button>
    </div>
</div>
<div id="appDiv" class="container hidden">
    <div class="server-info" id="serverInfo">🖥️ Загрузка...</div>
    <div class="tabs">
        <div class="tab active" onclick="showTab('dashboard')">📊 Дашборд</div>
        <div class="tab" onclick="showTab('inbounds')">📡 Инбаунды</div>
        <div class="tab" onclick="showTab('subscriptions')">🔗 Подписки</div>
        <div class="tab" onclick="showTab('settings')">⚙️ Настройки</div>
        <div class="tab" onclick="logout()" style="background:#ef4444">🚪 Выход</div>
    </div>
    <div id="dashboardTab"><div class="grid" id="systemStats"></div></div>
    <div id="inboundsTab" class="hidden">
        <div class="card"><h2>➕ Новый инбаунд</h2>
            <input type="number" id="port" placeholder="Порт">
            <select id="protocol"><option>vmess</option><option>vless</option><option>trojan</option><option>shadowsocks</option></select>
            <input type="text" id="remark" placeholder="Название">
            <input type="number" id="limitMb" placeholder="Лимит MB">
            <button onclick="addInbound()">Создать</button>
        </div>
        <div id="inboundsList"></div>
    </div>
    <div id="subscriptionsTab" class="hidden">
        <div class="card"><h2>📎 Создать подписку</h2>
            <input type="text" id="subName" placeholder="Название">
            <input type="number" id="subPort" placeholder="Порт инбаунда">
            <input type="number" id="subDays" placeholder="Срок (дней)" value="30">
            <button onclick="createSub()">Создать</button>
        </div>
        <div id="subsList"></div>
    </div>
    <div id="settingsTab" class="hidden">
        <div class="card"><h2>🔐 Смена пароля</h2>
            <input type="password" id="newPass" placeholder="Новый пароль">
            <button onclick="changePass()">Сменить</button>
        </div>
        <div class="card"><h2>🔄 Управление</h2>
            <button onclick="restartXray()">Перезапустить Xray</button>
        </div>
    </div>
</div>
<script>
let token=null;
async function api(path,method="GET",body=null){
    const res=await fetch(path,{method,headers:{"Authorization":`Bearer ${token}`,"Content-Type":"application/json"},body:body?JSON.stringify(body):null});
    if(res.status===401)logout();
    return res.json();
}
async function login(){
    const res=await fetch("/api/login",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({username:username.value,password:password.value})});
    const d=await res.json();
    if(d.token){token=d.token;document.getElementById("loginDiv").classList.add("hidden");document.getElementById("appDiv").classList.remove("hidden");loadAll();}
    else alert("Ошибка");
}
function logout(){token=null;location.reload();}
function showTab(t){
    ["dashboard","inbounds","subscriptions","settings"].forEach(x=>document.getElementById(x+"Tab").classList.add("hidden"));
    document.getElementById(t+"Tab").classList.remove("hidden");
    if(t=="dashboard")loadDashboard();
    if(t=="inbounds")loadInbounds();
    if(t=="subscriptions")loadSubs();
}
async function loadAll(){loadDashboard();loadInbounds();loadServer();}
async function loadServer(){
    const sys=await api("/api/system");
    const ping=await api("/api/ping");
    document.getElementById("serverInfo").innerHTML=`<span>🌍 ${sys.ip} (${sys.country})</span><span>🏓 ${ping.ping}ms</span><span>💻 CPU:${sys.cpu}% RAM:${sys.ram}%</span><span>✅ Xray:${sys.xray}</span>`;
}
async function loadDashboard(){
    const sys=await api("/api/system");
    document.getElementById("systemStats").innerHTML=`
        <div class="stat-card"><div class="stat-value">${sys.cpu}%</div><div>CPU</div></div>
        <div class="stat-card"><div class="stat-value">${sys.ram}%</div><div>RAM</div></div>
        <div class="stat-card"><div class="stat-value">${Math.floor(sys.uptime/86400)}д</div><div>Аптайм</div></div>`;
}
async function loadInbounds(){
    const d=await api("/api/inbounds");
    if(d.inbounds){
        let html=d.inbounds.map(i=>`<div class="card"><strong>📡 ${i.remark}</strong><br>Порт:${i.port} | ${i.protocol}<br>Клиентов:${i.clients}<br><button onclick="delInbound(${i.port})">Удалить</button></div>`).join("");
        document.getElementById("inboundsList").innerHTML=html||"Нет инбаундов";
    }
}
async function addInbound(){
    await api("/api/inbounds","POST",{port:parseInt(port.value),protocol:protocol.value,remark:remark.value,limit_mb:parseInt(limitMb.value)||null});
    loadInbounds();
}
async function delInbound(p){if(confirm("Удалить?")){await api(`/api/inbounds/${p}`,"DELETE");loadInbounds();}}
async function loadSubs(){
    const d=await api("/api/subscriptions");
    if(d.subscriptions){
        let html=d.subscriptions.map(s=>`<div class="card"><strong>🔗 ${s.name}</strong><br>ID:${s.id}<br><a href="/sub/${s.id}" target="_blank">/sub/${s.id}</a></div>`).join("");
        document.getElementById("subsList").innerHTML=html;
    }
}
async function createSub(){
    await api("/api/subscriptions","POST",{name:subName.value,inbound_port:parseInt(subPort.value),expiry_days:parseInt(subDays.value)});
    loadSubs();
}
async function changePass(){
    await api("/api/change-password","POST",{username:"admin",password:newPass.value});
    alert("Пароль изменён! Перезайдите.");
    logout();
}
function restartXray(){fetch("/api/restart",{method:"POST",headers:{"Authorization":`Bearer ${token}`}}).then(()=>alert("Xray перезапущен"));}
</script>
</body>
</html>
'''

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
MAINEOF

# Systemd сервис
cat > /etc/systemd/system/feduk-panel.service << EOF
[Unit]
Description=FEDUK Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/feduk-panel
ExecStart=/usr/bin/python3 /opt/feduk-panel/main.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Nginx
cat > /etc/nginx/sites-available/feduk-panel << EOF
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf /etc/nginx/sites-available/feduk-panel /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# UFW
ufw allow 80/tcp 443/tcp > /dev/null 2>&1
echo "y" | ufw enable > /dev/null 2>&1

# Запуск
systemctl daemon-reload
systemctl enable feduk-panel nginx xray > /dev/null 2>&1
systemctl restart feduk-panel nginx xray

sleep 2
if systemctl is-active --quiet feduk-panel; then
    echo -e "${GREEN}✅ Панель запущена${NC}"
else
    echo -e "${RED}⚠️ Ошибка: journalctl -u feduk-panel -n 20${NC}"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ FEDUK PROXY PANEL УСТАНОВЛЕН!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${BLUE}🌐 Панель: http://$IP${NC}"
echo -e "${BLUE}🔑 Логин: admin${NC}"
echo -e "${BLUE}🔑 Пароль: admin${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}📌 Функции: Дашборд | Инбаунды | Подписки | Статистика | Настройки${NC}"
echo -e "${RED}⚠️ Сразу смени пароль!${NC}"
