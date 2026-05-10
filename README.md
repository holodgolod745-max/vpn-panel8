# 🚀 FEDUK PROXY PANEL v3.1

<p align="center">
  <img src="https://img.shields.io/badge/version-3.1.0-blue.svg">
  <img src="https://img.shields.io/badge/Ubuntu-20.04%20|%2022.04%20|%2024.04-orange">
  <img src="https://img.shields.io/badge/Debian-11%20|%2012-red">
  <img src="https://img.shields.io/badge/license-MIT-green">
  <img src="https://img.shields.io/badge/Xray-core-latest-brightgreen">
</p>

**FEDUK Proxy Panel** — это мощная, полностью автоматизированная система управления прокси-серверами. Объединяет в себе лучшие возможности 3x-UI, Marzban и Remnawave. Простая установка, современный веб-интерфейс с тёмной/светлой темами, поддержка всех популярных протоколов и готовые CLI-утилиты.

---

## ✨ Особенности

| Функция | Описание |
|---------|----------|
| **🚀 Одна команда** | Полностью автоматическая установка без вопросов |
| **🎨 Интерфейс** | Тёмная/светлая тема, адаптив под мобильные устройства, графики в реальном времени (WebSocket) |
| **📡 Протоколы** | VMess, VLESS, Trojan, Shadowsocks, WireGuard, SOCKS5, HTTP, Reality |
| **⚙️ Управление** | Inbounds, клиенты, лимиты по трафику, сроки подписки |
| **💾 Резервное копирование** | Автоматический бэкап каждый день в 03:00 |
| **📊 Мониторинг** | CPU, RAM, диск, трафик, статус сервисов |
| **🛠️ CLI** | `feduk-status`, `feduk-backup`, `feduk-log` |
| **🐳 Технологии** | Python 3.11+, FastAPI, SQLite, Redis, Xray-core, Nginx |

---

## 📋 Требования к серверу

| Параметр | Минимальные | Рекомендуемые |
|----------|-------------|---------------|
| **ОС** | Ubuntu 20.04 / 22.04 / 24.04, Debian 11 / 12 | Ubuntu 22.04 LTS |
| **CPU** | 1 vCPU | 2 vCPU |
| **RAM** | 1 GB | 2 GB |
| **Диск** | 10 GB | 20 GB (SSD) |
| **Архитектура** | x86_64, ARM64 | x86_64 |
| **Порты** | 22 (SSH), 80 (HTTP), 443 (HTTPS) | — |
| **Интернет** | Публичный IPv4 | Статический IPv4 + домен |

---

## 🚀 Быстрая установка (одна команда)

```bash
sudo bash -c "$(curl -sSL https://raw.githubusercontent.com/holodgolod745-max/vpn-panel8/main/install.sh)"
