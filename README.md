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

**Полностью автоматическая установка прокси-сервера**  
VMess · VLESS · Trojan · Shadowsocks · WireGuard · Reality

[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%20|%2022.04%20|%2024.04-E95420?style=flat-square&logo=ubuntu)](https://ubuntu.com)
[![Debian](https://img.shields.io/badge/Debian-11%20|%2012-A81D33?style=flat-square&logo=debian)](https://debian.org)
[![Xray](https://img.shields.io/badge/Xray--core-latest-blue?style=flat-square)](https://github.com/XTLS/Xray-core)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

</div>

---

## 🚀 Быстрая установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USER/feduk-panel/main/install.sh)
```

> Запускать от `root`. Установка занимает ~3-5 минут.

---

## 📸 Скриншоты

### 1. Запуск установщика

Подключаемся к серверу по SSH и запускаем скрипт — появляется баннер и начинается автопроверка системы.

![Баннер установщика](01_installer_banner.png)

---

### 2. Процесс установки

Установщик последовательно проходит все 16 шагов с прогресс-баром и спиннером. Каждый шаг логируется в `/var/log/feduk_install.log`.

![Прогресс установки](02_installer_progress.png)

---

### 3. Установка завершена

По завершении скрипт выводит итоговый экран с URL панели, логином и паролем. Данные также сохраняются в `/root/.feduk_credentials`.

![Завершение установки](03_installer_complete.png)

---

### 4. Вход в панель управления

Открываем браузер, переходим по адресу панели и вводим данные из финального экрана установщика.

![Страница входа](04_panel_login.png)

---

### 5. Дашборд

Главный экран с реальными метриками сервера: CPU, RAM, диск, аптайм, трафик и сетевой график в реальном времени (обновляется каждые 10 секунд).

![Дашборд](05_dashboard.png)

---

### 6. Клиенты и QR-коды

Список всех клиентов с информацией о трафике, сроке действия и статусе. Кнопка 📱 генерирует QR-код и ссылку для быстрого подключения из любого клиента (v2rayN, Nekoray, Shadowrocket и др.).

![Клиенты и QR](06_clients_qr.png)

---

### 7. Управление Inbounds

Создание и управление прокси-каналами. Поддерживаемые протоколы: **VLESS**, **VMess**, **Trojan**, **Shadowsocks**. Каждый inbound можно включить/выключить без перезапуска.

![Inbounds](07_inbounds.png)

---

## ⚙️ Что устанавливается

| Компонент | Версия | Описание |
|-----------|--------|----------|
| **Xray-core** | latest | Прокси-ядро (XTLS) |
| **FastAPI** | 0.111 | Backend API |
| **Nginx** | system | Reverse proxy + TLS |
| **Redis** | system | Кэш сессий |
| **SQLite** | — | База данных |
| **Certbot** | latest | Let's Encrypt SSL |

---

## 📁 Структура файлов после установки

```
/opt/feduk/
├── panel/
│   ├── main.py          # FastAPI backend
│   ├── static/          # Web UI
│   └── venv/            # Python virtualenv
├── xray/
│   ├── bin/xray         # Xray-core бинарник
│   └── configs/         # JSON конфиги
└── certs/
    ├── cert.pem          # SSL сертификат
    └── key.pem           # SSL ключ

/etc/feduk/
└── config.yaml           # Настройки панели

/root/.feduk_credentials  # Логин/пароль/URL
/var/log/feduk_install.log # Лог установки
```

---

## 🔌 API Endpoints

| Метод | Путь | Описание |
|-------|------|----------|
| `POST` | `/api/auth/token` | Получить JWT токен |
| `GET` | `/api/dashboard` | Метрики системы |
| `GET` | `/api/inbounds` | Список inbounds |
| `POST` | `/api/inbounds` | Создать inbound |
| `DELETE` | `/api/inbounds/{id}` | Удалить inbound |
| `GET` | `/api/clients` | Список клиентов |
| `POST` | `/api/clients` | Создать клиента |
| `GET` | `/api/status` | Статус сервисов |
| `POST` | `/api/xray/restart` | Перезапустить Xray |
| `GET` | `/api/docs` | Swagger UI |

---

## 🛡️ Безопасность

- HTTPS с Let's Encrypt или self-signed RSA-4096
- JWT авторизация с истечением токена
- UFW файрвол (открыты только 22, 80, 443)
- Пароль хэшируется через bcrypt (cost 12)

---

## 📋 Системные требования

- **ОС:** Ubuntu 20.04 / 22.04 / 24.04 или Debian 11 / 12
- **CPU:** 1 ядро (рекомендуется 2+)
- **RAM:** 512 MB минимум (рекомендуется 1 GB+)
- **Диск:** 2 GB свободного места
- **Сеть:** Публичный IP, открытые порты 80 и 443

---

## 🔧 Управление после установки

```bash
# Статус сервисов
systemctl status feduk xray-feduk nginx

# Перезапуск панели
systemctl restart feduk

# Перезапуск Xray
systemctl restart xray-feduk

# Просмотр логов панели
journalctl -u feduk -f

# Просмотр логов Xray
journalctl -u xray-feduk -f

# Данные для входа
cat /root/.feduk_credentials
```

---

<div align="center">

Made with ❤️ · [Сообщить об ошибке](../../issues) · [Документация API](/api/docs)

</div>
