#!/bin/bash
# ============================================================
#   FEDUK PROXY PANEL v3.0 — Installer
#   Supports: Ubuntu 20.04/22.04/24.04, Debian 11/12
# ============================================================

set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────
#  COLORS & STYLES
# ─────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

BLACK="\033[30m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"

BG_BLACK="\033[40m"
BG_BLUE="\033[44m"
BG_MAGENTA="\033[45m"

# 256-color gradient helpers
C1="\033[38;5;27m"   # deep blue
C2="\033[38;5;33m"   # blue
C3="\033[38;5;57m"   # blue-violet
C4="\033[38;5;93m"   # violet
C5="\033[38;5;129m"  # purple
C6="\033[38;5;165m"  # magenta-purple

# ─────────────────────────────────────────────
#  GLOBALS
# ─────────────────────────────────────────────
FEDUK_VERSION="3.0.0"
INSTALL_DIR="/opt/feduk"
CONFIG_DIR="/etc/feduk"
LOG_FILE="/var/log/feduk_install.log"
CRED_FILE="/root/.feduk_credentials"
SERVICE_NAME="feduk"
XRAY_VERSION=""
PYTHON_MIN="3.11"
NODE_MIN="20"

PANEL_PORT="443"
HTTP_PORT="80"
DOMAIN=""
USE_LETSENCRYPT=false
ADMIN_USER="admin"
ADMIN_PASS=""
SERVER_IP=""
OS_NAME=""
OS_VERSION=""

SPINNER_PID=""

# ─────────────────────────────────────────────
#  LOGGING
# ─────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
log_info()    { log "INFO: $*"; }
log_warn()    { log "WARN: $*"; }
log_error()   { log "ERROR: $*"; }
log_success() { log "SUCCESS: $*"; }

# ─────────────────────────────────────────────
#  PRINT HELPERS
# ─────────────────────────────────────────────
print_ok()   { echo -e " ${GREEN}${BOLD}[✓]${RESET} $*"; }
print_err()  { echo -e " ${RED}${BOLD}[✗]${RESET} $*"; }
print_warn() { echo -e " ${YELLOW}${BOLD}[⚠]${RESET} $*"; }
print_info() { echo -e " ${BLUE}${BOLD}[ℹ]${RESET} $*"; }
print_step() { echo -e "\n${C3}${BOLD}▸ $*${RESET}"; }

die() {
    stop_spinner
    print_err "$*"
    log_error "$*"
    echo -e "\n${RED}Installation failed. Check log: ${LOG_FILE}${RESET}\n"
    exit 1
}

# ─────────────────────────────────────────────
#  SPINNER
# ─────────────────────────────────────────────
SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

start_spinner() {
    local msg="${1:-Loading...}"
    (
        local i=0
        while true; do
            printf "\r ${C4}${SPINNER_FRAMES[$i]}${RESET}  ${DIM}%s${RESET}   " "$msg"
            i=$(( (i+1) % ${#SPINNER_FRAMES[@]} ))
            sleep 0.08
        done
    ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null || true
}

stop_spinner() {
    if [[ -n "$SPINNER_PID" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    SPINNER_PID=""
    printf "\r\033[K"
}

run_with_spinner() {
    local msg="$1"; shift
    start_spinner "$msg"
    "$@" >> "$LOG_FILE" 2>&1
    local rc=$?
    stop_spinner
    if [[ $rc -eq 0 ]]; then
        print_ok "$msg"
        log_success "$msg"
    else
        print_err "$msg"
        log_error "$msg — exit code $rc"
        return $rc
    fi
}

# ─────────────────────────────────────────────
#  PROGRESS BAR
# ─────────────────────────────────────────────
TOTAL_STEPS=20
CURRENT_STEP=0

progress_bar() {
    CURRENT_STEP=$(( CURRENT_STEP + 1 ))
    local pct=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
    local filled=$(( pct * 30 / 100 ))
    local empty=$(( 30 - filled ))
    local bar=""
    for ((i=0;i<filled;i++)); do bar+="█"; done
    for ((i=0;i<empty;i++));  do bar+="░"; done
    printf "\r  ${C2}[${bar}]${RESET} ${BOLD}%3d%%${RESET}  Step %d/%d" "$pct" "$CURRENT_STEP" "$TOTAL_STEPS"
    if [[ $CURRENT_STEP -ge $TOTAL_STEPS ]]; then echo; fi
}

# ─────────────────────────────────────────────
#  ASCII ART BANNER
# ─────────────────────────────────────────────
show_banner() {
    clear
    echo
    echo -e "${C1}${BOLD}  ███████╗███████╗██████╗ ██╗   ██╗██╗  ██╗${RESET}"
    echo -e "${C2}${BOLD}  ██╔════╝██╔════╝██╔══██╗██║   ██║██║ ██╔╝${RESET}"
    echo -e "${C3}${BOLD}  █████╗  █████╗  ██║  ██║██║   ██║█████╔╝ ${RESET}"
    echo -e "${C4}${BOLD}  ██╔══╝  ██╔══╝  ██║  ██║██║   ██║██╔═██╗ ${RESET}"
    echo -e "${C5}${BOLD}  ██║     ███████╗██████╔╝╚██████╔╝██║  ██╗${RESET}"
    echo -e "${C6}${BOLD}  ╚═╝     ╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝${RESET}"
    echo
    echo -e "${C2}${BOLD}  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░${RESET}"
    echo -e "${C3}${BOLD}  ▒▒  P R O X Y   P A N E L   v 3 . 0  ▒▒${RESET}"
    echo -e "${C4}${BOLD}  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░${RESET}"
    echo
    echo -e "${C3}  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄${RESET}"
    echo -e "${C4}  █  VMess · VLESS · Trojan · Shadowsocks   █${RESET}"
    echo -e "${C5}  █  WireGuard · SOCKS5 · HTTP · Reality    █${RESET}"
    echo -e "${C3}  ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀${RESET}"
    echo
    echo -e "  ${DIM}Installer Log: ${LOG_FILE}${RESET}"
    echo -e "  ${DIM}$(date '+%A, %d %B %Y %H:%M:%S %Z')${RESET}"
    echo
}

# ─────────────────────────────────────────────
#  OS DETECTION
# ─────────────────────────────────────────────
detect_os() {
    print_step "Detecting Operating System"

    if [[ ! -f /etc/os-release ]]; then
        die "Cannot detect OS: /etc/os-release not found"
    fi

    source /etc/os-release
    OS_NAME="${ID}"
    OS_VERSION="${VERSION_ID}"

    case "$OS_NAME" in
        ubuntu)
            case "$OS_VERSION" in
                20.04|22.04|24.04)
                    print_ok "Ubuntu ${OS_VERSION} — supported"
                    ;;
                *)
                    print_warn "Ubuntu ${OS_VERSION} — not officially tested"
                    ;;
            esac
            ;;
        debian)
            case "$OS_VERSION" in
                11|12)
                    print_ok "Debian ${OS_VERSION} — supported"
                    ;;
                *)
                    print_warn "Debian ${OS_VERSION} — not officially tested"
                    ;;
            esac
            ;;
        centos|rocky|almalinux|rhel)
            print_warn "${OS_NAME} ${OS_VERSION} — experimental support"
            ;;
        *)
            die "Unsupported OS: ${OS_NAME}. Use Ubuntu 20.04/22.04/24.04 or Debian 11/12"
            ;;
    esac

    log_info "OS: ${OS_NAME} ${OS_VERSION}"
    progress_bar
}

# ─────────────────────────────────────────────
#  ROOT CHECK
# ─────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Use: sudo bash install.sh"
    fi
    print_ok "Running as root"
    log_info "UID: $EUID"
    progress_bar
}

# ─────────────────────────────────────────────
#  ARCH CHECK
# ─────────────────────────────────────────────
check_arch() {
    print_step "Checking system architecture"
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)   ARCH="64"  ; XRAY_ARCH="64"   ;;
        aarch64|arm64)  ARCH="arm64"; XRAY_ARCH="arm64-v8a" ;;
        armv7*)         ARCH="arm32"; XRAY_ARCH="arm32-v7a" ;;
        *)              die "Unsupported CPU architecture: $arch" ;;
    esac
    print_ok "Architecture: ${arch} → Xray: ${XRAY_ARCH}"
    log_info "ARCH: $arch"
    progress_bar
}

# ─────────────────────────────────────────────
#  NETWORK DETECTION
# ─────────────────────────────────────────────
detect_network() {
    print_step "Detecting network configuration"

    SERVER_IP=$(curl -s4 --max-time 10 https://api.ipify.org 2>/dev/null \
        || curl -s4 --max-time 10 https://ifconfig.me 2>/dev/null \
        || hostname -I | awk '{print $1}')

    if [[ -z "$SERVER_IP" ]]; then
        die "Failed to detect server IP address"
    fi

    print_ok "Server IP: ${SERVER_IP}"
    log_info "Server IP: $SERVER_IP"
    progress_bar
}

# ─────────────────────────────────────────────
#  INTERACTIVE SETUP
# ─────────────────────────────────────────────
interactive_setup() {
    # Temporarily disable strict mode — read returns non-zero on empty Enter
    # which kills the script under set -e
    set +euo pipefail
    local OLD_IFS="$IFS"
    IFS=$' \t\n'

    print_step "Interactive Configuration"
    echo

    # Domain or IP
    echo -e "  ${C3}${BOLD}Domain name${RESET} ${DIM}(leave empty to use IP: ${SERVER_IP})${RESET}"
    read -r -p "  → Domain: " DOMAIN </dev/tty
    DOMAIN="${DOMAIN:-}"

    # If user typed an IP address instead of a domain — treat as empty (use IP mode)
    if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_warn "IP address entered — Let's Encrypt requires a real domain. Using self-signed SSL."
        DOMAIN=""
    fi

    if [[ -n "$DOMAIN" ]]; then
        echo -e "\n  ${C3}${BOLD}Enable Let's Encrypt SSL?${RESET} ${DIM}(requires domain pointed to this server)${RESET}"
        read -r -p "  → Use Let's Encrypt? [Y/n]: " LE_CHOICE </dev/tty
        LE_CHOICE="${LE_CHOICE:-y}"
        [[ "${LE_CHOICE,,}" != "n" ]] && USE_LETSENCRYPT=true
    fi

    echo -e "\n  ${C3}${BOLD}Panel port${RESET} ${DIM}(default: 443)${RESET}"
    read -r -p "  → HTTPS port [443]: " PANEL_PORT </dev/tty
    PANEL_PORT="${PANEL_PORT:-443}"

    # Telegram bot
    echo -e "\n  ${C3}${BOLD}Telegram Bot Token${RESET} ${DIM}(optional, press Enter to skip)${RESET}"
    read -r -p "  → Bot token: " TG_BOT_TOKEN </dev/tty
    TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"

    echo -e "\n  ${C3}${BOLD}Telegram Admin Chat ID${RESET} ${DIM}(optional)${RESET}"
    read -r -p "  → Chat ID: " TG_ADMIN_ID </dev/tty
    TG_ADMIN_ID="${TG_ADMIN_ID:-}"

    # Generate secure admin password
    ADMIN_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)

    echo
    print_info "Configuration summary:"
    echo -e "    ${DIM}Domain/IP   :${RESET} ${DOMAIN:-$SERVER_IP}"
    echo -e "    ${DIM}SSL         :${RESET} ${USE_LETSENCRYPT}"
    echo -e "    ${DIM}Panel port  :${RESET} ${PANEL_PORT}"
    echo -e "    ${DIM}Admin user  :${RESET} ${ADMIN_USER}"
    echo -e "    ${DIM}Admin pass  :${RESET} ${ADMIN_PASS}"
    echo
    read -r -p "  Proceed with installation? [Y/n]: " CONFIRM </dev/tty
    CONFIRM="${CONFIRM:-y}"
    [[ "${CONFIRM,,}" == "n" ]] && { echo "Aborted."; exit 0; }

    # Restore strict mode
    IFS="$OLD_IFS"
    set -euo pipefail

    progress_bar
}

# ─────────────────────────────────────────────
#  PACKAGE MANAGER HELPERS
# ─────────────────────────────────────────────
pkg_update() {
    print_step "Updating package lists"
    case "$OS_NAME" in
        ubuntu|debian)
            run_with_spinner "Updating APT cache" apt-get update -qq
            ;;
        centos|rocky|almalinux|rhel)
            run_with_spinner "Updating DNF cache" dnf makecache -q
            ;;
    esac
    progress_bar
}

pkg_install() {
    local packages=("$@")
    case "$OS_NAME" in
        ubuntu|debian)
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}"
            ;;
        centos|rocky|almalinux|rhel)
            dnf install -y -q "${packages[@]}"
            ;;
    esac
}

# ─────────────────────────────────────────────
#  BASE DEPENDENCIES
# ─────────────────────────────────────────────
install_base_deps() {
    print_step "Installing base dependencies"

    local base_pkgs=(
        curl wget git unzip tar gzip jq
        net-tools iproute2 iptables
        ca-certificates gnupg lsb-release
        openssl uuid-runtime cron logrotate
        socat
    )

    run_with_spinner "Installing base packages" pkg_install "${base_pkgs[@]}"
    progress_bar
}

# ─────────────────────────────────────────────
#  UFW FIREWALL
# ─────────────────────────────────────────────
configure_firewall() {
    print_step "Configuring UFW firewall"

    if ! command -v ufw &>/dev/null; then
        run_with_spinner "Installing UFW" pkg_install ufw
    fi

    ufw --force reset >> "$LOG_FILE" 2>&1 || true
    ufw default deny incoming  >> "$LOG_FILE" 2>&1
    ufw default allow outgoing >> "$LOG_FILE" 2>&1
    ufw allow ssh              >> "$LOG_FILE" 2>&1
    ufw allow 22/tcp           >> "$LOG_FILE" 2>&1
    ufw allow "${HTTP_PORT}/tcp"   >> "$LOG_FILE" 2>&1
    ufw allow "${PANEL_PORT}/tcp"  >> "$LOG_FILE" 2>&1
    ufw --force enable         >> "$LOG_FILE" 2>&1

    print_ok "Firewall configured (ports 22, ${HTTP_PORT}, ${PANEL_PORT})"
    log_info "UFW enabled"
    progress_bar
}

# ─────────────────────────────────────────────
#  PYTHON 3.11+
# ─────────────────────────────────────────────
install_python() {
    print_step "Installing Python 3.11+"

    local py_ver
    py_ver=$(python3 --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1) || py_ver=""
    local py_major py_minor
    py_major=$(echo "$py_ver" | cut -d. -f1)
    py_minor=$(echo "$py_ver"  | cut -d. -f2)

    if [[ -n "$py_ver" ]] && \
       [[ "$py_major" -eq 3 ]] && \
       [[ "$py_minor" -ge 11 ]]; then
        print_ok "Python ${py_ver} already installed"
        log_info "Python $py_ver (existing)"
        progress_bar
        return 0
    fi

    case "$OS_NAME" in
        ubuntu)
            run_with_spinner "Adding deadsnakes PPA" \
                bash -c "add-apt-repository -y ppa:deadsnakes/ppa && apt-get update -qq"
            run_with_spinner "Installing Python 3.11" \
                pkg_install python3.11 python3.11-venv python3.11-dev python3-pip
            update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 >> "$LOG_FILE" 2>&1
            ;;
        debian)
            run_with_spinner "Installing Python 3.11 build deps" \
                pkg_install build-essential libssl-dev libffi-dev zlib1g-dev \
                libsqlite3-dev libbz2-dev libreadline-dev libncurses5-dev
            run_with_spinner "Downloading Python 3.11 source" \
                bash -c "cd /tmp && wget -q https://www.python.org/ftp/python/3.11.9/Python-3.11.9.tgz && tar xf Python-3.11.9.tgz"
            run_with_spinner "Compiling Python 3.11" \
                bash -c "cd /tmp/Python-3.11.9 && ./configure --enable-optimizations --quiet && make -j\$(nproc) && make altinstall"
            ln -sf /usr/local/bin/python3.11 /usr/bin/python3 2>/dev/null || true
            ;;
    esac

    run_with_spinner "Upgrading pip" \
        bash -c "python3 -m pip install --quiet --upgrade pip setuptools wheel"

    print_ok "Python $(python3 --version)"
    progress_bar
}

# ─────────────────────────────────────────────
#  NODE.JS 20+
# ─────────────────────────────────────────────
install_nodejs() {
    print_step "Installing Node.js 20+"

    local node_ver
    node_ver=$(node --version 2>/dev/null | grep -oP '\d+' | head -1) || node_ver=0

    if [[ "$node_ver" -ge 20 ]]; then
        print_ok "Node.js v$(node --version) already installed"
        log_info "Node.js v$node_ver (existing)"
        progress_bar
        return 0
    fi

    run_with_spinner "Adding NodeSource repository" \
        bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"
    run_with_spinner "Installing Node.js 20" \
        pkg_install nodejs

    print_ok "Node.js $(node --version) | npm $(npm --version)"
    log_info "Node.js installed"
    progress_bar
}

# ─────────────────────────────────────────────
#  XRAY-CORE
# ─────────────────────────────────────────────
install_xray() {
    print_step "Installing Xray-core"

    # Get latest version
    XRAY_VERSION=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" \
        | jq -r '.tag_name' 2>/dev/null) || XRAY_VERSION="v1.8.23"
    XRAY_VERSION="${XRAY_VERSION:-v1.8.23}"

    print_info "Xray version: ${XRAY_VERSION}"
    log_info "Xray version: $XRAY_VERSION"

    local xray_url="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"
    local tmpdir
    tmpdir=$(mktemp -d)

    run_with_spinner "Downloading Xray-core ${XRAY_VERSION}" \
        bash -c "curl -sSL '${xray_url}' -o '${tmpdir}/xray.zip'"

    run_with_spinner "Extracting Xray-core" \
        bash -c "unzip -qo '${tmpdir}/xray.zip' -d '${tmpdir}/xray'"

    mkdir -p "${INSTALL_DIR}/xray/bin"
    cp "${tmpdir}/xray/xray" "${INSTALL_DIR}/xray/bin/"
    chmod +x "${INSTALL_DIR}/xray/bin/xray"

    # Download geodata
    run_with_spinner "Downloading GeoIP database" \
        bash -c "curl -sSL 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat' \
            -o '${INSTALL_DIR}/xray/geoip.dat'"

    run_with_spinner "Downloading GeoSite database" \
        bash -c "curl -sSL 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat' \
            -o '${INSTALL_DIR}/xray/geosite.dat'"

    rm -rf "$tmpdir"

    print_ok "Xray-core ${XRAY_VERSION} installed → ${INSTALL_DIR}/xray/bin/xray"
    log_info "Xray installed: ${XRAY_VERSION}"
    progress_bar
}

# ─────────────────────────────────────────────
#  REDIS
# ─────────────────────────────────────────────
install_redis() {
    print_step "Installing Redis"

    run_with_spinner "Installing Redis server" pkg_install redis-server

    sed -i 's/^# maxmemory .*/maxmemory 256mb/'          /etc/redis/redis.conf 2>/dev/null || true
    sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf 2>/dev/null || true
    sed -i 's/^bind .*/bind 127.0.0.1/'                  /etc/redis/redis.conf 2>/dev/null || true

    systemctl enable redis-server >> "$LOG_FILE" 2>&1
    systemctl restart redis-server >> "$LOG_FILE" 2>&1

    print_ok "Redis running on 127.0.0.1:6379"
    log_info "Redis installed and started"
    progress_bar
}

# ─────────────────────────────────────────────
#  NGINX
# ─────────────────────────────────────────────
install_nginx() {
    print_step "Installing Nginx"

    run_with_spinner "Installing Nginx" pkg_install nginx

    print_ok "Nginx installed"
    log_info "Nginx installed"
    progress_bar
}

# ─────────────────────────────────────────────
#  SSL CERTIFICATES
# ─────────────────────────────────────────────
setup_ssl() {
    print_step "Setting up SSL certificates"

    mkdir -p "${INSTALL_DIR}/certs"

    # Safety guard: Let's Encrypt only works with real domain names, not IPs
    if [[ "$USE_LETSENCRYPT" == true ]] && [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_warn "Domain looks like an IP — switching to self-signed certificate"
        USE_LETSENCRYPT=false
        DOMAIN=""
    fi

    if [[ "$USE_LETSENCRYPT" == true ]] && [[ -n "$DOMAIN" ]]; then
        run_with_spinner "Installing Certbot" \
            bash -c "pkg_install certbot python3-certbot-nginx"

        # Stop nginx temporarily so certbot --standalone can bind port 80
        systemctl stop nginx >> "$LOG_FILE" 2>&1 || true

        if run_with_spinner "Obtaining Let's Encrypt certificate for ${DOMAIN}" \
            bash -c "certbot certonly --standalone --non-interactive --agree-tos \
                --email admin@${DOMAIN} -d ${DOMAIN} >> '$LOG_FILE' 2>&1"; then

            ln -sf "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" "${INSTALL_DIR}/certs/cert.pem"
            ln -sf "/etc/letsencrypt/live/${DOMAIN}/privkey.pem"   "${INSTALL_DIR}/certs/key.pem"

            # Auto-renew
            (crontab -l 2>/dev/null; echo "0 2 * * * systemctl stop nginx; certbot renew --quiet; systemctl start nginx") \
                | crontab - 2>/dev/null || true

            print_ok "Let's Encrypt certificate obtained for ${DOMAIN}"
            log_info "Let's Encrypt: $DOMAIN"
        else
            print_warn "Let's Encrypt failed — falling back to self-signed certificate"
            log_warn "certbot failed, using self-signed"
            USE_LETSENCRYPT=false
            local common_name="${DOMAIN:-$SERVER_IP}"
            openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
                -keyout "${INSTALL_DIR}/certs/key.pem" \
                -out "${INSTALL_DIR}/certs/cert.pem" \
                -subj "/CN=${common_name}/O=FEDUK/OU=Proxy/C=RU" \
                -addext "subjectAltName=IP:${SERVER_IP}" >> "$LOG_FILE" 2>&1
            print_ok "Self-signed certificate generated (10 years, fallback)"
        fi

        systemctl start nginx >> "$LOG_FILE" 2>&1 || true
    else
        # Self-signed
        local common_name="${DOMAIN:-$SERVER_IP}"
        run_with_spinner "Generating self-signed certificate" \
            bash -c "openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
                -keyout '${INSTALL_DIR}/certs/key.pem' \
                -out '${INSTALL_DIR}/certs/cert.pem' \
                -subj '/CN=${common_name}/O=FEDUK/OU=Proxy/C=RU' \
                -addext 'subjectAltName=IP:${SERVER_IP}' 2>/dev/null"

        print_ok "Self-signed certificate generated (10 years)"
        log_info "Self-signed cert: ${common_name}"
    fi
    progress_bar
}

# ─────────────────────────────────────────────
#  DIRECTORY STRUCTURE
# ─────────────────────────────────────────────
create_directories() {
    print_step "Creating directory structure"

    mkdir -p \
        "${INSTALL_DIR}/panel" \
        "${INSTALL_DIR}/xray/configs" \
        "${INSTALL_DIR}/data" \
        "${INSTALL_DIR}/backups" \
        "${INSTALL_DIR}/logs" \
        "${INSTALL_DIR}/certs" \
        "${CONFIG_DIR}"

    touch "${INSTALL_DIR}/logs/access.log"
    touch "${INSTALL_DIR}/logs/error.log"

    print_ok "Directory structure created under ${INSTALL_DIR}"
    log_info "Directories created"
    progress_bar
}

# ─────────────────────────────────────────────
#  XRAY CONFIG
# ─────────────────────────────────────────────
create_xray_config() {
    print_step "Creating Xray base configuration"

    cat > "${INSTALL_DIR}/xray/configs/config.json" <<'XRAYEOF'
{
  "log": {
    "access": "/opt/feduk/logs/xray-access.log",
    "error":  "/opt/feduk/logs/xray-error.log",
    "loglevel": "warning"
  },
  "api": {
    "tag": "api",
    "services": ["HandlerService","LoggerService","StatsService"]
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": { "statsUserUplink": true, "statsUserDownlink": true }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "inbounds": [
    {
      "tag": "api-inbound",
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": { "domainStrategy": "UseIPv4" }
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api-inbound"],
        "outboundTag": "api"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads-all"],
        "outboundTag": "blocked"
      }
    ]
  }
}
XRAYEOF

    print_ok "Xray config written to ${INSTALL_DIR}/xray/configs/config.json"
    log_info "Xray base config created"
    progress_bar
}

# ─────────────────────────────────────────────
#  PYTHON VENV & FASTAPI BACKEND
# ─────────────────────────────────────────────
setup_python_backend() {
    print_step "Setting up FastAPI backend"

    # Virtual environment
    run_with_spinner "Creating Python virtual environment" \
        bash -c "python3 -m venv ${INSTALL_DIR}/panel/venv"

    local pip="${INSTALL_DIR}/panel/venv/bin/pip"

    run_with_spinner "Installing FastAPI and dependencies" \
        bash -c "${pip} install --quiet \
            fastapi==0.111.0 \
            uvicorn[standard]==0.29.0 \
            sqlalchemy==2.0.30 \
            alembic==1.13.1 \
            pydantic==2.7.1 \
            pydantic-settings==2.2.1 \
            python-jose[cryptography]==3.3.0 \
            passlib[bcrypt]==1.7.4 \
            python-multipart==0.0.9 \
            redis==5.0.4 \
            aioredis==2.0.1 \
            httpx==0.27.0 \
            websockets==12.0 \
            grpcio==1.63.0 \
            grpcio-tools==1.63.0 \
            python-telegram-bot==21.2 \
            qrcode==7.4.2 \
            psutil==5.9.8 \
            geoip2==4.8.0 \
            PyYAML==6.0.1 \
            APScheduler==3.10.4 \
            loguru==0.7.2"

    # ── Main FastAPI application ──────────────────
    cat > "${INSTALL_DIR}/panel/main.py" <<'PYEOF'
"""
FEDUK Proxy Panel v3.0 — FastAPI Backend
"""
import asyncio, json, os, secrets, subprocess, uuid
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, List

from fastapi import (
    FastAPI, Depends, HTTPException, WebSocket,
    WebSocketDisconnect, status, Request, BackgroundTasks
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel, Field
from sqlalchemy import (
    create_engine, Column, String, Integer, BigInteger,
    Boolean, DateTime, Text, ForeignKey, func
)
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session, relationship
import redis as redis_lib
import psutil
import yaml
from loguru import logger

# ── Settings ──────────────────────────────────
BASE_DIR   = Path("/opt/feduk")
DATA_DIR   = BASE_DIR / "data"
LOG_DIR    = BASE_DIR / "logs"
CERT_DIR   = BASE_DIR / "certs"
XRAY_BIN   = BASE_DIR / "xray" / "bin" / "xray"
XRAY_CFG   = BASE_DIR / "xray" / "configs" / "config.json"
BACKUP_DIR = BASE_DIR / "backups"
CFG_FILE   = Path("/etc/feduk/config.yml")

DATA_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)
BACKUP_DIR.mkdir(parents=True, exist_ok=True)

# Load YAML config
def load_config() -> dict:
    if CFG_FILE.exists():
        with open(CFG_FILE) as f:
            return yaml.safe_load(f) or {}
    return {}

cfg = load_config()
SECRET_KEY    = cfg.get("secret_key", secrets.token_hex(32))
ALGORITHM     = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30
TG_BOT_TOKEN  = cfg.get("telegram_bot_token", "")
TG_ADMIN_ID   = cfg.get("telegram_admin_id",  "")
ADMIN_USER    = cfg.get("admin_user", "admin")
ADMIN_PASS    = cfg.get("admin_password_hash", "")

# ── Database ───────────────────────────────────
DB_PATH = DATA_DIR / "config.db"
engine  = create_engine(f"sqlite:///{DB_PATH}", connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class Inbound(Base):
    __tablename__ = "inbounds"
    id          = Column(Integer, primary_key=True, index=True)
    tag         = Column(String(64), unique=True, nullable=False)
    remark      = Column(String(128))
    protocol    = Column(String(32))
    port        = Column(Integer)
    listen      = Column(String(64), default="0.0.0.0")
    settings    = Column(Text, default="{}")
    stream      = Column(Text, default="{}")
    sniffing    = Column(Text, default="{}")
    enabled     = Column(Boolean, default=True)
    created_at  = Column(DateTime, default=datetime.utcnow)
    clients     = relationship("Client", back_populates="inbound", cascade="all,delete")

class Client(Base):
    __tablename__ = "clients"
    id           = Column(Integer, primary_key=True, index=True)
    inbound_id   = Column(Integer, ForeignKey("inbounds.id"))
    email        = Column(String(128), unique=True, nullable=False)
    uuid         = Column(String(36), default=lambda: str(uuid.uuid4()))
    password     = Column(String(64), default="")
    flow         = Column(String(32), default="")
    enabled      = Column(Boolean, default=True)
    traffic_up   = Column(BigInteger, default=0)
    traffic_down = Column(BigInteger, default=0)
    traffic_limit= Column(BigInteger, default=0)
    ip_limit     = Column(Integer, default=0)
    expire_date  = Column(DateTime, nullable=True)
    created_at   = Column(DateTime, default=datetime.utcnow)
    inbound      = relationship("Inbound", back_populates="clients")

class User(Base):
    __tablename__ = "admin_users"
    id            = Column(Integer, primary_key=True)
    username      = Column(String(64), unique=True)
    password_hash = Column(String(128))
    is_active     = Column(Boolean, default=True)
    created_at    = Column(DateTime, default=datetime.utcnow)

Base.metadata.create_all(bind=engine)

# ── Auth helpers ──────────────────────────────
pwd_ctx   = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2    = OAuth2PasswordBearer(tokenUrl="/api/auth/token")

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_ctx.verify(plain, hashed)

def get_password_hash(password: str) -> str:
    return pwd_ctx.hash(password)

def create_access_token(data: dict, expires_delta: timedelta = None) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def get_current_user(token: str = Depends(oauth2), db: Session = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    user = db.query(User).filter(User.username == username).first()
    if user is None:
        raise credentials_exception
    return user

# ── Pydantic schemas ──────────────────────────
class Token(BaseModel):
    access_token: str
    token_type: str

class InboundCreate(BaseModel):
    remark:   str
    protocol: str
    port:     int = Field(..., ge=1, le=65535)
    listen:   str = "0.0.0.0"
    settings: dict = {}
    stream:   dict = {}

class InboundOut(BaseModel):
    id: int; tag: str; remark: str; protocol: str
    port: int; enabled: bool; created_at: datetime
    class Config: from_attributes = True

class ClientCreate(BaseModel):
    email:         str
    inbound_id:    int
    traffic_limit: int = 0
    ip_limit:      int = 0
    expire_date:   Optional[datetime] = None
    flow:          str = ""

class ClientOut(BaseModel):
    id: int; email: str; uuid: str; enabled: bool
    traffic_up: int; traffic_down: int; traffic_limit: int
    expire_date: Optional[datetime]; created_at: datetime
    class Config: from_attributes = True

# ── Redis ─────────────────────────────────────
try:
    r = redis_lib.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
    r.ping()
    REDIS_OK = True
except Exception:
    REDIS_OK = False
    r = None

# ── Xray control ─────────────────────────────
class XrayManager:
    @staticmethod
    def reload_config():
        try:
            subprocess.run(
                ["systemctl", "restart", "xray-feduk"],
                capture_output=True, timeout=10
            )
        except Exception as e:
            logger.error(f"Xray reload failed: {e}")

    @staticmethod
    def get_stats() -> dict:
        try:
            result = subprocess.run(
                [str(XRAY_BIN), "api", "stats", "-s", "127.0.0.1:10085"],
                capture_output=True, text=True, timeout=5
            )
            return json.loads(result.stdout) if result.returncode == 0 else {}
        except Exception:
            return {}

    @staticmethod
    def build_full_config(db: Session) -> dict:
        inbounds_db = db.query(Inbound).filter(Inbound.enabled == True).all()
        with open(XRAY_CFG) as f:
            cfg_data = json.load(f)

        inbounds_list = []
        for inb in inbounds_db:
            settings = json.loads(inb.settings)
            clients_db = db.query(Client).filter(
                Client.inbound_id == inb.id, Client.enabled == True
            ).all()

            if inb.protocol in ("vmess", "vless", "trojan"):
                cl_list = []
                for c in clients_db:
                    entry = {"id": c.uuid, "email": c.email}
                    if inb.protocol == "vmess":
                        entry["alterId"] = 0
                    if inb.protocol == "vless" and c.flow:
                        entry["flow"] = c.flow
                    if inb.protocol == "trojan":
                        entry = {"password": c.password or c.uuid, "email": c.email}
                    cl_list.append(entry)
                settings["clients"] = cl_list
            elif inb.protocol == "shadowsocks":
                pass

            inbounds_list.append({
                "tag":      inb.tag,
                "listen":   inb.listen,
                "port":     inb.port,
                "protocol": inb.protocol,
                "settings": settings,
                "streamSettings": json.loads(inb.stream),
                "sniffing":       json.loads(inb.sniffing),
            })

        cfg_data["inbounds"] = inbounds_list + [cfg_data["inbounds"][0]]
        return cfg_data

xray_mgr = XrayManager()

# ── FastAPI app ───────────────────────────────
app = FastAPI(
    title="FEDUK Proxy Panel",
    description="FEDUK Proxy Panel API v3.0",
    version="3.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc"
)

app.add_middleware(CORSMiddleware,
    allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"])
app.add_middleware(GZipMiddleware, minimum_size=1000)

# ── Auth routes ───────────────────────────────
@app.post("/api/auth/token", response_model=Token, tags=["Auth"])
async def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == form.username).first()
    if not user or not verify_password(form.password, user.password_hash):
        raise HTTPException(status_code=400, detail="Incorrect username or password")
    token = create_access_token({"sub": user.username})
    return {"access_token": token, "token_type": "bearer"}

# ── Dashboard ─────────────────────────────────
@app.get("/api/dashboard", tags=["Dashboard"])
async def dashboard(db: Session = Depends(get_db), _=Depends(get_current_user)):
    cpu    = psutil.cpu_percent(interval=0.5)
    mem    = psutil.virtual_memory()
    disk   = psutil.disk_usage("/")
    net_io = psutil.net_io_counters()
    up_time = (datetime.utcnow() - datetime.utcfromtimestamp(psutil.boot_time())).total_seconds()

    inbounds_total = db.query(func.count(Inbound.id)).scalar()
    clients_total  = db.query(func.count(Client.id)).scalar()
    clients_active = db.query(func.count(Client.id)).filter(Client.enabled == True).scalar()
    traffic_up     = db.query(func.sum(Client.traffic_up)).scalar()   or 0
    traffic_down   = db.query(func.sum(Client.traffic_down)).scalar() or 0

    return {
        "system": {
            "cpu_percent":   cpu,
            "mem_total":     mem.total,
            "mem_used":      mem.used,
            "mem_percent":   mem.percent,
            "disk_total":    disk.total,
            "disk_used":     disk.used,
            "disk_percent":  disk.percent,
            "net_sent":      net_io.bytes_sent,
            "net_recv":      net_io.bytes_recv,
            "uptime_seconds": up_time,
        },
        "proxy": {
            "inbounds_total": inbounds_total,
            "clients_total":  clients_total,
            "clients_active": clients_active,
            "traffic_up_gb":  round(traffic_up   / 1024**3, 3),
            "traffic_down_gb":round(traffic_down / 1024**3, 3),
        }
    }

# ── Inbounds CRUD ─────────────────────────────
@app.get("/api/inbounds", tags=["Inbounds"])
async def list_inbounds(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return db.query(Inbound).all()

@app.post("/api/inbounds", tags=["Inbounds"])
async def create_inbound(data: InboundCreate, bg: BackgroundTasks,
                         db: Session = Depends(get_db), _=Depends(get_current_user)):
    # Check port not in use
    existing = db.query(Inbound).filter(Inbound.port == data.port).first()
    if existing:
        raise HTTPException(status_code=400, detail=f"Port {data.port} already in use")
    tag = f"inbound-{data.protocol}-{data.port}"
    inb = Inbound(
        tag=tag, remark=data.remark, protocol=data.protocol,
        port=data.port, listen=data.listen,
        settings=json.dumps(data.settings),
        stream=json.dumps(data.stream)
    )
    db.add(inb); db.commit(); db.refresh(inb)
    bg.add_task(xray_mgr.reload_config)
    return inb

@app.delete("/api/inbounds/{inbound_id}", tags=["Inbounds"])
async def delete_inbound(inbound_id: int, bg: BackgroundTasks,
                         db: Session = Depends(get_db), _=Depends(get_current_user)):
    inb = db.query(Inbound).filter(Inbound.id == inbound_id).first()
    if not inb:
        raise HTTPException(status_code=404, detail="Inbound not found")
    db.delete(inb); db.commit()
    bg.add_task(xray_mgr.reload_config)
    return {"message": "Deleted"}

# ── Clients CRUD ──────────────────────────────
@app.get("/api/clients", tags=["Clients"])
async def list_clients(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return db.query(Client).all()

@app.post("/api/clients", tags=["Clients"])
async def create_client(data: ClientCreate, db: Session = Depends(get_db),
                        _=Depends(get_current_user)):
    existing = db.query(Client).filter(Client.email == data.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already exists")
    client = Client(
        email=data.email, inbound_id=data.inbound_id,
        traffic_limit=data.traffic_limit, ip_limit=data.ip_limit,
        expire_date=data.expire_date, flow=data.flow
    )
    db.add(client); db.commit(); db.refresh(client)
    return client

@app.delete("/api/clients/{client_id}", tags=["Clients"])
async def delete_client(client_id: int, db: Session = Depends(get_db),
                        _=Depends(get_current_user)):
    c = db.query(Client).filter(Client.id == client_id).first()
    if not c:
        raise HTTPException(status_code=404, detail="Client not found")
    db.delete(c); db.commit()
    return {"message": "Deleted"}

# ── Subscriptions ─────────────────────────────
@app.get("/sub/{client_uuid}", tags=["Subscriptions"])
async def subscription(client_uuid: str, fmt: str = "v2ray",
                       db: Session = Depends(get_db)):
    import base64
    client = db.query(Client).filter(Client.uuid == client_uuid, Client.enabled == True).first()
    if not client:
        raise HTTPException(status_code=404, detail="Client not found")

    inbound = client.inbound
    if not inbound:
        raise HTTPException(status_code=404, detail="Inbound not found")

    links = []
    server_ip_or_domain = os.environ.get("SERVER_HOST", "127.0.0.1")

    if inbound.protocol == "vmess":
        vmess_obj = {
            "v": "2", "ps": client.email, "add": server_ip_or_domain,
            "port": str(inbound.port), "id": client.uuid,
            "aid": "0", "net": "tcp", "type": "none",
            "tls": "tls", "sni": server_ip_or_domain
        }
        stream = json.loads(inbound.stream)
        vmess_obj["net"] = stream.get("network", "tcp")
        b64 = base64.b64encode(json.dumps(vmess_obj).encode()).decode()
        links.append(f"vmess://{b64}")

    elif inbound.protocol == "vless":
        flow = f"?flow={client.flow}" if client.flow else ""
        links.append(
            f"vless://{client.uuid}@{server_ip_or_domain}:{inbound.port}"
            f"?encryption=none&type=tcp&security=reality{flow}#{client.email}"
        )

    elif inbound.protocol == "trojan":
        links.append(
            f"trojan://{client.password or client.uuid}@{server_ip_or_domain}:{inbound.port}"
            f"?sni={server_ip_or_domain}#{client.email}"
        )

    elif inbound.protocol == "shadowsocks":
        settings = json.loads(inbound.settings)
        method   = settings.get("method", "chacha20-ietf-poly1305")
        password = settings.get("password", "feduk")
        cred = base64.b64encode(f"{method}:{password}".encode()).decode()
        links.append(f"ss://{cred}@{server_ip_or_domain}:{inbound.port}#{client.email}")

    if fmt == "clash":
        clash_proxies = [{"name": client.email, "type": "vmess",
                          "server": server_ip_or_domain, "port": inbound.port,
                          "uuid": client.uuid, "alterId": 0, "cipher": "auto"}]
        clash_cfg = {
            "mixed-port": 7890, "allow-lan": True, "mode": "rule",
            "proxies": clash_proxies,
            "proxy-groups": [{"name": "FEDUK", "type": "select",
                               "proxies": [client.email]}],
            "rules": ["MATCH,FEDUK"]
        }
        import yaml
        return HTMLResponse(yaml.dump(clash_cfg), media_type="text/plain")

    combined = "\n".join(links)
    b64_all  = base64.b64encode(combined.encode()).decode()
    return HTMLResponse(b64_all, media_type="text/plain")

# ── Backup ────────────────────────────────────
@app.post("/api/backup", tags=["Backup"])
async def create_backup(_=Depends(get_current_user)):
    import tarfile, time
    ts   = int(time.time())
    path = BACKUP_DIR / f"feduk_backup_{ts}.tar.gz"
    with tarfile.open(path, "w:gz") as tar:
        tar.add(str(DATA_DIR),   arcname="data")
        tar.add("/etc/feduk",    arcname="config")
        tar.add(str(XRAY_CFG),   arcname="xray_config.json")
    return {"backup_file": str(path), "size_mb": round(path.stat().st_size / 1024**2, 2)}

# ── Logs ──────────────────────────────────────
@app.get("/api/logs", tags=["Logs"])
async def get_logs(lines: int = 100, log_type: str = "access",
                   _=Depends(get_current_user)):
    log_map = {"access": LOG_DIR / "xray-access.log",
               "error":  LOG_DIR / "xray-error.log",
               "panel":  LOG_DIR / "panel.log"}
    lf = log_map.get(log_type, LOG_DIR / "xray-access.log")
    if not lf.exists():
        return {"lines": []}
    result = subprocess.run(["tail", f"-{lines}", str(lf)],
                            capture_output=True, text=True)
    return {"lines": result.stdout.splitlines()}

# ── WebSocket stats ───────────────────────────
class WSManager:
    def __init__(self):
        self.active: List[WebSocket] = []
    async def connect(self, ws: WebSocket):
        await ws.accept()
        self.active.append(ws)
    def disconnect(self, ws: WebSocket):
        self.active.remove(ws)
    async def broadcast(self, data: dict):
        for ws in list(self.active):
            try:
                await ws.send_json(data)
            except Exception:
                self.active.remove(ws)

ws_manager = WSManager()

@app.websocket("/ws/stats")
async def ws_stats(websocket: WebSocket):
    await ws_manager.connect(websocket)
    try:
        while True:
            cpu   = psutil.cpu_percent(interval=1)
            mem   = psutil.virtual_memory().percent
            net   = psutil.net_io_counters()
            await websocket.send_json({
                "ts": datetime.utcnow().isoformat(),
                "cpu": cpu, "mem": mem,
                "net_sent": net.bytes_sent,
                "net_recv": net.bytes_recv
            })
            await asyncio.sleep(2)
    except WebSocketDisconnect:
        ws_manager.disconnect(websocket)

# ── Static / SPA ──────────────────────────────
static_dir = Path("/opt/feduk/panel/static")
static_dir.mkdir(parents=True, exist_ok=True)

app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

@app.get("/{full_path:path}", include_in_schema=False)
async def serve_spa(full_path: str, request: Request):
    index = static_dir / "index.html"
    if index.exists():
        return HTMLResponse(index.read_text())
    return HTMLResponse("<h1>FEDUK Panel</h1><p>Frontend loading...</p>")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="127.0.0.1", port=8000,
                reload=False, workers=2,
                log_config=None)
PYEOF

    print_ok "FastAPI backend created"
    log_info "Backend Python files written"
    progress_bar
}

# ─────────────────────────────────────────────
#  FRONTEND (HTML/CSS/JS)
# ─────────────────────────────────────────────
create_frontend() {
    print_step "Creating frontend (HTML/CSS/JS)"

    local STATIC="${INSTALL_DIR}/panel/static"
    mkdir -p "$STATIC"

    cat > "${STATIC}/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="ru" data-theme="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>FEDUK Proxy Panel v3.0</title>
<style>
:root {
  --bg-primary:   #0a0b0e;
  --bg-secondary: #111318;
  --bg-card:      #161a22;
  --bg-hover:     #1e2330;
  --accent-1:     #3b6ef8;
  --accent-2:     #7c3aed;
  --accent-3:     #06b6d4;
  --success:      #10b981;
  --warning:      #f59e0b;
  --danger:       #ef4444;
  --text-primary: #e2e8f0;
  --text-muted:   #64748b;
  --border:       #1e2b3d;
  --gradient:     linear-gradient(135deg, #3b6ef8, #7c3aed);
  --shadow:       0 8px 32px rgba(0,0,0,0.5);
  --radius:       12px;
  --radius-sm:    8px;
  --font-mono:    'JetBrains Mono', 'Fira Code', monospace;
}
[data-theme="light"] {
  --bg-primary:   #f0f4ff;
  --bg-secondary: #ffffff;
  --bg-card:      #ffffff;
  --bg-hover:     #e8edf8;
  --text-primary: #1a1f36;
  --text-muted:   #6b7280;
  --border:       #d1daea;
}
* { margin:0; padding:0; box-sizing:border-box; }
html, body { height:100%; font-family: 'Inter', system-ui, sans-serif;
             background: var(--bg-primary); color: var(--text-primary);
             font-size: 14px; line-height: 1.6; }
::-webkit-scrollbar { width: 6px; }
::-webkit-scrollbar-track { background: var(--bg-secondary); }
::-webkit-scrollbar-thumb { background: var(--accent-1); border-radius: 3px; }

/* ── Layout ── */
.layout   { display: flex; height: 100vh; overflow: hidden; }
.sidebar  { width: 240px; min-width: 240px; background: var(--bg-secondary);
             border-right: 1px solid var(--border); display: flex;
             flex-direction: column; transition: width .3s; overflow: hidden; }
.content  { flex: 1; overflow-y: auto; padding: 24px; }

/* ── Sidebar ── */
.logo-area { padding: 20px 16px; border-bottom: 1px solid var(--border); }
.logo-title { font-size: 18px; font-weight: 800; background: var(--gradient);
              -webkit-background-clip: text; -webkit-text-fill-color: transparent;
              background-clip: text; letter-spacing: -0.5px; }
.logo-sub   { font-size: 11px; color: var(--text-muted); margin-top: 2px; }

.nav  { flex: 1; padding: 12px 8px; overflow-y: auto; }
.nav-item { display: flex; align-items: center; gap: 10px; padding: 10px 12px;
             border-radius: var(--radius-sm); cursor: pointer; font-size: 13px;
             font-weight: 500; color: var(--text-muted); transition: all .2s;
             margin-bottom: 2px; text-decoration: none; }
.nav-item:hover  { background: var(--bg-hover); color: var(--text-primary); }
.nav-item.active { background: rgba(59,110,248,0.15); color: var(--accent-1);
                   font-weight: 600; }
.nav-item .icon  { font-size: 16px; width: 20px; text-align: center; }
.nav-badge { margin-left: auto; background: var(--accent-1); color: #fff;
             font-size: 10px; padding: 1px 6px; border-radius: 10px; }

.sidebar-footer { padding: 12px 8px; border-top: 1px solid var(--border); }
.theme-toggle   { display: flex; align-items: center; gap: 8px; cursor: pointer;
                  padding: 8px 12px; border-radius: var(--radius-sm);
                  color: var(--text-muted); font-size: 13px; user-select: none; }
.theme-toggle:hover { background: var(--bg-hover); }
.toggle-switch { width: 36px; height: 20px; background: var(--bg-hover);
                 border-radius: 10px; position: relative; margin-left: auto;
                 transition: background .2s; }
.toggle-switch.on { background: var(--accent-1); }
.toggle-knob  { width: 16px; height: 16px; background: #fff; border-radius: 50%;
                position: absolute; top: 2px; left: 2px; transition: left .2s; }
.toggle-switch.on .toggle-knob { left: 18px; }

/* ── Header ── */
.header { display: flex; align-items: center; justify-content: space-between;
          margin-bottom: 24px; gap: 16px; flex-wrap: wrap; }
.page-title { font-size: 22px; font-weight: 700; }
.page-title span { color: var(--text-muted); font-weight: 400; font-size: 14px;
                   margin-left: 8px; }
.header-actions { display: flex; gap: 8px; }

/* ── Buttons ── */
.btn { display: inline-flex; align-items: center; gap: 6px; padding: 8px 16px;
       border-radius: var(--radius-sm); border: none; cursor: pointer;
       font-size: 13px; font-weight: 600; transition: all .2s; text-decoration: none; }
.btn-primary { background: var(--gradient); color: #fff; box-shadow: 0 4px 12px rgba(59,110,248,.3); }
.btn-primary:hover { transform: translateY(-1px); box-shadow: 0 6px 20px rgba(59,110,248,.4); }
.btn-secondary { background: var(--bg-card); color: var(--text-primary); border: 1px solid var(--border); }
.btn-secondary:hover { background: var(--bg-hover); }
.btn-danger  { background: rgba(239,68,68,.15); color: var(--danger); border: 1px solid rgba(239,68,68,.3); }
.btn-danger:hover { background: rgba(239,68,68,.25); }
.btn-sm { padding: 5px 10px; font-size: 12px; }

/* ── Cards ── */
.cards-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px,1fr)); gap: 16px; margin-bottom: 24px; }
.card { background: var(--bg-card); border: 1px solid var(--border);
         border-radius: var(--radius); padding: 20px; transition: all .2s; position: relative; overflow: hidden; }
.card::before { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 3px;
                background: var(--gradient); }
.card:hover  { border-color: var(--accent-1); transform: translateY(-2px); box-shadow: var(--shadow); }
.card-label  { font-size: 11px; text-transform: uppercase; letter-spacing: 1px;
               color: var(--text-muted); font-weight: 600; margin-bottom: 8px; }
.card-value  { font-size: 28px; font-weight: 800; line-height: 1; }
.card-sub    { font-size: 12px; color: var(--text-muted); margin-top: 6px; }
.card-icon   { position: absolute; right: 16px; top: 50%; transform: translateY(-50%);
               font-size: 36px; opacity: .07; }

/* ── Table ── */
.table-wrap { background: var(--bg-card); border: 1px solid var(--border);
               border-radius: var(--radius); overflow: hidden; }
.table-head  { display: flex; justify-content: space-between; align-items: center;
                padding: 16px 20px; border-bottom: 1px solid var(--border); }
.table-head-title { font-weight: 700; font-size: 15px; }
table { width: 100%; border-collapse: collapse; }
th { background: rgba(255,255,255,.02); color: var(--text-muted);
     font-size: 11px; text-transform: uppercase; letter-spacing: .8px;
     font-weight: 600; padding: 12px 20px; text-align: left; white-space: nowrap; }
td { padding: 13px 20px; border-top: 1px solid var(--border); font-size: 13px; }
tr:hover td { background: var(--bg-hover); }

/* ── Badges ── */
.badge { display: inline-flex; align-items: center; gap: 4px; padding: 3px 8px;
          border-radius: 20px; font-size: 11px; font-weight: 600; white-space: nowrap; }
.badge-green  { background: rgba(16,185,129,.15); color: var(--success); }
.badge-red    { background: rgba(239,68,68,.15);  color: var(--danger); }
.badge-blue   { background: rgba(59,110,248,.15); color: var(--accent-1); }
.badge-violet { background: rgba(124,58,237,.15); color: var(--accent-2); }
.badge-cyan   { background: rgba(6,182,212,.15);  color: var(--accent-3); }

/* ── Progress bar ── */
.progress-wrap { background: var(--bg-primary); border-radius: 4px; height: 6px; overflow: hidden; }
.progress-fill  { height: 100%; border-radius: 4px; background: var(--gradient);
                  transition: width .5s ease; }

/* ── Charts ── */
.charts-row   { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px,1fr)); gap: 16px; margin-bottom: 24px; }
.chart-card   { background: var(--bg-card); border: 1px solid var(--border);
                border-radius: var(--radius); padding: 20px; }
.chart-title  { font-weight: 700; margin-bottom: 16px; font-size: 14px; }
canvas        { max-width: 100%; display: block; }

/* ── Modal ── */
.modal-overlay { display: none; position: fixed; inset: 0; background: rgba(0,0,0,.7);
                  z-index: 1000; justify-content: center; align-items: center;
                  backdrop-filter: blur(4px); }
.modal-overlay.open { display: flex; }
.modal  { background: var(--bg-card); border: 1px solid var(--border); border-radius: var(--radius);
           padding: 28px; min-width: 400px; max-width: 560px; width: 90vw;
           box-shadow: var(--shadow); animation: modalIn .2s ease; }
@keyframes modalIn { from { transform: scale(.95); opacity: 0; } to { transform: scale(1); opacity: 1; } }
.modal-title { font-size: 18px; font-weight: 700; margin-bottom: 20px; }
.modal-footer { display: flex; justify-content: flex-end; gap: 8px; margin-top: 24px; }

/* ── Forms ── */
.form-group { margin-bottom: 16px; }
.form-label { display: block; font-size: 12px; font-weight: 600; color: var(--text-muted);
               text-transform: uppercase; letter-spacing: .6px; margin-bottom: 6px; }
.form-input,
.form-select { width: 100%; background: var(--bg-primary); border: 1px solid var(--border);
               border-radius: var(--radius-sm); padding: 10px 12px; color: var(--text-primary);
               font-size: 13px; transition: border-color .2s; outline: none; }
.form-input:focus,
.form-select:focus { border-color: var(--accent-1); }
.form-row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }

/* ── Login ── */
.login-wrap { min-height: 100vh; display: flex; align-items: center; justify-content: center;
               background: var(--bg-primary); }
.login-card { background: var(--bg-card); border: 1px solid var(--border);
               border-radius: 16px; padding: 40px; width: 380px;
               box-shadow: 0 24px 64px rgba(0,0,0,.6); }
.login-logo { text-align: center; margin-bottom: 32px; }
.login-logo h1 { font-size: 26px; font-weight: 900; background: var(--gradient);
                 -webkit-background-clip: text; -webkit-text-fill-color: transparent;
                 background-clip: text; }
.login-logo p  { color: var(--text-muted); font-size: 12px; margin-top: 4px; }

/* ── Toast ── */
#toast-container { position: fixed; top: 20px; right: 20px; z-index: 9999;
                   display: flex; flex-direction: column; gap: 8px; }
.toast { background: var(--bg-card); border: 1px solid var(--border); border-radius: var(--radius-sm);
          padding: 12px 16px; display: flex; align-items: center; gap: 10px; font-size: 13px;
          box-shadow: var(--shadow); animation: toastIn .3s ease;
          min-width: 280px; max-width: 380px; }
@keyframes toastIn { from { transform: translateX(100%); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
.toast.success { border-color: var(--success); }
.toast.error   { border-color: var(--danger); }
.toast.warning { border-color: var(--warning); }

/* ── Tabs ── */
.tabs { display: flex; gap: 4px; margin-bottom: 20px; background: var(--bg-card);
         border: 1px solid var(--border); padding: 4px; border-radius: var(--radius-sm);
         width: fit-content; }
.tab-btn { padding: 8px 16px; border-radius: 6px; cursor: pointer; font-size: 13px;
            font-weight: 500; color: var(--text-muted); transition: all .2s;
            border: none; background: transparent; }
.tab-btn.active { background: var(--bg-secondary); color: var(--text-primary);
                  font-weight: 600; box-shadow: 0 2px 8px rgba(0,0,0,.3); }

/* ── Stats chart ── */
.sparkline-bar { display: flex; align-items: flex-end; gap: 3px; height: 48px; }
.sparkline-bar div { flex: 1; background: rgba(59,110,248,.4); border-radius: 2px 2px 0 0;
                      transition: height .5s, background .2s; }
.sparkline-bar div:hover { background: var(--accent-1); }

/* ── Code block ── */
.code-block { background: var(--bg-primary); border: 1px solid var(--border);
               border-radius: var(--radius-sm); padding: 12px 16px; font-family: var(--font-mono);
               font-size: 12px; overflow-x: auto; color: #a9c4f5; }

/* ── Responsive ── */
@media (max-width: 768px) {
  .sidebar  { width: 60px; min-width: 60px; }
  .nav-item .label { display: none; }
  .logo-area { padding: 12px 8px; }
  .logo-title, .logo-sub { display: none; }
  .content  { padding: 16px; }
  .form-row { grid-template-columns: 1fr; }
  .modal    { min-width: unset; }
}

/* ── Scrollbar & selection ── */
::selection { background: rgba(59,110,248,.3); }

/* ── Pulse animation ── */
@keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: .5; } }
.pulse { animation: pulse 2s infinite; }

/* ── Loading spinner ── */
.spinner { width: 32px; height: 32px; border: 3px solid var(--border);
            border-top-color: var(--accent-1); border-radius: 50%;
            animation: spin .8s linear infinite; margin: 40px auto; }
@keyframes spin { to { transform: rotate(360deg); } }
</style>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
</head>
<body>

<div id="toast-container"></div>

<!-- LOGIN -->
<div id="login-page" class="login-wrap">
  <div class="login-card">
    <div class="login-logo">
      <h1>⚡ FEDUK Panel</h1>
      <p>Proxy Management v3.0</p>
    </div>
    <div class="form-group">
      <label class="form-label">Username</label>
      <input type="text" id="login-user" class="form-input" value="admin" placeholder="admin">
    </div>
    <div class="form-group">
      <label class="form-label">Password</label>
      <input type="password" id="login-pass" class="form-input" placeholder="••••••••">
    </div>
    <button class="btn btn-primary" style="width:100%;justify-content:center;padding:12px"
            onclick="doLogin()">Sign In →</button>
    <div id="login-error" style="color:var(--danger);font-size:12px;margin-top:12px;text-align:center"></div>
  </div>
</div>

<!-- MAIN APP -->
<div id="app" class="layout" style="display:none">

  <!-- Sidebar -->
  <aside class="sidebar">
    <div class="logo-area">
      <div class="logo-title">⚡ FEDUK</div>
      <div class="logo-sub">Proxy Panel v3.0</div>
    </div>
    <nav class="nav">
      <a class="nav-item active" data-page="dashboard" onclick="navigate(this,'dashboard')">
        <span class="icon">📊</span><span class="label">Dashboard</span>
      </a>
      <a class="nav-item" data-page="inbounds" onclick="navigate(this,'inbounds')">
        <span class="icon">🔌</span><span class="label">Inbounds</span>
        <span class="nav-badge" id="badge-inbounds">0</span>
      </a>
      <a class="nav-item" data-page="clients" onclick="navigate(this,'clients')">
        <span class="icon">👥</span><span class="label">Clients</span>
        <span class="nav-badge" id="badge-clients">0</span>
      </a>
      <a class="nav-item" data-page="subscriptions" onclick="navigate(this,'subscriptions')">
        <span class="icon">🔗</span><span class="label">Subscriptions</span>
      </a>
      <a class="nav-item" data-page="statistics" onclick="navigate(this,'statistics')">
        <span class="icon">📈</span><span class="label">Statistics</span>
      </a>
      <a class="nav-item" data-page="settings" onclick="navigate(this,'settings')">
        <span class="icon">⚙️</span><span class="label">Settings</span>
      </a>
      <a class="nav-item" data-page="logs" onclick="navigate(this,'logs')">
        <span class="icon">📋</span><span class="label">Logs</span>
      </a>
      <a class="nav-item" data-page="backup" onclick="navigate(this,'backup')">
        <span class="icon">💾</span><span class="label">Backup</span>
      </a>
    </nav>
    <div class="sidebar-footer">
      <div class="theme-toggle" onclick="toggleTheme()">
        <span>🌙</span>
        <span class="label">Theme</span>
        <div class="toggle-switch" id="theme-sw"><div class="toggle-knob"></div></div>
      </div>
      <div class="nav-item" onclick="logout()" style="margin-top:4px;cursor:pointer">
        <span class="icon">🚪</span><span class="label">Logout</span>
      </div>
    </div>
  </aside>

  <!-- Content -->
  <main class="content" id="main-content">
    <div class="spinner"></div>
  </main>
</div>

<!-- MODALS -->
<div class="modal-overlay" id="modal-inbound">
  <div class="modal">
    <div class="modal-title">➕ New Inbound</div>
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Remark</label>
        <input type="text" id="ib-remark" class="form-input" placeholder="My VMess">
      </div>
      <div class="form-group">
        <label class="form-label">Protocol</label>
        <select id="ib-proto" class="form-select" onchange="updateProtoHint()">
          <option value="vmess">VMess</option>
          <option value="vless">VLESS</option>
          <option value="trojan">Trojan</option>
          <option value="shadowsocks">Shadowsocks</option>
          <option value="socks">SOCKS5</option>
          <option value="http">HTTP Proxy</option>
          <option value="dokodemo-door">Dokodemo-door</option>
        </select>
      </div>
    </div>
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Port (1–65535)</label>
        <input type="number" id="ib-port" class="form-input" placeholder="10001" min="1" max="65535">
      </div>
      <div class="form-group">
        <label class="form-label">Listen IP</label>
        <input type="text" id="ib-listen" class="form-input" value="0.0.0.0">
      </div>
    </div>
    <div id="proto-hint" class="code-block" style="margin-top:4px;font-size:11px"></div>
    <div class="modal-footer">
      <button class="btn btn-secondary" onclick="closeModal('modal-inbound')">Cancel</button>
      <button class="btn btn-primary" onclick="submitInbound()">Create Inbound</button>
    </div>
  </div>
</div>

<div class="modal-overlay" id="modal-client">
  <div class="modal">
    <div class="modal-title">👤 New Client</div>
    <div class="form-group">
      <label class="form-label">Email / Name</label>
      <input type="text" id="cl-email" class="form-input" placeholder="user@example.com">
    </div>
    <div class="form-group">
      <label class="form-label">Inbound</label>
      <select id="cl-inbound" class="form-select"></select>
    </div>
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Traffic Limit (GB, 0=∞)</label>
        <input type="number" id="cl-traffic" class="form-input" value="0" min="0">
      </div>
      <div class="form-group">
        <label class="form-label">IP Limit (0=∞)</label>
        <input type="number" id="cl-iplimit" class="form-input" value="0" min="0">
      </div>
    </div>
    <div class="form-group">
      <label class="form-label">Expire Date (optional)</label>
      <input type="datetime-local" id="cl-expire" class="form-input">
    </div>
    <div class="modal-footer">
      <button class="btn btn-secondary" onclick="closeModal('modal-client')">Cancel</button>
      <button class="btn btn-primary" onclick="submitClient()">Create Client</button>
    </div>
  </div>
</div>

<script>
// ── State ──────────────────────────────────
const API = '/api';
let token = localStorage.getItem('feduk_token') || '';
let currentPage = 'dashboard';
let wsConn = null;
let statsHistory = { cpu: Array(20).fill(0), mem: Array(20).fill(0) };

// ── Auth ───────────────────────────────────
async function doLogin() {
  const u = document.getElementById('login-user').value.trim();
  const p = document.getElementById('login-pass').value;
  document.getElementById('login-error').textContent = '';
  try {
    const fd = new FormData();
    fd.append('username', u); fd.append('password', p);
    const r = await fetch(`${API}/auth/token`, { method:'POST', body: fd });
    if (!r.ok) throw new Error('Invalid credentials');
    const d = await r.json();
    token = d.access_token;
    localStorage.setItem('feduk_token', token);
    showApp();
  } catch(e) {
    document.getElementById('login-error').textContent = e.message;
  }
}
document.getElementById('login-pass').addEventListener('keydown', e => {
  if (e.key === 'Enter') doLogin();
});

function logout() {
  token = '';
  localStorage.removeItem('feduk_token');
  document.getElementById('app').style.display = 'none';
  document.getElementById('login-page').style.display = 'flex';
}

// ── App init ───────────────────────────────
async function showApp() {
  document.getElementById('login-page').style.display = 'none';
  document.getElementById('app').style.display = 'flex';
  await navigate(document.querySelector('[data-page="dashboard"]'), 'dashboard');
  connectWS();
}

function headers() {
  return { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' };
}

async function apiGet(path) {
  const r = await fetch(`${API}${path}`, { headers: headers() });
  if (r.status === 401) { logout(); return null; }
  return r.json();
}
async function apiPost(path, body) {
  const r = await fetch(`${API}${path}`, {
    method: 'POST', headers: headers(), body: JSON.stringify(body)
  });
  if (r.status === 401) { logout(); return null; }
  return r.json();
}
async function apiDelete(path) {
  const r = await fetch(`${API}${path}`, { method: 'DELETE', headers: headers() });
  if (r.status === 401) { logout(); return null; }
  return r.json();
}

// ── Navigation ─────────────────────────────
async function navigate(el, page) {
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  if (el) el.classList.add('active');
  currentPage = page;
  const mc = document.getElementById('main-content');
  mc.innerHTML = '<div class="spinner"></div>';
  switch(page) {
    case 'dashboard':     await renderDashboard(); break;
    case 'inbounds':      await renderInbounds(); break;
    case 'clients':       await renderClients(); break;
    case 'subscriptions': await renderSubscriptions(); break;
    case 'statistics':    await renderStatistics(); break;
    case 'settings':      renderSettings(); break;
    case 'logs':          await renderLogs(); break;
    case 'backup':        await renderBackup(); break;
  }
}

// ── Dashboard ──────────────────────────────
async function renderDashboard() {
  const data = await apiGet('/dashboard');
  const mc = document.getElementById('main-content');
  if (!data) return;
  const s = data.system; const p = data.proxy;
  const upd = fmtUptime(s.uptime_seconds);
  mc.innerHTML = `
  <div class="header">
    <div class="page-title">Dashboard <span>System Overview</span></div>
    <div class="header-actions">
      <span id="ws-status" class="badge badge-red">● Disconnected</span>
    </div>
  </div>
  <div class="cards-grid">
    <div class="card">
      <div class="card-label">CPU Usage</div>
      <div class="card-value" id="dash-cpu">${s.cpu_percent.toFixed(1)}<small style="font-size:16px">%</small></div>
      <div class="progress-wrap" style="margin-top:10px"><div class="progress-fill" style="width:${s.cpu_percent}%"></div></div>
      <div class="card-icon">🖥️</div>
    </div>
    <div class="card">
      <div class="card-label">Memory</div>
      <div class="card-value" id="dash-mem">${s.mem_percent.toFixed(1)}<small style="font-size:16px">%</small></div>
      <div class="progress-wrap" style="margin-top:10px"><div class="progress-fill" style="width:${s.mem_percent}%"></div></div>
      <div class="card-sub">${fmtBytes(s.mem_used)} / ${fmtBytes(s.mem_total)}</div>
      <div class="card-icon">💾</div>
    </div>
    <div class="card">
      <div class="card-label">Disk</div>
      <div class="card-value">${s.disk_percent.toFixed(1)}<small style="font-size:16px">%</small></div>
      <div class="progress-wrap" style="margin-top:10px"><div class="progress-fill" style="width:${s.disk_percent}%"></div></div>
      <div class="card-sub">${fmtBytes(s.disk_used)} / ${fmtBytes(s.disk_total)}</div>
      <div class="card-icon">💿</div>
    </div>
    <div class="card">
      <div class="card-label">Uptime</div>
      <div class="card-value" style="font-size:20px">${upd}</div>
      <div class="card-icon">⏱️</div>
    </div>
    <div class="card">
      <div class="card-label">Inbounds</div>
      <div class="card-value">${p.inbounds_total}</div>
      <div class="card-icon">🔌</div>
    </div>
    <div class="card">
      <div class="card-label">Active Clients</div>
      <div class="card-value">${p.clients_active} <small style="font-size:14px;color:var(--text-muted)">/ ${p.clients_total}</small></div>
      <div class="card-icon">👥</div>
    </div>
    <div class="card">
      <div class="card-label">Traffic ↑</div>
      <div class="card-value" id="dash-tu">${p.traffic_up_gb.toFixed(2)}<small style="font-size:16px"> GB</small></div>
      <div class="card-icon">📤</div>
    </div>
    <div class="card">
      <div class="card-label">Traffic ↓</div>
      <div class="card-value" id="dash-td">${p.traffic_down_gb.toFixed(2)}<small style="font-size:16px"> GB</small></div>
      <div class="card-icon">📥</div>
    </div>
  </div>
  <div class="charts-row">
    <div class="chart-card">
      <div class="chart-title">CPU History (real-time)</div>
      <div class="sparkline-bar" id="spark-cpu">
        ${statsHistory.cpu.map(v=>`<div style="height:${Math.max(4,v*0.48)}px" title="${v}%"></div>`).join('')}
      </div>
    </div>
    <div class="chart-card">
      <div class="chart-title">Memory History (real-time)</div>
      <div class="sparkline-bar" id="spark-mem">
        ${statsHistory.mem.map(v=>`<div style="height:${Math.max(4,v*0.48)}px;background:rgba(124,58,237,.5)" title="${v}%"></div>`).join('')}
      </div>
    </div>
    <div class="chart-card">
      <div class="chart-title">Network I/O</div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:8px">
        <div>
          <div style="font-size:11px;color:var(--text-muted);margin-bottom:4px">SENT</div>
          <div style="font-size:20px;font-weight:700" id="net-sent">${fmtBytes(s.net_sent)}</div>
        </div>
        <div>
          <div style="font-size:11px;color:var(--text-muted);margin-bottom:4px">RECV</div>
          <div style="font-size:20px;font-weight:700" id="net-recv">${fmtBytes(s.net_recv)}</div>
        </div>
      </div>
    </div>
  </div>`;
}

// ── Inbounds page ─────────────────────────
async function renderInbounds() {
  const data = await apiGet('/inbounds');
  const mc = document.getElementById('main-content');
  if (!data) return;
  document.getElementById('badge-inbounds').textContent = data.length;
  let rows = data.map(ib => `
    <tr>
      <td><span class="badge badge-blue">#${ib.id}</span></td>
      <td><strong>${escHtml(ib.remark)}</strong></td>
      <td><span class="badge badge-violet">${escHtml(ib.protocol)}</span></td>
      <td><code style="font-family:var(--font-mono)">${ib.port}</code></td>
      <td>${ib.enabled
          ? '<span class="badge badge-green">● Active</span>'
          : '<span class="badge badge-red">● Disabled</span>'}</td>
      <td>${fmtDate(ib.created_at)}</td>
      <td>
        <button class="btn btn-danger btn-sm" onclick="deleteInbound(${ib.id})">Delete</button>
      </td>
    </tr>`).join('') || `<tr><td colspan="7" style="text-align:center;color:var(--text-muted);padding:40px">No inbounds yet</td></tr>`;

  mc.innerHTML = `
  <div class="header">
    <div class="page-title">Inbounds <span>${data.length} configured</span></div>
    <div class="header-actions">
      <button class="btn btn-primary" onclick="openModal('modal-inbound')">➕ New Inbound</button>
    </div>
  </div>
  <div class="table-wrap">
    <div class="table-head"><span class="table-head-title">🔌 Inbound List</span></div>
    <table>
      <thead><tr>
        <th>ID</th><th>Remark</th><th>Protocol</th><th>Port</th>
        <th>Status</th><th>Created</th><th>Actions</th>
      </tr></thead>
      <tbody>${rows}</tbody>
    </table>
  </div>`;
}

async function deleteInbound(id) {
  if (!confirm(`Delete inbound #${id}? This will remove all its clients.`)) return;
  await apiDelete(`/inbounds/${id}`);
  toast('Inbound deleted', 'success');
  await renderInbounds();
}

async function submitInbound() {
  const remark   = document.getElementById('ib-remark').value.trim();
  const protocol = document.getElementById('ib-proto').value;
  const port     = parseInt(document.getElementById('ib-port').value);
  const listen   = document.getElementById('ib-listen').value.trim();
  if (!remark || !port) { toast('Fill all required fields', 'error'); return; }
  const r = await apiPost('/inbounds', { remark, protocol, port, listen, settings:{}, stream:{} });
  if (r && r.id) {
    toast(`Inbound "${remark}" created on port ${port}`, 'success');
    closeModal('modal-inbound');
    await renderInbounds();
  } else {
    toast(r?.detail || 'Failed to create inbound', 'error');
  }
}

function updateProtoHint() {
  const p = document.getElementById('ib-proto').value;
  const hints = {
    vmess:        'VMess — WebSocket/gRPC/HTTP2/XTLS transport',
    vless:        'VLESS — Reality/XTLS-rprx-vision',
    trojan:       'Trojan — TLS camouflage, Trojan-Go compatible',
    shadowsocks:  'Shadowsocks — 2022 AEAD / Obfs',
    socks:        'SOCKS5 — with optional auth',
    http:         'HTTP CONNECT proxy',
    'dokodemo-door': 'Dokodemo-door — transparent proxy',
  };
  document.getElementById('proto-hint').textContent = hints[p] || '';
}

// ── Clients page ──────────────────────────
async function renderClients() {
  const data = await apiGet('/clients');
  const mc = document.getElementById('main-content');
  if (!data) return;
  document.getElementById('badge-clients').textContent = data.length;
  let rows = data.map(c => {
    const traf = `${fmtBytes(c.traffic_up + c.traffic_down)}`;
    const lim  = c.traffic_limit ? fmtBytes(c.traffic_limit) : '∞';
    const pct  = c.traffic_limit
      ? Math.min(100, (c.traffic_up + c.traffic_down) / c.traffic_limit * 100) : 0;
    const expired = c.expire_date && new Date(c.expire_date) < new Date();
    return `<tr>
      <td><span class="badge badge-blue">#${c.id}</span></td>
      <td><strong>${escHtml(c.email)}</strong></td>
      <td><code style="font-family:var(--font-mono);font-size:11px">${c.uuid.substr(0,13)}…</code></td>
      <td>
        <div style="font-size:12px;margin-bottom:4px">${traf} / ${lim}</div>
        ${c.traffic_limit ? `<div class="progress-wrap" style="width:80px"><div class="progress-fill" style="width:${pct}%"></div></div>` : ''}
      </td>
      <td>${c.expire_date
          ? `<span class="badge ${expired?'badge-red':'badge-cyan'}">${fmtDate(c.expire_date)}</span>`
          : '<span style="color:var(--text-muted)">∞</span>'}</td>
      <td>${c.enabled && !expired
          ? '<span class="badge badge-green">● Active</span>'
          : '<span class="badge badge-red">● Disabled</span>'}</td>
      <td>
        <button class="btn btn-secondary btn-sm" onclick="copySubLink('${c.uuid}')">📋 Sub</button>
        <button class="btn btn-danger btn-sm"    onclick="deleteClient(${c.id})">Delete</button>
      </td>
    </tr>`;}).join('') || `<tr><td colspan="7" style="text-align:center;color:var(--text-muted);padding:40px">No clients yet</td></tr>`;

  mc.innerHTML = `
  <div class="header">
    <div class="page-title">Clients <span>${data.length} total</span></div>
    <div class="header-actions">
      <button class="btn btn-primary" onclick="openClientModal()">➕ New Client</button>
    </div>
  </div>
  <div class="table-wrap">
    <div class="table-head"><span class="table-head-title">👥 Client List</span></div>
    <table>
      <thead><tr>
        <th>ID</th><th>Email</th><th>UUID</th><th>Traffic</th>
        <th>Expires</th><th>Status</th><th>Actions</th>
      </tr></thead>
      <tbody>${rows}</tbody>
    </table>
  </div>`;
}

async function openClientModal() {
  const inbs = await apiGet('/inbounds');
  const sel  = document.getElementById('cl-inbound');
  sel.innerHTML = (inbs || []).map(ib => `<option value="${ib.id}">${escHtml(ib.remark)} (${ib.protocol}:${ib.port})</option>`).join('');
  openModal('modal-client');
}

async function submitClient() {
  const email       = document.getElementById('cl-email').value.trim();
  const inbound_id  = parseInt(document.getElementById('cl-inbound').value);
  const traffic_lim = parseInt(document.getElementById('cl-traffic').value) * 1024**3;
  const ip_limit    = parseInt(document.getElementById('cl-iplimit').value);
  const expire_raw  = document.getElementById('cl-expire').value;
  const expire_date = expire_raw ? new Date(expire_raw).toISOString() : null;
  if (!email) { toast('Enter email', 'error'); return; }
  const r = await apiPost('/clients', { email, inbound_id, traffic_limit: traffic_lim, ip_limit, expire_date });
  if (r && r.id) {
    toast(`Client "${email}" created`, 'success');
    closeModal('modal-client');
    await renderClients();
  } else {
    toast(r?.detail || 'Failed to create client', 'error');
  }
}

async function deleteClient(id) {
  if (!confirm(`Delete client #${id}?`)) return;
  await apiDelete(`/clients/${id}`);
  toast('Client deleted', 'success');
  await renderClients();
}

function copySubLink(uuid) {
  const link = `${location.origin}/sub/${uuid}`;
  navigator.clipboard.writeText(link).then(() => toast('Subscription link copied!', 'success'));
}

// ── Subscriptions ─────────────────────────
async function renderSubscriptions() {
  const clients = await apiGet('/clients');
  const mc = document.getElementById('main-content');
  if (!clients) return;
  let rows = clients.map(c => `
    <tr>
      <td>${escHtml(c.email)}</td>
      <td>
        <div class="code-block" style="font-size:11px;word-break:break-all">
          ${location.origin}/sub/${c.uuid}
        </div>
      </td>
      <td>
        <button class="btn btn-secondary btn-sm" onclick="copyText('${location.origin}/sub/${c.uuid}')">📋 Copy</button>
        <button class="btn btn-secondary btn-sm" onclick="copyText('${location.origin}/sub/${c.uuid}?fmt=clash')">Clash</button>
        <button class="btn btn-secondary btn-sm" onclick="copyText('${location.origin}/sub/${c.uuid}?fmt=singbox')">Sing-box</button>
      </td>
    </tr>`).join('') || `<tr><td colspan="3" style="text-align:center;color:var(--text-muted);padding:40px">No clients</td></tr>`;

  mc.innerHTML = `
  <div class="header">
    <div class="page-title">Subscriptions <span>Share links</span></div>
  </div>
  <div class="table-wrap">
    <div class="table-head"><span class="table-head-title">🔗 Subscription Links</span></div>
    <table>
      <thead><tr><th>Client</th><th>Link</th><th>Formats</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>
  </div>`;
}

// ── Statistics ────────────────────────────
async function renderStatistics() {
  const data = await apiGet('/dashboard');
  const mc = document.getElementById('main-content');
  if (!data) return;
  mc.innerHTML = `
  <div class="header">
    <div class="page-title">Statistics <span>Usage data</span></div>
  </div>
  <div class="cards-grid">
    <div class="card">
      <div class="card-label">Total Upload</div>
      <div class="card-value">${data.proxy.traffic_up_gb.toFixed(3)}<small style="font-size:16px"> GB</small></div>
    </div>
    <div class="card">
      <div class="card-label">Total Download</div>
      <div class="card-value">${data.proxy.traffic_down_gb.toFixed(3)}<small style="font-size:16px"> GB</small></div>
    </div>
  </div>
  <div class="chart-card" style="background:var(--bg-card);border:1px solid var(--border);border-radius:var(--radius);padding:24px">
    <div class="chart-title">Live CPU & Memory (WebSocket)</div>
    <div id="live-cpu-bar" class="sparkline-bar">${statsHistory.cpu.map(v=>`<div style="height:${Math.max(4,v*0.48)}px" title="${v}%"></div>`).join('')}</div>
    <div style="font-size:11px;color:var(--text-muted);margin-top:8px">CPU — updates every 2 seconds via WebSocket</div>
  </div>`;
}

// ── Settings ──────────────────────────────
function renderSettings() {
  document.getElementById('main-content').innerHTML = `
  <div class="header">
    <div class="page-title">Settings <span>System configuration</span></div>
  </div>
  <div class="chart-card" style="background:var(--bg-card);border:1px solid var(--border);border-radius:var(--radius);padding:24px;max-width:600px">
    <div class="chart-title" style="margin-bottom:20px">⚙️ General</div>
    <div class="form-group">
      <label class="form-label">Panel Title</label>
      <input class="form-input" value="FEDUK Proxy Panel" readonly>
    </div>
    <div class="form-group">
      <label class="form-label">Xray Config Path</label>
      <input class="form-input" value="/opt/feduk/xray/configs/config.json" readonly>
    </div>
    <div class="form-group">
      <label class="form-label">Database Path</label>
      <input class="form-input" value="/opt/feduk/data/config.db" readonly>
    </div>
    <div class="form-group">
      <label class="form-label">Backup Directory</label>
      <input class="form-input" value="/opt/feduk/backups/" readonly>
    </div>
    <p style="color:var(--text-muted);font-size:12px;margin-top:16px">
      Edit <code>/etc/feduk/config.yml</code> on server to change settings.
    </p>
  </div>`;
}

// ── Logs ──────────────────────────────────
async function renderLogs() {
  const data = await apiGet('/logs?lines=200&log_type=access');
  const mc = document.getElementById('main-content');
  const lines = data?.lines || [];
  mc.innerHTML = `
  <div class="header">
    <div class="page-title">Logs <span>${lines.length} lines</span></div>
    <div class="header-actions">
      <button class="btn btn-secondary" onclick="renderLogs()">🔄 Refresh</button>
    </div>
  </div>
  <div class="code-block" style="height:70vh;overflow-y:auto;white-space:pre;font-size:12px;line-height:1.8">
    ${lines.length ? escHtml(lines.join('\n')) : '(no log entries yet)'}
  </div>`;
  const cb = mc.querySelector('.code-block');
  if (cb) cb.scrollTop = cb.scrollHeight;
}

// ── Backup ────────────────────────────────
async function renderBackup() {
  const mc = document.getElementById('main-content');
  mc.innerHTML = `
  <div class="header">
    <div class="page-title">Backup <span>Database & configs</span></div>
  </div>
  <div class="chart-card" style="background:var(--bg-card);border:1px solid var(--border);border-radius:var(--radius);padding:24px;max-width:500px">
    <div class="chart-title">💾 Create Backup</div>
    <p style="color:var(--text-muted);margin:12px 0">
      Creates a <code>.tar.gz</code> archive of database, configs, and Xray settings.
    </p>
    <button class="btn btn-primary" onclick="doBackup()">Create Backup Now</button>
    <div id="backup-result" style="margin-top:16px"></div>
  </div>`;
}

async function doBackup() {
  const r = await apiPost('/backup', {});
  const el = document.getElementById('backup-result');
  if (r && r.backup_file) {
    el.innerHTML = `<span class="badge badge-green">✓ Saved: ${escHtml(r.backup_file)} (${r.size_mb} MB)</span>`;
    toast('Backup created!', 'success');
  } else {
    el.innerHTML = `<span class="badge badge-red">✗ Backup failed</span>`;
  }
}

// ── WebSocket ─────────────────────────────
function connectWS() {
  if (wsConn) return;
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  try {
    wsConn = new WebSocket(`${proto}://${location.host}/ws/stats`);
    wsConn.onmessage = e => {
      const d = JSON.parse(e.data);
      statsHistory.cpu.push(d.cpu); statsHistory.cpu.shift();
      statsHistory.mem.push(d.mem); statsHistory.mem.shift();
      const ws_el = document.getElementById('ws-status');
      if (ws_el) { ws_el.textContent = '● Live'; ws_el.className = 'badge badge-green'; }
      if (currentPage === 'dashboard') updateDashLive(d);
      if (currentPage === 'statistics') updateStatsLive();
    };
    wsConn.onclose = () => { wsConn = null; setTimeout(connectWS, 3000); };
    wsConn.onerror = () => { wsConn = null; };
  } catch(e) {}
}

function updateDashLive(d) {
  const cpu = document.getElementById('dash-cpu');
  if (cpu) cpu.innerHTML = `${d.cpu.toFixed(1)}<small style="font-size:16px">%</small>`;
  const mem = document.getElementById('dash-mem');
  if (mem) mem.innerHTML = `${d.mem.toFixed(1)}<small style="font-size:16px">%</small>`;
  const ns = document.getElementById('net-sent');
  if (ns) ns.textContent = fmtBytes(d.net_sent);
  const nr = document.getElementById('net-recv');
  if (nr) nr.textContent = fmtBytes(d.net_recv);
  updateSparklines();
}

function updateSparklines() {
  const sc = document.getElementById('spark-cpu');
  if (sc) sc.innerHTML = statsHistory.cpu.map(v=>`<div style="height:${Math.max(4,v*0.48)}px" title="${v}%"></div>`).join('');
  const sm = document.getElementById('spark-mem');
  if (sm) sm.innerHTML = statsHistory.mem.map(v=>`<div style="height:${Math.max(4,v*0.48)}px;background:rgba(124,58,237,.5)" title="${v}%"></div>`).join('');
}

function updateStatsLive() {
  const lb = document.getElementById('live-cpu-bar');
  if (lb) lb.innerHTML = statsHistory.cpu.map(v=>`<div style="height:${Math.max(4,v*0.48)}px" title="${v}%"></div>`).join('');
}

// ── Modals ────────────────────────────────
function openModal(id)  { document.getElementById(id).classList.add('open'); updateProtoHint(); }
function closeModal(id) { document.getElementById(id).classList.remove('open'); }
document.querySelectorAll('.modal-overlay').forEach(m => {
  m.addEventListener('click', e => { if (e.target === m) m.classList.remove('open'); });
});

// ── Theme ────────────────────────────────
function toggleTheme() {
  const html = document.documentElement;
  const isDark = html.getAttribute('data-theme') === 'dark';
  html.setAttribute('data-theme', isDark ? 'light' : 'dark');
  const sw = document.getElementById('theme-sw');
  if (sw) sw.classList.toggle('on', !isDark);
  localStorage.setItem('feduk_theme', isDark ? 'light' : 'dark');
}
(function() {
  const t = localStorage.getItem('feduk_theme') || 'dark';
  document.documentElement.setAttribute('data-theme', t);
  if (t === 'light') {
    const sw = document.getElementById('theme-sw');
    if (sw) sw.classList.add('on');
  }
})();

// ── Toast ─────────────────────────────────
function toast(msg, type='info') {
  const icons = { success:'✅', error:'❌', warning:'⚠️', info:'ℹ️' };
  const tc = document.getElementById('toast-container');
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.innerHTML = `<span>${icons[type]||'ℹ️'}</span><span>${escHtml(msg)}</span>`;
  tc.appendChild(el);
  setTimeout(() => { el.style.opacity='0'; el.style.transform='translateX(100%)';
                     el.style.transition='all .3s'; setTimeout(()=>el.remove(),300); }, 3500);
}

// ── Utilities ─────────────────────────────
function fmtBytes(b) {
  if (b < 1024) return b + ' B';
  if (b < 1048576) return (b/1024).toFixed(1) + ' KB';
  if (b < 1073741824) return (b/1048576).toFixed(1) + ' MB';
  return (b/1073741824).toFixed(2) + ' GB';
}
function fmtDate(d) {
  if (!d) return '-';
  return new Date(d).toLocaleDateString('ru-RU', {day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'});
}
function fmtUptime(s) {
  const d = Math.floor(s/86400), h = Math.floor((s%86400)/3600), m = Math.floor((s%3600)/60);
  return `${d}d ${h}h ${m}m`;
}
function escHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function copyText(t) {
  navigator.clipboard.writeText(t).then(() => toast('Copied!', 'success'));
}

// ── Auto-login if token exists ─────────────
if (token) {
  apiGet('/dashboard').then(d => {
    if (d) showApp(); else { token=''; localStorage.removeItem('feduk_token'); }
  });
}
</script>
</body>
</html>
HTMLEOF

    print_ok "Frontend HTML/CSS/JS created at ${STATIC}/index.html"
    log_info "Frontend created"
    progress_bar
}

# ─────────────────────────────────────────────
#  NGINX CONFIG
# ─────────────────────────────────────────────
configure_nginx() {
    print_step "Configuring Nginx reverse proxy"

    local server_name="${DOMAIN:-${SERVER_IP}}"

    cat > /etc/nginx/sites-available/feduk <<NGINXEOF
# ── FEDUK Panel — Nginx config ──────────────
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen ${HTTP_PORT};
    server_name ${server_name};
    return 301 https://\$host\$request_uri;
}

server {
    listen ${PANEL_PORT} ssl;
    http2 on;
    server_name ${server_name};

    ssl_certificate     ${INSTALL_DIR}/certs/cert.pem;
    ssl_certificate_key ${INSTALL_DIR}/certs/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;

    access_log ${INSTALL_DIR}/logs/nginx-access.log;
    error_log  ${INSTALL_DIR}/logs/nginx-error.log;

    client_max_body_size 50m;

    # WebSocket support
    location /ws/ {
        proxy_pass         http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection \$connection_upgrade;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
    }

    # API and SPA
    location / {
        proxy_pass         http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120;
        proxy_connect_timeout 30;
    }
}
NGINXEOF

    ln -sf /etc/nginx/sites-available/feduk /etc/nginx/sites-enabled/feduk 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    nginx -t >> "$LOG_FILE" 2>&1 || die "Nginx config test failed — check ${LOG_FILE}"

    systemctl enable nginx  >> "$LOG_FILE" 2>&1
    systemctl restart nginx >> "$LOG_FILE" 2>&1

    print_ok "Nginx configured and restarted"
    log_info "Nginx configured for ${server_name}"
    progress_bar
}

# ─────────────────────────────────────────────
#  MAIN CONFIG FILE
# ─────────────────────────────────────────────
create_main_config() {
    print_step "Writing main configuration"

    local server_host="${DOMAIN:-${SERVER_IP}}"
    local secret_key
    secret_key=$(openssl rand -hex 32)
    local admin_hash
    admin_hash=$(python3 -c "from passlib.context import CryptContext; print(CryptContext(schemes=['bcrypt']).hash('${ADMIN_PASS}'))" 2>/dev/null \
        || python3 -c "import hashlib; print(hashlib.sha256(b'${ADMIN_PASS}').hexdigest())")

    cat > "${CONFIG_DIR}/config.yml" <<CFGEOF
# ── FEDUK Panel Configuration ──
version: "3.0"
secret_key: "${secret_key}"
admin_user: "${ADMIN_USER}"
admin_password_hash: "${admin_hash}"
server_host: "${server_host}"
panel_port: ${PANEL_PORT}
telegram_bot_token: "${TG_BOT_TOKEN}"
telegram_admin_id: "${TG_ADMIN_ID}"
xray_api_host: "127.0.0.1"
xray_api_port: 10085
redis_host: "127.0.0.1"
redis_port: 6379
backup_cron: "0 3 * * *"
log_level: "info"
CFGEOF

    cat > "${CONFIG_DIR}/admin.json" <<ADEOF
{
  "admins": [
    {
      "username": "${ADMIN_USER}",
      "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }
  ]
}
ADEOF

    print_ok "Config written to ${CONFIG_DIR}/config.yml"
    log_info "Main config created"
    progress_bar
}

# ─────────────────────────────────────────────
#  SYSTEMD SERVICES
# ─────────────────────────────────────────────
create_systemd_services() {
    print_step "Creating systemd services"

    # Xray service
    cat > /etc/systemd/system/xray-feduk.service <<SVCEOF
[Unit]
Description=FEDUK Xray-core
Documentation=https://xtls.github.io
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${INSTALL_DIR}/xray/bin/xray run -config ${INSTALL_DIR}/xray/configs/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
SVCEOF

    # FastAPI panel service
    cat > /etc/systemd/system/feduk.service <<PANELEOF
[Unit]
Description=FEDUK Proxy Panel (FastAPI)
After=network.target redis-server.service xray-feduk.service
Wants=redis-server.service xray-feduk.service

[Service]
User=root
WorkingDirectory=${INSTALL_DIR}/panel
Environment="SERVER_HOST=${DOMAIN:-$SERVER_IP}"
Environment="PATH=${INSTALL_DIR}/panel/venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=${INSTALL_DIR}/panel/venv/bin/uvicorn main:app \
    --host 127.0.0.1 \
    --port 8000 \
    --workers 2 \
    --access-log \
    --log-level info
Restart=always
RestartSec=5
LimitNOFILE=100000
StandardOutput=append:${INSTALL_DIR}/logs/panel.log
StandardError=append:${INSTALL_DIR}/logs/panel-error.log

[Install]
WantedBy=multi-user.target
PANELEOF

    systemctl daemon-reload >> "$LOG_FILE" 2>&1

    run_with_spinner "Enabling Xray-core service" \
        bash -c "systemctl enable xray-feduk && systemctl start xray-feduk"

    run_with_spinner "Enabling FEDUK panel service" \
        bash -c "systemctl enable feduk && systemctl start feduk"

    print_ok "Services started: xray-feduk, feduk"
    log_info "Systemd services created and started"
    progress_bar
}

# ─────────────────────────────────────────────
#  INIT ADMIN IN DATABASE
# ─────────────────────────────────────────────
init_admin_db() {
    print_step "Initialising admin account in database"

    run_with_spinner "Waiting for panel to start" bash -c "sleep 4"

    python3 - <<INITPY
import sys, os
sys.path.insert(0, '${INSTALL_DIR}/panel')
os.chdir('${INSTALL_DIR}/panel')

# Activate venv
activate = '${INSTALL_DIR}/panel/venv/bin/activate_this.py'
try:
    exec(open(activate).read(), {'__file__': activate})
except Exception:
    pass

try:
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    from passlib.context import CryptContext

    engine = create_engine('sqlite:////${INSTALL_DIR}/data/config.db',
                           connect_args={'check_same_thread': False})
    Session = sessionmaker(bind=engine)
    db = Session()

    from main import Base, User
    Base.metadata.create_all(bind=engine)

    existing = db.query(User).filter(User.username == '${ADMIN_USER}').first()
    if not existing:
        pwd = CryptContext(schemes=['bcrypt']).hash('${ADMIN_PASS}')
        u = User(username='${ADMIN_USER}', password_hash=pwd)
        db.add(u)
        db.commit()
        print('Admin created OK')
    else:
        from passlib.context import CryptContext
        existing.password_hash = CryptContext(schemes=['bcrypt']).hash('${ADMIN_PASS}')
        db.commit()
        print('Admin updated OK')
    db.close()
except Exception as e:
    print(f'DB init error: {e}', file=sys.stderr)
INITPY

    print_ok "Admin account initialised"
    log_info "Admin DB init done"
    progress_bar
}

# ─────────────────────────────────────────────
#  CLI TOOLS
# ─────────────────────────────────────────────
install_cli_tools() {
    print_step "Installing CLI management tools"

    # feduk-backup
    cat > /usr/local/bin/feduk-backup <<'BKEOF'
#!/bin/bash
set -e
BACKUP_DIR="/opt/feduk/backups"
TS=$(date +%Y%m%d_%H%M%S)
FILE="${BACKUP_DIR}/feduk_backup_${TS}.tar.gz"
tar -czf "$FILE" /opt/feduk/data /etc/feduk /opt/feduk/xray/configs 2>/dev/null
echo "✓ Backup saved: $FILE ($(du -sh "$FILE" | cut -f1))"
BKEOF
    chmod +x /usr/local/bin/feduk-backup

    # feduk-update
    cat > /usr/local/bin/feduk-update <<'UPDEOF'
#!/bin/bash
set -e
echo "Updating Xray-core..."
LATEST=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep tag_name | cut -d'"' -f4)
ARCH=$(uname -m)
case "$ARCH" in x86_64) XA="64";; aarch64) XA="arm64-v8a";; *) XA="64";; esac
TMP=$(mktemp -d)
curl -sSL "https://github.com/XTLS/Xray-core/releases/download/${LATEST}/Xray-linux-${XA}.zip" -o "${TMP}/xray.zip"
unzip -qo "${TMP}/xray.zip" -d "${TMP}/xray"
systemctl stop xray-feduk
cp "${TMP}/xray/xray" /opt/feduk/xray/bin/xray
chmod +x /opt/feduk/xray/bin/xray
systemctl start xray-feduk
rm -rf "$TMP"
echo "✓ Xray updated to ${LATEST}"
echo "Restarting panel..."
systemctl restart feduk
echo "✓ Panel restarted"
UPDEOF
    chmod +x /usr/local/bin/feduk-update

    # feduk-status
    cat > /usr/local/bin/feduk-status <<'STEOF'
#!/bin/bash
echo "══════════════════════════════════════"
echo "  FEDUK Panel — Service Status"
echo "══════════════════════════════════════"
services=(feduk xray-feduk nginx redis-server)
for s in "${services[@]}"; do
    if systemctl is-active --quiet "$s"; then
        echo "  ✓ ${s}"
    else
        echo "  ✗ ${s} (STOPPED)"
    fi
done
echo "══════════════════════════════════════"
echo "  Disk: $(df -h /opt/feduk | tail -1 | awk '{print $3"/"$2" ("$5")"}')"
echo "  Load: $(uptime | awk -F'load average:' '{print $2}' | xargs)"
echo "══════════════════════════════════════"
STEOF
    chmod +x /usr/local/bin/feduk-status

    print_ok "CLI tools installed: feduk-backup, feduk-update, feduk-status"
    log_info "CLI tools installed"
    progress_bar
}

# ─────────────────────────────────────────────
#  LOGROTATE
# ─────────────────────────────────────────────
setup_logrotate() {
    cat > /etc/logrotate.d/feduk <<'LREOF'
/opt/feduk/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        systemctl reload feduk  2>/dev/null || true
        systemctl reload nginx  2>/dev/null || true
    endscript
}
LREOF
    print_ok "Logrotate configured"
    log_info "Logrotate set up"
}

# ─────────────────────────────────────────────
#  AUTO BACKUP CRON
# ─────────────────────────────────────────────
setup_cron_backup() {
    (crontab -l 2>/dev/null | grep -v feduk-backup
     echo "0 3 * * * /usr/local/bin/feduk-backup >> /opt/feduk/logs/backup.log 2>&1") \
     | crontab - 2>/dev/null || true
    print_ok "Auto-backup cron set (03:00 daily)"
    log_info "Auto-backup cron installed"
}

# ─────────────────────────────────────────────
#  SAVE CREDENTIALS
# ─────────────────────────────────────────────
save_credentials() {
    local panel_url="https://${DOMAIN:-${SERVER_IP}}"
    [[ "${PANEL_PORT}" != "443" ]] && panel_url="${panel_url}:${PANEL_PORT}"

    cat > "$CRED_FILE" <<CREDEOF
# ════════════════════════════════════════════
#   FEDUK PANEL CREDENTIALS
#   Generated: $(date)
# ════════════════════════════════════════════
PANEL_URL=${panel_url}
ADMIN_USER=${ADMIN_USER}
ADMIN_PASS=${ADMIN_PASS}
SERVER_IP=${SERVER_IP}
DOMAIN=${DOMAIN:-none}
SSL=${USE_LETSENCRYPT}
# ════════════════════════════════════════════
CREDEOF
    chmod 600 "$CRED_FILE"
    print_ok "Credentials saved to ${CRED_FILE}"
    log_info "Credentials saved"
}

# ─────────────────────────────────────────────
#  HEALTH CHECK
# ─────────────────────────────────────────────
health_check() {
    print_step "Running health checks"
    local ok=true

    local services=("feduk" "xray-feduk" "nginx" "redis-server")
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            print_ok "Service: ${svc}"
        else
            print_warn "Service: ${svc} — not running"
            ok=false
        fi
    done

    # API check
    sleep 2
    if curl -sk --max-time 5 "https://127.0.0.1:${PANEL_PORT}/api/docs" &>/dev/null; then
        print_ok "Panel API responding on port ${PANEL_PORT}"
    else
        print_warn "Panel API not yet responding (may need a moment)"
    fi

    $ok && log_success "All health checks passed" || log_warn "Some checks failed"
    progress_bar
}

# ─────────────────────────────────────────────
#  FINAL SUMMARY BOX
# ─────────────────────────────────────────────
show_summary() {
    local panel_url="https://${DOMAIN:-${SERVER_IP}}"
    [[ "${PANEL_PORT}" != "443" ]] && panel_url="${panel_url}:${PANEL_PORT}"

    echo
    echo -e "${C1}${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${C2}${BOLD}║          FEDUK PROXY PANEL v3.0 — INSTALLED          ║${RESET}"
    echo -e "${C3}${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"
    echo -e "${C4}${BOLD}║${RESET}                                                      ${C4}${BOLD}║${RESET}"
    echo -e "${C4}${BOLD}║${RESET}  ${GREEN}${BOLD}Panel URL :${RESET} ${WHITE}${BOLD}${panel_url}${RESET}"
    printf   "${C4}${BOLD}║${RESET}  ${GREEN}${BOLD}Login     :${RESET} ${WHITE}${BOLD}%-40s${C4}${BOLD}║${RESET}\n" "${ADMIN_USER}"
    printf   "${C4}${BOLD}║${RESET}  ${GREEN}${BOLD}Password  :${RESET} ${WHITE}${BOLD}%-40s${C4}${BOLD}║${RESET}\n" "${ADMIN_PASS}"
    echo -e "${C4}${BOLD}║${RESET}                                                      ${C4}${BOLD}║${RESET}"
    echo -e "${C5}${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"
    echo -e "${C5}${BOLD}║${RESET}  ${CYAN}Creds file  :${RESET} ${DIM}${CRED_FILE}${RESET}"
    echo -e "${C5}${BOLD}║${RESET}  ${CYAN}Backup cmd  :${RESET} ${YELLOW}feduk-backup${RESET}"
    echo -e "${C5}${BOLD}║${RESET}  ${CYAN}Update cmd  :${RESET} ${YELLOW}feduk-update${RESET}"
    echo -e "${C5}${BOLD}║${RESET}  ${CYAN}Status cmd  :${RESET} ${YELLOW}feduk-status${RESET}"
    echo -e "${C5}${BOLD}║${RESET}  ${CYAN}Panel logs  :${RESET} ${YELLOW}journalctl -u feduk -f${RESET}"
    echo -e "${C5}${BOLD}║${RESET}  ${CYAN}Xray logs   :${RESET} ${YELLOW}journalctl -u xray-feduk -f${RESET}"
    echo -e "${C6}${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"
    echo -e "${C6}${BOLD}║${RESET}  ${DIM}Protocols: VMess · VLESS · Trojan · Shadowsocks   ${C6}${BOLD}║${RESET}"
    echo -e "${C6}${BOLD}║${RESET}  ${DIM}           WireGuard · SOCKS5 · HTTP · Reality     ${C6}${BOLD}║${RESET}"
    echo -e "${C6}${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
    echo
    echo -e "  ${GREEN}${BOLD}Installation complete! Open panel:${RESET} ${WHITE}${BOLD}${panel_url}${RESET}"
    echo
}

# ─────────────────────────────────────────────
#  CLEANUP ON EXIT
# ─────────────────────────────────────────────
cleanup() {
    stop_spinner
}
trap cleanup EXIT INT TERM

# ═════════════════════════════════════════════
#  MAIN
# ═════════════════════════════════════════════
main() {
    # Init log
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    log_info "FEDUK Panel installer started — v${FEDUK_VERSION}"

    show_banner

    echo -e "${C3}${BOLD}  Starting installation sequence...${RESET}\n"
    sleep 1

    check_root
    detect_os
    check_arch
    detect_network
    interactive_setup

    echo
    echo -e "${C2}${BOLD}  ▸ Installing components${RESET}"
    echo

    pkg_update
    install_base_deps
    configure_firewall
    install_python
    install_nodejs
    install_redis

    create_directories
    install_xray
    install_nginx

    setup_ssl
    create_xray_config
    setup_python_backend
    create_frontend
    configure_nginx
    create_main_config
    create_systemd_services
    init_admin_db
    install_cli_tools
    setup_logrotate
    setup_cron_backup
    save_credentials
    health_check

    show_summary

    log_success "Installation completed successfully"
}

main "$@"
