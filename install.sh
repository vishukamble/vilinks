#!/usr/bin/env bash
set -euo pipefail

OWNER="${VILINKS_OWNER:-vishukamble}"
REPO="${VILINKS_REPO:-vilinks}"
REF="${VILINKS_REF:-main}"   # can be tag too
INSTALL_DIR="${VILINKS_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/vilinks}"
DATA_DIR="${VILINKS_DATA_DIR:-$HOME/.vilinks}"
CFG_FILE="$DATA_DIR/config.env"
PORT_DEFAULT="${VILINKS_PORT:-8765}"
PREFIX_DEFAULT="${VILINKS_PREFIX:-vi}"

RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; GREEN=$'\033[0;32m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'
info(){ echo "${CYAN}→${NC} $*"; }
ok(){ echo "${GREEN}✓${NC} $*"; }
warn(){ echo "${YELLOW}⚠${NC} $*"; }
die(){ echo "${RED}✗${NC} $*" >&2; exit 1; }

has(){ command -v "$1" >/dev/null 2>&1; }

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "mac";;
    Linux) echo "linux";;
    *) echo "other";;
  esac
}

compose_cmd() {
  if has docker && docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif has docker-compose; then
    echo "docker-compose"
  else
    echo ""
  fi
}

download_and_extract() {
  mkdir -p "$INSTALL_DIR"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # Support tags or branches via same URL pattern:
  # tags: refs/tags/<tag>.tar.gz ; branches: refs/heads/<branch>.tar.gz
  local kind="heads"
  [[ "$REF" != "main" && "$REF" != "master" ]] && kind="heads"
  # If user explicitly sets VILINKS_IS_TAG=1, treat REF as tag
  if [[ "${VILINKS_IS_TAG:-0}" == "1" ]]; then kind="tags"; fi

  local url="https://github.com/$OWNER/$REPO/archive/refs/$kind/$REF.tar.gz"

  info "Downloading $OWNER/$REPO ($REF) ..."
  curl -fsSL "$url" -o "$tmp/vilinks.tgz" || die "Download failed: $url"

  info "Extracting to $INSTALL_DIR/src ..."
  rm -rf "$INSTALL_DIR/src"
  mkdir -p "$INSTALL_DIR/src"
  tar -xzf "$tmp/vilinks.tgz" -C "$tmp"
  # repo extracts as <repo>-<ref>/
  local extracted
  extracted="$(find "$tmp" -maxdepth 1 -type d -name "${REPO}-*" | head -n1)"
  [[ -n "$extracted" ]] || die "Could not find extracted folder"
  cp -R "$extracted/." "$INSTALL_DIR/src"
  ok "Installed source → $INSTALL_DIR/src"
}

write_config() {
  local prefix="$1" port="$2"
  mkdir -p "$INSTALL_DIR" "$DATA_DIR"
  cat > "$CFG_FILE" <<EOF
VILINKS_PREFIX=$prefix
VILINKS_PORT=$port
VILINKS_DB=$DATA_DIR/vilinks.db
VILINKS_BASE_URL=http://127.0.0.1:${port}/
EOF
  ok "Config → $CFG_FILE"
}

maybe_pretty_url() {
  local os="$1" prefix="$2" port="$3"

  echo ""
  read -r -p "Set up pretty URL http://$prefix/ (hosts + port 80 forward, requires sudo)? [y/N]: " ans
  ans="${ans:-N}"
  [[ "$ans" =~ ^[Yy]$ ]] || return 0

  # Port 80 check
  if has lsof && lsof -i :80 -sTCP:LISTEN >/dev/null 2>&1; then
    warn "Port 80 is already in use. You can still use: http://$prefix.localhost:$port/"
    return 0
  fi

  info "Adding hosts entry (127.0.0.1 $prefix) ..."
  if grep -qE "^127\.0\.0\.1[[:space:]]+$prefix(\s|$)" /etc/hosts 2>/dev/null; then
    ok "Hosts entry already present"
  else
    echo "127.0.0.1 $prefix" | sudo tee -a /etc/hosts >/dev/null
    ok "Added hosts entry"
  fi

  if [[ "$os" == "mac" ]]; then
    local anchor="/etc/pf.anchors/vilinks"
    local pfconf="/etc/pf.conf"
    local plist="/Library/LaunchDaemons/com.vilinks.portforward.plist"

    info "Configuring pf port forward 80 → $port (macOS)..."
    echo "rdr pass on lo0 proto tcp from any to 127.0.0.1 port 80 -> 127.0.0.1 port $port" | sudo tee "$anchor" >/dev/null

    # Ensure pf.conf loads the anchor
    if ! sudo grep -q 'vilinks' "$pfconf"; then
      sudo cp "$pfconf" "$pfconf.bak"
      printf '\n# vilinks\nrdr-anchor "vilinks"\nload anchor "vilinks" from "/etc/pf.anchors/vilinks"\n' | sudo tee -a "$pfconf" >/dev/null
    fi

    sudo pfctl -f "$pfconf" >/dev/null || true
    sudo pfctl -E >/dev/null 2>&1 || true

    # Persist on reboot
    cat <<EOF | sudo tee "$plist" >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.vilinks.portforward</string>
  <key>ProgramArguments</key>
  <array>
    <string>/sbin/pfctl</string><string>-f</string><string>/etc/pf.conf</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
    sudo chown root:wheel "$plist"
    sudo chmod 644 "$plist"
    sudo launchctl unload "$plist" >/dev/null 2>&1 || true
    sudo launchctl load "$plist" >/dev/null

    ok "Pretty URL enabled: http://$prefix/"
    return 0
  fi

  if [[ "$os" == "linux" ]]; then
    has iptables || die "iptables not found (needed for port forward)."
    info "Configuring iptables port forward 80 → $port (Linux)..."
    sudo iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 --dport 80 -j REDIRECT --to-port "$port" 2>/dev/null || true
    sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port "$port" 2>/dev/null || true
    ok "Pretty URL enabled: http://$prefix/"
    return 0
  fi

  warn "Pretty URL setup is only supported on macOS/Linux in this script."
}

run_docker() {
  local c; c="$(compose_cmd)"
  [[ -n "$c" ]] || die "Docker Compose not found. Install Docker Desktop / docker compose."

  # Export config so docker-compose.yml can use it
  set -a
  # shellcheck disable=SC1090
  export VILINKS_DATA_DIR="$DATA_DIR"
  source "$CFG_FILE"
  set +a

  info "Starting vilinks (Docker)..."
  (cd "$INSTALL_DIR/src" && $c up -d --build) || die "Docker failed to start"
  ok "vilinks is running (Docker)"
}

run_python() {
  has python3 || die "python3 not found."

  local VENV_DIR="$DATA_DIR/venv"
  local PID_FILE="$DATA_DIR/vilinks.pid"
  local LOG_FILE="$DATA_DIR/vilinks.log"

  info "Setting up venv (Python)..."
  mkdir -p "$DATA_DIR"
  cd "$INSTALL_DIR/src"

  python3 -m venv "$VENV_DIR"
  # shellcheck disable=SC1091
  source "$VENV_DIR/bin/activate"
  python -m pip install -U pip >/dev/null
  python -m pip install -r requirements.txt

  info "Starting vilinks (Python)..."

  # Load config.env safely + export vars
  set -a
  # shellcheck disable=SC1090
  source "$CFG_FILE"
  set +a

  nohup "$VENV_DIR/bin/python" app.py > "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"

  ok "vilinks started (Python) pid=$(cat "$PID_FILE")"
  ok "Logs → $LOG_FILE"
}

main() {
  echo ""
  echo "vilinks installer"
  echo ""

  local os; os="$(detect_os)"
  [[ "$os" != "other" ]] || warn "Unsupported OS detected; Docker install may still work."

  download_and_extract

  echo ""
  read -r -p "Prefix hostname (default: $PREFIX_DEFAULT): " prefix
  prefix="${prefix:-$PREFIX_DEFAULT}"

  read -r -p "App port (default: $PORT_DEFAULT): " port
  port="${port:-$PORT_DEFAULT}"

  write_config "$prefix" "$port"

  echo ""
  echo "Install method:"
  echo "  1) Docker (recommended)"
  echo "  2) Python (venv, no Docker)"
  read -r -p "Choose [1/2] (default 1): " choice
  choice="${choice:-1}"

  # Always provide no-admin URL that works everywhere:
  local fallback_url="http://127.0.0.1:${port}/"
  echo "Open:            http://127.0.0.1:${port}/"
  echo "Open (alt):      http://localhost:${port}/"

  # Start service
  if [[ "$choice" == "1" ]]; then
    has docker || die "docker not found."
    docker info >/dev/null 2>&1 || die "Docker is not running."
    run_docker
  elif [[ "$choice" == "2" ]]; then
    run_python
  else
    die "Invalid choice."
  fi

  maybe_pretty_url "$os" "$prefix" "$port"

  echo ""
  ok "Done."
  echo "Open (no admin): $fallback_url"
  echo "Config:          $CFG_FILE"
  echo "Data:            $DATA_DIR/vilinks.db"
  echo ""
}

main "$@"