#!/bin/bash
set -e

run() {
  echo ">>> $*"
  "$@"
}

log_info()  { echo "[INFO]  $*"; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

echo "=== Starfish Demo Setup ==="

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
  log_error "This script must be run as root (or with sudo)."
  exit 1
fi

# --- Detect OS ---
detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID}"
    OS_VERSION="${VERSION_ID}"
    OS_NAME="${NAME}"
  elif [[ -f /etc/redhat-release ]]; then
    OS_ID="rhel"
    OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    OS_NAME=$(cat /etc/redhat-release)
  else
    OS_ID="unknown"
    OS_VERSION="unknown"
    OS_NAME="Unknown"
  fi
  log_info "Detected OS: ${OS_NAME} ${OS_VERSION} (${OS_ID})"
}

# --- Detect package manager ---
detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
  else
    PKG_MANAGER="unknown"
  fi
  log_info "Package manager: ${PKG_MANAGER}"
}

# --- Install a package ---
install_pkg() {
  local pkg="$1"
  log_info "Installing ${pkg}..."
  case "$PKG_MANAGER" in
    apt)
      apt-get update -qq
      apt-get install -y "$pkg"
      ;;
    dnf)
      dnf install -y "$pkg"
      ;;
    yum)
      yum install -y "$pkg"
      ;;
    *)
      log_error "Unsupported package manager. Please install '${pkg}' manually."
      exit 1
      ;;
  esac
}

# --- Check and install dependencies ---
check_dependencies() {
  local missing=()

  # curl
  if ! command -v curl >/dev/null 2>&1; then
    missing+=("curl")
  fi

  # tar
  if ! command -v tar >/dev/null 2>&1; then
    missing+=("tar")
  fi

  # xz (for .tar.xz extraction)
  if ! command -v xz >/dev/null 2>&1; then
    case "$PKG_MANAGER" in
      apt) missing+=("xz-utils") ;;
      dnf|yum) missing+=("xz") ;;
      *) missing+=("xz") ;;
    esac
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_warn "Missing dependencies: ${missing[*]}"
    read -p "Install missing dependencies? [Y/n]: " INSTALL_DEPS
    INSTALL_DEPS="${INSTALL_DEPS:-Y}"
    if [[ "$INSTALL_DEPS" =~ ^[Yy]$ ]]; then
      for pkg in "${missing[@]}"; do
        install_pkg "$pkg"
      done
    else
      log_error "Cannot continue without dependencies."
      exit 1
    fi
  else
    log_info "All dependencies satisfied."
  fi
}

# --- Detect current IP address ---
detect_ip() {
  local ip=""

  # Method 1: hostname -I (most common)
  if command -v hostname >/dev/null 2>&1; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi

  # Method 2: ip command fallback
  if [[ -z "$ip" ]] && command -v ip >/dev/null 2>&1; then
    ip=$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
  fi

  # Method 3: ifconfig fallback (older systems)
  if [[ -z "$ip" ]] && command -v ifconfig >/dev/null 2>&1; then
    ip=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]+\.){3}[0-9]+' | \
         grep -v '127.0.0.1' | awk '{print $2}' | sed 's/addr://' | head -1)
  fi

  if [[ -z "$ip" ]]; then
    log_warn "Could not auto-detect IP address."
    read -p "Enter this machine's IP address: " ip
  fi

  echo "$ip"
}

# --- Install systemd-nspawn if needed ---
install_nspawn() {
  if command -v systemd-nspawn >/dev/null 2>&1; then
    log_info "systemd-nspawn is already installed."
    return 0
  fi

  log_info "systemd-nspawn not found. Installing..."

  case "$PKG_MANAGER" in
    apt)
      install_pkg "systemd-container"
      ;;
    dnf|yum)
      install_pkg "systemd-container"
      ;;
    *)
      log_error "Cannot auto-install systemd-container. Please install manually."
      exit 1
      ;;
  esac
}

# =============================================================================
# Main Script
# =============================================================================

detect_os
detect_pkg_manager

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- License check ---
if [[ ! -f "$SCRIPT_DIR/license" ]]; then
  log_error "License file not found."
  echo "Please place the license file here and re-run:"
  echo "  $SCRIPT_DIR/license"
  exit 1
fi

# --- Check dependencies ---
check_dependencies

# --- Destination directory ---
DEFAULT_DIR="/opt/starfish-demo"
read -p "Extract demo to directory [${DEFAULT_DIR}]: " DEST_DIR
DEST_DIR="${DEST_DIR:-$DEFAULT_DIR}"
DEST_DIR="${DEST_DIR%/}"  # Remove trailing slash

run mkdir -p "$DEST_DIR"

# --- Download and extract ---
TARBALL="starfish-demo.tar.xz"
TARBALL_PATH="${DEST_DIR}/${TARBALL}"
DOWNLOAD_URL="https://starfishdownloads.s3.amazonaws.com/tools/${TARBALL}"

if [[ -f "$TARBALL_PATH" ]]; then
  read -p "Tarball already exists at ${TARBALL_PATH}. Re-download? [y/N]: " REDOWNLOAD
  if [[ "$REDOWNLOAD" =~ ^[Yy]$ ]]; then
    run curl -o "$TARBALL_PATH" "$DOWNLOAD_URL"
  fi
else
  run curl -o "$TARBALL_PATH" "$DOWNLOAD_URL"
fi

run tar -xJf "$TARBALL_PATH" -C "$DEST_DIR"

# --- Copy license ---
run cp "$SCRIPT_DIR/license" "$DEST_DIR/opt/starfish/etc/license"

echo
echo "=== Update IP references inside extracted container ==="

CURRENT_IP=$(detect_ip)
echo "Current detected IP: $CURRENT_IP"

read -p "Continue replacing 172.31.34.47 with $CURRENT_IP? (y/N): " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  CONFIG_FILES=(
    "$DEST_DIR/opt/starfish/pg/17/local.conf"
    "$DEST_DIR/opt/starfish/etc/99-local.ini"
    "$DEST_DIR/opt/starfish/etc/01-service.ini"
    "$DEST_DIR/opt/starfish/nginx/etc/conf.d/starfish/local.conf"
    "$DEST_DIR/opt/starfish/grafana/promtail/etc/promtail.yaml"
    "$DEST_DIR/opt/starfish/redash-systemd/10.1.0/.env"
  )

  for f in "${CONFIG_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      run sed -i "s/172\.31\.34\.47/$CURRENT_IP/g" "$f"
    else
      log_warn "Config file not found (skipping): $f"
    fi
  done

  echo "Replaced with IP: $CURRENT_IP"
else
  echo "Cancelled. No changes made."
fi

echo
echo "=== Create agent IP update script (runs once on container boot) ==="

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  cat > /tmp/update_agent_ip_address.sh <<EOF
#!/bin/bash
set -e

MAX_RETRIES=30
RETRY_DELAY=10
IP="${CURRENT_IP}"

echo "Waiting for Starfish to be ready..."

for i in \$(seq 1 \$MAX_RETRIES); do
  if sf volume list &>/dev/null; then
    echo "Starfish is ready. Updating agent IP addresses..."
    break
  fi
  if [ \$i -eq \$MAX_RETRIES ]; then
    echo "ERROR: Timeout waiting for Starfish after 5 minutes."
    exit 1
  fi
  echo "Waiting for Starfish... (\$i/\$MAX_RETRIES)"
  sleep \$RETRY_DELAY
done

sf volume add-agent dthompson  "https://\${IP}:30002" /home/dthompson  --replace-as-default
sf volume add-agent mwatson    "https://\${IP}:30002" /home/mwatson    --replace-as-default
sf volume add-agent sleung     "https://\${IP}:30002" /home/sleung     --replace-as-default
sf volume add-agent jbaker     "https://\${IP}:30002" /home/jbaker     --replace-as-default
sf volume add-agent nromero    "https://\${IP}:30002" /home/nromero    --replace-as-default
sf volume add-agent kpatel     "https://\${IP}:30002" /home/kpatel     --replace-as-default
sf volume add-agent akim       "https://\${IP}:30002" /home/akim       --replace-as-default
sf volume add-agent rmorgan    "https://\${IP}:30002" /home/rmorgan    --replace-as-default
sf volume add-agent efs        "https://\${IP}:30002" /mnt/efs         --replace-as-default
sf volume add-agent sim-lustre "https://\${IP}:30002" /mnt/sim-lustre  --replace-as-default
sf volume add-agent sim-nfs    "https://\${IP}:30002" /mnt/sim-nfs     --replace-as-default
sf volume add-agent sim-s3     "https://\${IP}:30002" /mnt/sim-s3      --replace-as-default

echo "Agent IP addresses updated successfully."
EOF

  run mkdir -p "$DEST_DIR/usr/sbin"
  run cp /tmp/update_agent_ip_address.sh "$DEST_DIR/usr/sbin/update_agent_ip_address.sh"
  run chmod +x "$DEST_DIR/usr/sbin/update_agent_ip_address.sh"
  run rm -f /tmp/update_agent_ip_address.sh

  cat > /tmp/update_agent_ip_address.service <<'EOF'
[Unit]
Description=Update Starfish agent IP addresses (run once)
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/update_agent_ip_address.sh
ExecStartPost=/bin/systemctl disable update_agent_ip_address.service
TimeoutStartSec=360

[Install]
WantedBy=multi-user.target
EOF

  run mkdir -p "$DEST_DIR/etc/systemd/system"
  run cp /tmp/update_agent_ip_address.service "$DEST_DIR/etc/systemd/system/update_agent_ip_address.service"
  run rm -f /tmp/update_agent_ip_address.service

  run mkdir -p "$DEST_DIR/etc/systemd/system/multi-user.target.wants"
  run ln -sf /etc/systemd/system/update_agent_ip_address.service \
    "$DEST_DIR/etc/systemd/system/multi-user.target.wants/update_agent_ip_address.service"

  log_info "Created /usr/sbin/update_agent_ip_address.sh inside container (with IP: $CURRENT_IP)"
else
  log_warn "Skipping agent update script + service because IP replacement was cancelled."
fi

echo
echo "=== Starfish Demo Setup Complete ==="
read -p "Start Starfish Demo now? [y/N]: " R
if [[ "$R" =~ ^[Yy]$ ]]; then
  install_nspawn

  echo
  log_info "Starting Starfish Demo container..."
  log_info "Login: root / root"
  echo
  systemd-nspawn -D "$DEST_DIR" --boot
fi
