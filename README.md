<div align="center">

<pre>
███████╗███████╗██████╗ ██╗   ██╗██╗  ██╗
██╔════╝██╔════╝██╔══██╗██║   ██║██║ ██╔╝
█████╗  █████╗  ██║  ██║██║   ██║█████╔╝
██╔══╝  ██╔══╝  ██║  ██║██║   ██║██╔═██╗
██║     ███████╗██████╔╝╚██████╔╝██║  ██╗
╚═╝     ╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝
</pre>

# FEDUK Proxy Panel v3.1

**Полностью автоматическая установка прокси-сервера на базе Xray-core**  
VMess · VLESS · Trojan · Shadowsocks · WireGuard · SOCKS5 · HTTP · Reality

[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%20|%2022.04%20|%2024.04-E95420?style=flat-square&logo=ubuntu)](https://ubuntu.com)
[![Debian](https://img.shields.io/badge/Debian-11%20|%2012-A81D33?style=flat-square&logo=debian)](https://debian.org)
[![Xray](https://img.shields.io/badge/Xray--core-latest-blue?style=flat-square)](https://github.com/XTLS/Xray-core)
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?style=flat-square&logo=python)](https://python.org)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

</div>

---

## 🚀 Быстрая установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/holodgolod745-max/vpn-panel8/main/install.sh)
```

> Запускать от `root`. Установка занимает ~3–5 минут.

**Рекомендуется через `tmux`** — чтобы SSH-разрыв не прервал установку:

```bash
apt install tmux -y && tmux new -s install
bash <(curl -fsSL https://raw.githubusercontent.com/holodgolod745-max/vpn-panel8/main/install.sh)
# Если соединение оборвалось — переподключись и:
tmux attach -t install
```

---

## ✨ Ключевые возможности

- **16 шагов** полностью автоматической установки с цветным прогресс-баром
- **Умное определение портов** — если 443/80 заняты другой панелью (3x-ui, x-ui, marzban), автоматически выбирает свободные
- **Обнаружение конфликтующих панелей** — предупреждает о x-ui, 3x-ui, marzban ещё до начала установки
- **Повторная установка** — сохраняет БД и сертификаты в `/root/feduk_backup_<timestamp>` перед перезаписью
- **Self-healing** — health-check после установки автоматически диагностирует и перезапускает упавшие сервисы (до 5 попыток)
- **SSL** — Let's Encrypt по домену (с проверкой DNS) или self-signed RSA-4096 на 10 лет как fallback
- **TCP оптимизация ядра** — BBR congestion control, увеличенные буферы, лимиты файловых дескрипторов
- **Авто-бэкап** — ежедневно в 03:00, хранит 30 дней
- **Авто-обновление GeoIP/GeoSite** — каждое воскресенье в 04:00

---

## ⚙️ Что устанавливается

| Компонент | Версия | Описание |
|-----------|--------|----------|
| **Xray-core** | latest (fallback v1.8.13) | Прокси-ядро XTLS/Reality |
| **FastAPI** | 0.111.0 | Backend REST API |
| **Uvicorn** | 0.29.0 | ASGI сервер |
| **SQLAlchemy** | 2.0.30 | ORM / SQLite |
| **Pydantic** | 2.7.1 | Валидация данных |
| **python-jose** | 3.3.0 | JWT токены |
| **bcrypt** | 4.1.3 | Хэширование паролей |
| **Nginx** | system | Reverse proxy + TLS termination |
| **Redis** | system | Кэш сессий |
| **Node.js** | 20.x | Фронтенд (устанавливается если < 18) |
| **Certbot** | latest | Let's Encrypt (только при домене) |

---

## 🔢 Шаги установки (16 шагов)

| # | Функция | Что делает |
|---|---------|-----------|
| 1 | `preflight` | Проверяет root, RAM (мин. 512MB), диск (мин. 2GB), ОС, архитектуру (x86_64/aarch64/armv7l). Обнаруживает конфликтующие панели. Определяет IP через 3 сервиса с fallback на hostname. Генерирует пароль 16 символов. Спрашивает домен, проверяет DNS. Определяет свободные порты. |
| 2 | `install_packages` | Снимает APT lock-файлы (`/var/lib/dpkg/lock*`, `/var/cache/apt/archives/lock`), запускает `dpkg --configure -a`, 3 попытки `apt-get update` с паузой 5 сек. Устанавливает curl, wget, nginx, redis, python3, build-essential и др. Node.js 20 — только если текущая версия < 18. |
| 3 | `configure_firewall` | Настраивает UFW (deny incoming, allow outgoing, SSH/HTTP/HTTPS). Применяет TCP BBR через modprobe, записывает оптимизации в `/etc/sysctl.d/99-feduk.conf` (BBR, fastopen, keepalive, буферы до 16MB). Лимиты fd в `/etc/security/limits.d/99-feduk.conf` (1048576). |
| 4 | `create_directories` | Создаёт `/opt/feduk/{xray/{bin,configs},panel/{static,venv},certs,data,logs,backups}` и `/etc/feduk/`. Права: 750 на корень, 700 на certs, 750 на data. |
| 5 | `install_xray` | Получает последнюю версию через GitHub API (fallback v1.8.13). Скачивает zip, распаковывает, устанавливает бинарник с chmod 755. GeoIP и GeoSite от Loyalsoldier через `run_step_soft` (не критично). |
| 6 | `setup_ssl` | Если домен + DNS совпадает с IP: certbot standalone, симлинки на `/etc/letsencrypt/live/`. Если ошибка certbot — fallback на self-signed. Без домена: `_self_signed()` — openssl RSA-4096, SAN с IP и доменом, 3650 дней. |
| 7 | `create_xray_config` | Генерирует `config.json`: API на 127.0.0.1:10085, Stats+Policy для учёта трафика, routing (приватные IP→direct, реклама→blocked через geosite:category-ads-all). |
| 8 | `setup_python_backend` | Создаёт venv, обновляет pip, устанавливает 9 зависимостей. Генерирует полный `main.py` FastAPI (~1300 строк) с аутентификацией, CRUD для inbounds/clients, статистикой, проксированием к Xray API. |
| 9 | `create_frontend` | Генерирует Web UI: HTML/CSS/JS панель управления. |
| 10 | `configure_nginx` | Определяет версию nginx, выбирает синтаксис HTTP/2. Освобождает порты через `fuser -k`. Создаёт конфиг с SSL, proxy_pass на uvicorn, WebSocket upgrade. Проверяет `nginx -t`, до 2 попыток запуска. |
| 11 | `create_app_config` | Создаёт `/etc/feduk/config.yml` с JWT secret (openssl rand -hex 32), xray_api_port 10085, redis 127.0.0.1:6379. Проверяет что secret не дефолтный. |
| 12 | `configure_redis` | Включает и перезапускает redis-server. Ждёт `redis-cli ping → PONG` до 10 секунд. |
| 13 | `create_systemd_services` | Unit-файлы для `xray-feduk` (Xray бинарник) и `feduk` (uvicorn на BACKEND_PORT). Запускает через `run_step_soft`. |
| 14 | `init_admin_db` | Инициализирует SQLite, создаёт таблицы, добавляет admin с bcrypt-хэшем. |
| 15 | `setup_extras` | Устанавливает `feduk-status`, `feduk-backup`, `feduk-log`. Настраивает logrotate (14 дней, compress). Cron: бэкап 03:00 ежедневно, обновление geo в воскресенье 04:00. Systemd timer для certbot (03:00 и 15:00). Сохраняет credentials в `/root/.feduk_credentials` (chmod 600). |
| 16 | `health_check` | До 5 попыток: curl на `https://127.0.0.1:PANEL_PORT/api/health` + внешний URL. При неудаче — `_heal_services()`: рестарт Redis, feduk, nginx, открытие UFW-порта, пересоздание сертификата, пересоздание nginx конфига. |

---

## 🔌 Умный выбор портов

Если стандартные порты заняты (3x-ui, x-ui и т.п.), скрипт автоматически ищет свободные ещё в `preflight`, до установки:

| Назначение | По умолчанию | Автоподбор |
|------------|-------------|-----------|
| HTTPS (панель) | 443 | 8443 → 8444 → 8445 → 9443 → 10443 |
| HTTP (редирект) | 80 | 8080 → 8081 → 8088 → 9080 |
| Бэкенд (uvicorn) | 8000 | 8001 → 8002 → 8003 → 8010 |

Итоговый URL с нестандартным портом: `https://IP:8443`

---

## 📁 Структура файлов после установки

```
/opt/feduk/
├── panel/
│   ├── main.py              # FastAPI backend (~1300 строк)
│   ├── static/              # Web UI
│   └── venv/                # Python virtualenv
├── xray/
│   ├── bin/xray             # Xray-core бинарник (chmod 755)
│   └── configs/
│       ├── config.json      # Основной конфиг Xray
│       ├── geoip.dat        # GeoIP база (Loyalsoldier)
│       └── geosite.dat      # GeoSite база (Loyalsoldier)
├── certs/
│   ├── cert.pem             # SSL сертификат (chmod 644)
│   └── key.pem              # SSL ключ (chmod 600)
├── data/
│   └── feduk.db             # SQLite база данных (chmod 750)
├── logs/
│   ├── xray-access.log
│   ├── xray-error.log
│   ├── panel-error.log
│   ├── nginx-access.log
│   └── backup.log
└── backups/                 # Авто-бэкапы (хранятся 30 дней)

/etc/feduk/config.yml            # Настройки панели (chmod 640)
/etc/nginx/sites-available/feduk # Nginx конфиг
/etc/systemd/system/feduk.service
/etc/systemd/system/xray-feduk.service
/etc/sysctl.d/99-feduk.conf      # TCP оптимизации ядра
/etc/security/limits.d/99-feduk.conf
/etc/logrotate.d/feduk
/root/.feduk_credentials         # Логин / пароль / URL (chmod 600)
/var/log/feduk_install.log       # Лог установки
/usr/local/bin/feduk-status      # CLI утилита статуса
/usr/local/bin/feduk-backup      # CLI утилита бэкапа
/usr/local/bin/feduk-log         # CLI утилита логов
```

---

## 🔌 API Endpoints

| Метод | Путь | Описание |
|-------|------|----------|
| `POST` | `/api/auth/token` | Получить JWT токен |
| `GET` | `/api/dashboard` | Метрики системы (CPU, RAM, сеть) |
| `GET` | `/api/inbounds` | Список inbounds |
| `POST` | `/api/inbounds` | Создать inbound |
| `DELETE` | `/api/inbounds/{id}` | Удалить inbound |
| `GET` | `/api/clients` | Список клиентов |
| `POST` | `/api/clients` | Создать клиента |
| `GET` | `/api/status` | Статус сервисов (Redis, Xray, Nginx) |
| `POST` | `/api/xray/restart` | Перезапустить Xray |
| `GET` | `/api/health` | Health check |
| `GET` | `/api/docs` | Swagger UI |

---

## 🛡️ Безопасность

- **HTTPS** с Let's Encrypt или self-signed RSA-4096 (10 лет)
- **JWT** — `python-jose[cryptography]`, secret key через `openssl rand -hex 32`, проверяется на дефолтное значение
- **bcrypt 4.1.3** — прямое использование без passlib (passlib несовместима с bcrypt ≥ 4.x из-за удалённого `__about__`)
- **UFW** — deny incoming по умолчанию, открыты только SSH, HTTP, HTTPS
- **Права файлов** — ключ 600, конфиг 640, credentials 600, certs/ директория 700
- **Автообновление Let's Encrypt** — systemd timer дважды в сутки (03:00 и 15:00) с рандомной задержкой до 1 часа

---

## 🔧 Управление после установки

```bash
# ── Статус одной командой ──────────────────────
feduk-status

# ── Управление сервисами ───────────────────────
systemctl status feduk xray-feduk nginx redis-server
systemctl restart feduk          # Перезапуск панели
systemctl restart xray-feduk     # Перезапуск Xray

# ── Просмотр логов ────────────────────────────
feduk-log panel     # Логи FastAPI / uvicorn (journalctl -u feduk -f)
feduk-log xray      # Логи Xray (journalctl -u xray-feduk -f)
feduk-log nginx     # nginx-access.log
feduk-log errors    # panel-error.log
feduk-log all       # Все сервисы сразу

# ── Бэкап ─────────────────────────────────────
feduk-backup        # /opt/feduk/backups/backup_YYYYMMDD_HHMMSS.tar.gz
                    # Содержит: data/, certs/, xray/configs/, /etc/feduk/
                    # Авто-удаление через 30 дней

# ── Данные доступа ────────────────────────────
cat /root/.feduk_credentials

# ── Xray конфиг ───────────────────────────────
/opt/feduk/xray/bin/xray -test -config /opt/feduk/xray/configs/config.json
```

---

## ❗ Частые ошибки и решения

### APT update завершился с ошибкой (код 100)

**Причина:** сломанный сторонний репозиторий — чаще всего `ookla/speedtest-cli`, который не поддерживает Ubuntu Noble (24.04).

**Что делает скрипт:** снимает lock-файлы (`/var/lib/dpkg/lock-frontend`, `/var/lib/dpkg/lock`, `/var/cache/apt/archives/lock`, `/var/lib/apt/lists/lock`), запускает `dpkg --configure -a`, 3 попытки с паузой 5 сек. При провале всех — предупреждение, установка продолжается с кешем.

**Исправить вручную:**
```bash
rm -f /etc/apt/sources.list.d/ookla_speedtest-cli.list
rm -f /etc/apt/sources.list.d/packagecloud*.list
apt-get update
```

---

### SSH сессия разорвалась во время установки

**Причина:** `configure_firewall` перезапускает UFW и применяет sysctl, что может разорвать активное SSH-соединение.

**Всегда запускай через tmux:**
```bash
apt install tmux -y && tmux new -s install
# После разрыва:
tmux attach -t install
```

**Проверить статус после переподключения:**
```bash
tail -30 /var/log/feduk_install.log
systemctl status feduk xray-feduk nginx
```

---

### Nginx не запускается — порт занят (3x-ui)

**Причина:** 3x-ui, x-ui или другой процесс занял порт 443 или 80.

**Что делает скрипт:** `preflight` проверяет порты через `ss -tlnp` и автоматически переключается на альтернативные (443→8443, 80→8080). `configure_nginx` дополнительно вызывает `fuser -k PORT/tcp` перед запуском nginx.

**Диагностика вручную:**
```bash
ss -tlnp | grep -E ':80 |:443 '
fuser 443/tcp                          # Кто занимает порт
systemctl status nginx
journalctl -u nginx -n 30
nginx -t                               # Проверка конфига
```

---

### Панель недоступна после установки

**Что делает скрипт:** `health_check` делает до 5 попыток. Между попытками `_heal_services()` проверяет и перезапускает Redis, feduk (uvicorn), nginx, открывает UFW-порт, пересоздаёт сертификат если нет файлов, пересоздаёт nginx конфиг если `nginx -t` упал.

**Диагностика вручную:**
```bash
feduk-status
curl -sk https://127.0.0.1:443/api/health    # Внутренняя проверка
curl -sk https://YOUR_IP:443/api/health      # Внешняя проверка
journalctl -u feduk -n 50
journalctl -u nginx -n 20
cat /opt/feduk/logs/panel-error.log
nginx -t
ufw status
```

---

### Redis не отвечает

**Причина:** Redis не успел запуститься или конфликт с существующей установкой.

**Что делает скрипт:** ждёт `redis-cli ping → PONG` до 10 секунд. При таймауте — предупреждение, установка продолжается (панель работает без кэша в деградированном режиме).

```bash
systemctl status redis-server
journalctl -u redis-server -n 20
systemctl restart redis-server
redis-cli ping    # Должно вернуть PONG
```

---

### Certbot не получил сертификат

**Причины:**
- A-запись домена не настроена или не распространилась
- IP в A-записи не совпадает с IP сервера
- Порт 80 занят в момент запуска certbot (скрипт останавливает nginx, но другой процесс может держать порт)

**Что делает скрипт:** перед вызовом certbot проверяет DNS через `dig +short`. Если IP не совпадает с `SERVER_IP` — сразу переходит к self-signed. При ошибке certbot — fallback на self-signed RSA-4096.

**Повторить вручную:**
```bash
systemctl stop nginx
certbot certonly --standalone -d your.domain.com
ln -sf /etc/letsencrypt/live/your.domain.com/fullchain.pem /opt/feduk/certs/cert.pem
ln -sf /etc/letsencrypt/live/your.domain.com/privkey.pem /opt/feduk/certs/key.pem
systemctl start nginx && systemctl restart feduk xray-feduk
```

---

### Браузер предупреждает о сертификате

**Причина:** self-signed сертификат — установка прошла без домена или certbot не смог получить сертификат.

Нажмите «Дополнительно» → «Продолжить» — соединение зашифровано RSA-4096.

Для доверенного сертификата: настройте A-запись домена → IP сервера, переустановите панель с указанием домена.

---

### Повторная установка — конфликт с предыдущей

При обнаружении `/root/.feduk_credentials` или `/opt/feduk/` скрипт предлагает:
- **Y (по умолчанию, таймаут 30 сек)** — копирует `data/`, `certs/`, `config.yml` в `/root/feduk_backup_<timestamp>`
- **N** — чистая установка

```bash
# Восстановить из бэкапа вручную:
ls /root/feduk_backup_*/
cp -r /root/feduk_backup_TIMESTAMP/data /opt/feduk/
systemctl restart feduk
```

---

## 🔄 Автоматические задачи

| Время | Задача | Логи |
|-------|--------|------|
| Ежедневно 03:00 | `feduk-backup` — бэкап data/, certs/, configs/, /etc/feduk/ | `/opt/feduk/logs/backup.log` |
| Воскресенье 04:00 | Обновление `geoip.dat` + `systemctl restart xray-feduk` | `/opt/feduk/logs/backup.log` |
| Пн–Вс 03:00 и 15:00 | `certbot renew` (только при Let's Encrypt) | systemd journal |

---

## 🔍 Конфигурация Xray (config.json)

Базовый конфиг содержит:

- **API** — порт 10085, только 127.0.0.1, сервисы: HandlerService, LoggerService, StatsService
- **Stats + Policy** — сбор трафика по пользователям и inbound/outbound направлениям
- **Outbound direct** — `UseIPv4` (без IPv6 утечек)
- **Outbound blackhole** — для блокировки рекламы
- **Routing** — приватные IP → direct, geosite:category-ads-all → blocked, api-inbound → api

Inbounds (VMess, VLESS, Trojan, Shadowsocks, Reality и др.) добавляются через API панели.

---

<div align="center">

Made with ❤️ · [Сообщить об ошибке](../../issues) · [Документация API](/api/docs)

</div>
