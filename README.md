<div align="center">

# ⚡ FEDUK Proxy Panel v3.0

**Современная панель управления прокси-серверами**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Python](https://img.shields.io/badge/python-3.10%2B-blue)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.111-green)](https://fastapi.tiangolo.com)
[![Xray](https://img.shields.io/badge/Xray--core-latest-purple)](https://github.com/XTLS/Xray-core)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%20|%2022.04%20|%2024.04-orange)](https://ubuntu.com)

</div>

---

## 🖼️ Скриншоты

### 🔐 Вход в панель
![Login](screenshot_login.png)

### 📊 Дашборд
![Dashboard](screenshot_dashboard.png)

### 🔌 Inbounds — управление протоколами
![Inbounds](screenshot_inbounds.png)

### 👥 Клиенты — управление пользователями
![Clients](screenshot_clients.png)

### 🔧 Статус сервисов
![Status](screenshot_status.png)

---

## ✨ Возможности

- **Протоколы:** VMess · VLESS · Trojan · Shadowsocks · WireGuard · SOCKS5 · Reality
- **SSL:** Let's Encrypt (автоматически) или самоподписанный
- **Авторизация:** JWT-токены, bcrypt хеширование паролей
- **Мониторинг:** CPU, RAM, диск, трафик в реальном времени
- **Автоматизация:** авто-бэкап, авто-обновление сертификатов
- **Тёмная/светлая** тема прямо в панели

---

## 🚀 Установка

Одна команда — всё остальное скрипт делает сам:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/install.sh)
```

Или скачать и запустить:

```bash
wget https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/install.sh
bash install.sh
```

> Требуется **root** и **Ubuntu 20.04 / 22.04 / 24.04** или **Debian 11 / 12**

---

## ⚙️ Что делает установщик

| Шаг | Действие |
|-----|----------|
| 1 | Проверка системы, определение IP |
| 2 | Установка зависимостей (Python, Node.js, Redis, Nginx) |
| 3 | Настройка файрвола UFW |
| 4 | Установка Xray-core (последняя версия) |
| 5 | **SSL сертификат** — Let's Encrypt если указан домен, иначе self-signed |
| 6 | FastAPI бэкенд + SQLite база данных |
| 7 | Красивый веб-интерфейс |
| 8 | Systemd сервисы (автозапуск) |
| 9 | Создание admin пользователя |
| 10 | Вывод URL, логина и пароля |

---

## 🔒 Безопасность

- Пароли хешируются через **bcrypt** (12 rounds)
- JWT токены с TTL 24 часа
- TLS 1.2 / 1.3 только
- Заголовки HSTS, X-Frame-Options, CSP
- Авто-обновление Let's Encrypt сертификатов

---

## 📋 Управление

```bash
# Статус сервисов + данные доступа
feduk-status

# Создать бэкап
feduk-backup

# Логи панели
journalctl -u feduk -f

# Логи Xray
journalctl -u xray-feduk -f

# Перезапуск
systemctl restart feduk
```

---

## 📁 Структура

```
/opt/feduk/
├── panel/
│   ├── main.py          # FastAPI приложение
│   ├── static/          # Фронтенд (HTML/CSS/JS)
│   └── venv/            # Python окружение
├── xray/
│   ├── bin/xray         # Xray-core
│   └── configs/         # Конфиги
├── certs/               # SSL сертификаты
├── data/config.db       # SQLite база
└── logs/                # Логи

/etc/feduk/config.yml    # Конфиг приложения
/root/.feduk_credentials # Данные доступа
```

---

<div align="center">

Сделано с ❤️ | [Сообщить об ошибке](../../issues)

</div>
