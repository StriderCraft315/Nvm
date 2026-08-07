#!/usr/bin/env bash
set -euo pipefail

RED="\e[1;31m"; GREEN="\e[1;32m"; YELLOW="\e[1;33m"; CYAN="\e[1;36m"; MAGENTA="\e[1;35m"; NC="\e[0m"
line() { echo -e "${MAGENTA}============================================================${NC}"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

clear
echo -e "${CYAN}"
cat << "EOF"

███╗   ██╗██╗   ██╗███╗   ███╗
████╗  ██║██║   ██║████╗ ████║
██╔██╗ ██║██║   ██║██╔████╔██║
██║╚██╗██║╚██╗ ██╔╝██║╚██╔╝██║
██║ ╚████║ ╚████╔╝ ██║ ╚═╝ ██║
╚═╝  ╚═══╝  ╚═══╝  ╚═╝     ╚═╝

        NVM PANEL V4 ULTRA INSTALLER

EOF
echo -e "${NC}"
line

if [[ "$EUID" -ne 0 ]]; then
    error "Please run this installer as root."
    exit 1
fi

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
else
    error "Unable to detect operating system."
    exit 1
fi
ARCH=$(uname -m)
info "Detected OS: ${PRETTY_NAME}"
info "Architecture: ${ARCH}"
line

info "Installing dependencies..."
if command -v apt >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt update -y
    apt install -y wget lsof tar unzip sudo nano python3 python3-pip ca-certificates
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y wget lsof tar unzip sudo nano python3 python3-pip ca-certificates
elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release
    yum install -y wget lsof tar unzip sudo nano python3 python3-pip ca-certificates
elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm wget lsof tar unzip sudo nano python python-pip ca-certificates
elif command -v apk >/dev/null 2>&1; then
    apk update
    apk add wget lsof tar unzip sudo nano python3 py3-pip ca-certificates
elif command -v zypper >/dev/null 2>&1; then
    zypper refresh
    zypper install -y wget lsof tar unzip sudo nano python3 python3-pip ca-certificates
else
    error "Unsupported Linux distribution."
    exit 1
fi
ok "Dependencies installed."
line

NVM_URL="https://github.com/StriderCraft315/Nvm/releases/download/NVM-v4/nvm.bin"
INSTALL_DIR="/opt/nvm"
SERVICE_NAME="nvm"
PANEL_PORT="5000"
BIN_FILE="${INSTALL_DIR}/nvm.bin"
LOG_FILE="/var/log/nvm.log"

if lsof -Pi :${PANEL_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    warn "Port ${PANEL_PORT} is already in use."
    echo
    lsof -i:${PANEL_PORT}
    echo
    read -rp "Continue anyway? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        error "Installation cancelled."
        exit 1
    fi
fi
line

info "Creating installation directory..."
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"
ok "Directory created."
line

info "Downloading nvm.bin with wget..."
rm -f nvm.bin
wget --tries=5 --timeout=30 --progress=bar:force -O nvm.bin "${NVM_URL}"
echo
line

if [[ ! -f nvm.bin ]]; then
    error "Download failed – file not found."
    exit 1
fi
if [[ ! -s nvm.bin ]]; then
    error "Downloaded file is empty."
    exit 1
fi
if file nvm.bin | grep -qi "html"; then
    error "Downloaded HTML page instead of binary. Check the URL."
    exit 1
fi

chmod +x nvm.bin
ok "nvm.bin downloaded and made executable."
line

info "Configuring firewall..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PANEL_PORT}/tcp >/dev/null 2>&1 || true
fi
if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=${PANEL_PORT}/tcp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi
if command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT -p tcp --dport ${PANEL_PORT} -j ACCEPT >/dev/null 2>&1 || \
    iptables -I INPUT -p tcp --dport ${PANEL_PORT} -j ACCEPT >/dev/null 2>&1 || true
fi
ok "Firewall configured."
line

if command -v systemctl >/dev/null 2>&1; then
    info "Creating systemd service..."
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=NVM Panel V4
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_FILE}
Restart=always
RestartSec=5
LimitNOFILE=1048576
User=root
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
    systemctl restart ${SERVICE_NAME}
    sleep 5

    # Verify it's listening
    if systemctl is-active --quiet ${SERVICE_NAME} && lsof -Pi :${PANEL_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
        ok "NVM service started successfully."
    else
        error "NVM service failed to start or is not listening on port ${PANEL_PORT}."
        echo
        echo "--- Last 10 lines of ${LOG_FILE} ---"
        tail -n 10 "${LOG_FILE}" 2>/dev/null || echo "Log file not found."
        echo
        systemctl status ${SERVICE_NAME} --no-pager
        echo
        exit 1
    fi
else
    warn "systemd not detected – running manually."
    nohup ${BIN_FILE} >> ${LOG_FILE} 2>&1 &
    sleep 3
    if ! lsof -Pi :${PANEL_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
        error "Manual start failed. Check ${LOG_FILE}."
        tail -n 10 "${LOG_FILE}" 2>/dev/null
        exit 1
    fi
fi
line

# Get public IP (only IPv4, plain text)
PUBLIC_IP=$(wget -4 -qO- --timeout=10 ifconfig.me 2>/dev/null || true)
if [[ -z "${PUBLIC_IP}" ]]; then
    PUBLIC_IP=$(hostname -I | awk '{print $1}')
fi
if [[ -z "${PUBLIC_IP}" ]]; then
    PUBLIC_IP="YOUR_SERVER_IP"
fi

clear
echo -e "${GREEN}"
cat << EOF

╔══════════════════════════════════════════════════════╗
║               NVM PANEL V4 INSTALLED                ║
╚══════════════════════════════════════════════════════╝

PANEL URL         : http://${PUBLIC_IP}:${PANEL_PORT}

USERNAME          : admin
PASSWORD          : admin

INSTALL DIRECTORY : ${INSTALL_DIR}

BINARY FILE       : ${BIN_FILE}

LOG FILE          : ${LOG_FILE}

SERVICE NAME      : ${SERVICE_NAME}

════════════════════════════════════════════════════════

SERVICE COMMANDS

systemctl start ${SERVICE_NAME}
systemctl stop ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}
systemctl status ${SERVICE_NAME}

════════════════════════════════════════════════════════

VIEW LIVE LOGS

journalctl -u ${SERVICE_NAME} -f

════════════════════════════════════════════════════════

EOF
echo -e "${NC}"
