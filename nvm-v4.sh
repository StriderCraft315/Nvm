#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# COLORS
# =========================================================
RED="\e[1;31m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
CYAN="\e[1;36m"
MAGENTA="\e[1;35m"
NC="\e[0m"

line() {
    echo -e "${MAGENTA}============================================================${NC}"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =========================================================
# ASCII ART – NVM
# =========================================================
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

# =========================================================
# ROOT CHECK
# =========================================================
if [[ "$EUID" -ne 0 ]]; then
    error "Please run this installer as root."
    exit 1
fi

# =========================================================
# OS DETECTION
# =========================================================
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    DISTRO=$ID
    VERSION=$VERSION_ID
else
    error "Unable to detect operating system."
    exit 1
fi

ARCH=$(uname -m)
info "Detected OS: ${PRETTY_NAME}"
info "Architecture: ${ARCH}"
line

# =========================================================
# INSTALL DEPENDENCIES
# =========================================================
info "Installing dependencies..."

if command -v apt >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt update -y
    apt install -y curl wget lsof tar unzip sudo nano python3 python3-pip ca-certificates

elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl wget lsof tar unzip sudo nano python3 python3-pip ca-certificates

elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release
    yum install -y curl wget lsof tar unzip sudo nano python3 python3-pip ca-certificates

elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm curl wget lsof tar unzip sudo nano python python-pip ca-certificates

elif command -v apk >/dev/null 2>&1; then
    apk update
    apk add curl wget lsof tar unzip sudo nano python3 py3-pip ca-certificates

elif command -v zypper >/dev/null 2>&1; then
    zypper refresh
    zypper install -y curl wget lsof tar unzip sudo nano python3 python3-pip ca-certificates

else
    error "Unsupported Linux distribution."
    exit 1
fi

ok "Dependencies installed."
line

# =========================================================
# VARIABLES
# =========================================================
NVM_URL="https://github.com/StriderCraft315/Nvm/releases/download/NVM-v4/nvm.bin"
INSTALL_DIR="/opt/nvm"
SERVICE_NAME="nvm"
PANEL_PORT="5000"
BIN_FILE="${INSTALL_DIR}/nvm.bin"
LOG_FILE="/var/log/nvm.log"
MIN_FILE_SIZE_MB=30

# =========================================================
# PORT CHECK
# =========================================================
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

# =========================================================
# CREATE INSTALL DIRECTORY
# =========================================================
info "Creating installation directory..."
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"
ok "Directory created."
line

# =========================================================
# DOWNLOAD BINARY
# =========================================================
info "Downloading nvm.bin..."
rm -f nvm.bin
curl -L --fail --retry 5 --retry-delay 3 --progress-bar -o nvm.bin "${NVM_URL}"
echo
line

# =========================================================
# VERIFY BINARY
# =========================================================
if [[ ! -f nvm.bin ]]; then
    error "Download failed."
    exit 1
fi

if [[ ! -s nvm.bin ]]; then
    error "Downloaded file is empty."
    exit 1
fi

FILE_SIZE_MB=$(du -m nvm.bin | cut -f1)
info "Downloaded File Size: ${FILE_SIZE_MB}MB"

if [[ "${FILE_SIZE_MB}" -lt "${MIN_FILE_SIZE_MB}" ]]; then
    error "Invalid or corrupted nvm.bin detected."
    file nvm.bin || true
    exit 1
fi

if file nvm.bin | grep -qi "html"; then
    error "Downloaded HTML page instead of binary."
    exit 1
fi

chmod +x nvm.bin
ok "nvm.bin verified successfully."
line

# =========================================================
# FIREWALL CONFIG
# =========================================================
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

# =========================================================
# SYSTEMD SERVICE
# =========================================================
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

    if systemctl is-active --quiet ${SERVICE_NAME}; then
        ok "NVM service started successfully."
    else
        error "NVM service failed to start."
        echo
        systemctl status ${SERVICE_NAME} --no-pager
        echo
        exit 1
    fi
else
    warn "systemd not detected."
    warn "Running NVM manually..."
    nohup ${BIN_FILE} >> ${LOG_FILE} 2>&1 &
    sleep 3
fi
line

# =========================================================
# PANEL STATUS
# =========================================================
if lsof -Pi :${PANEL_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    PANEL_STATUS="${GREEN}ONLINE${NC}"
else
    PANEL_STATUS="${RED}OFFLINE${NC}"
fi

# =========================================================
# PUBLIC IP
# =========================================================
PUBLIC_IP=$(curl -4 -s --max-time 10 ifconfig.me || true)
if [[ -z "${PUBLIC_IP}" ]]; then
    PUBLIC_IP=$(hostname -I | awk '{print $1}')
fi
if [[ -z "${PUBLIC_IP}" ]]; then
    PUBLIC_IP="YOUR_SERVER_IP"
fi

# =========================================================
# FINISH (no one-line installer)
# =========================================================
clear
echo -e "${GREEN}"
cat << EOF

╔══════════════════════════════════════════════════════╗
║               NVM PANEL V4 INSTALLED                ║
╚══════════════════════════════════════════════════════╝

STATUS            : ${PANEL_STATUS}

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
