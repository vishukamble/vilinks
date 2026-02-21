#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}→${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $1"; }
die()     { echo -e "${RED}✗${NC} $1"; exit 1; }

[[ "$EUID" -eq 0 ]] && die "Do not run as root. Run as your normal user: ./scripts/install.sh"

echo ""
echo "  vilinks — local GoLinks-style shortener"
echo ""

default_host="vi"
read -p "Short hostname (so you type 'vi/' ) [${default_host}]: " SHORT_HOST
SHORT_HOST="${SHORT_HOST:-$default_host}"

if ! [[ "$SHORT_HOST" =~ ^[a-z][a-z0-9-]{1,30}$ ]]; then
  die "Invalid hostname '$SHORT_HOST'. Use lowercase letters/numbers/hyphens (2-31 chars)."
fi

default_port="8765"
read -p "App port [${default_port}]: " PORT
PORT="${PORT:-$default_port}"
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1024 || PORT > 65535 )); then
  die "Invalid port '$PORT'"
fi

DATA_DIR="$HOME/.vilinks"
mkdir -p "$DATA_DIR"

info "Choose install mode"
echo "  1) Docker (recommended)"
echo "  2) Native Python (venv in ~/.vilinks)"
read -p "Select [1/2]: " MODE
MODE="${MODE:-1}"

# Write .env for docker compose and for scripts
ENV_FILE="$REPO_DIR/.env"
cat > "$ENV_FILE" <<EOF
VILINKS_PORT=$PORT
VILINKS_BASE_HOST=$SHORT_HOST
VILINKS_DATA_DIR=$DATA_DIR
EOF
success "Wrote $ENV_FILE"

# Hosts entry
read -p "Add hosts entry '127.0.0.1 $SHORT_HOST' (needed for http://$SHORT_HOST/ )? [Y/n]: " ADD_HOSTS
ADD_HOSTS="${ADD_HOSTS:-Y}"
if [[ "$ADD_HOSTS" =~ ^[Yy]$ ]]; then
  info "Configuring /etc/hosts..."
  if grep -qE "^127\\.0\\.0\\.1[[:space:]]+$SHORT_HOST(\\s|$)" /etc/hosts 2>/dev/null; then
    success "Hosts entry already present"
  else
    echo "127.0.0.1 $SHORT_HOST" | sudo tee -a /etc/hosts > /dev/null
    success "Added hosts entry"
  fi
fi

# Port 80 forward (optional)
PORT80_BUSY=false
if lsof -i :80 -sTCP:LISTEN &>/dev/null 2>&1; then
  PORT80_BUSY=true
  warn "Port 80 is in use — you can still use http://$SHORT_HOST:$PORT/"
fi

read -p "Enable port-80 forward so http://$SHORT_HOST/ works (requires sudo)? [y/N]: " FORWARD80
FORWARD80="${FORWARD80:-N}"
if [[ "$FORWARD80" =~ ^[Yy]$ ]]; then
  if [[ "$PORT80_BUSY" == "true" ]]; then
    warn "Skipping port-80 forward because port 80 is busy."
  else
    if [[ "$(uname)" == "Darwin" ]]; then
      info "Setting up macOS pf redirect 80 -> $PORT"
      ANCHOR_FILE="/etc/pf.anchors/vilinks"
      sudo sh -c "echo 'rdr pass on lo0 proto tcp from any to 127.0.0.1 port 80 -> 127.0.0.1 port $PORT' > '$ANCHOR_FILE'"

      # Ensure pf.conf loads the anchor
      if ! sudo grep -q 'anchor "vilinks"' /etc/pf.conf; then
        info "Updating /etc/pf.conf (backup at /etc/pf.conf.vilinks.bak)"
        sudo cp /etc/pf.conf /etc/pf.conf.vilinks.bak
        sudo sh -c "printf '\n# vilinks\nanchor \"vilinks\"\nload anchor \"vilinks\" from \"/etc/pf.anchors/vilinks\"\n' >> /etc/pf.conf"
      fi

      sudo pfctl -f /etc/pf.conf >/dev/null
      sudo pfctl -e >/dev/null 2>&1 || true
      success "pf redirect enabled"

      warn "Note: pf rules may not survive reboot on some macOS setups. If you want persistence, create a LaunchDaemon (see README)."

    elif [[ "$(uname)" == "Linux" ]]; then
      info "Setting up Linux iptables redirect 80 -> $PORT"
      command -v iptables &>/dev/null || warn "iptables not found. Skipping port-80 forward." 
      if command -v iptables &>/dev/null; then
        sudo iptables -t nat -A OUTPUT     -p tcp -d 127.0.0.1 --dport 80 -j REDIRECT --to-port $PORT 2>/dev/null || true
        sudo iptables -t nat -A PREROUTING -p tcp              --dport 80 -j REDIRECT --to-port $PORT 2>/dev/null || true
        success "iptables redirect configured"
        warn "Persistence varies by distro; you may need iptables-persistent / nftables rules for reboot survival."
      fi
    else
      warn "Unknown OS, skipping port-80 forward."
    fi
  fi
fi

# Install + start
if [[ "$MODE" == "1" ]]; then
  info "Checking Docker..."
  command -v docker &>/dev/null || die "Docker not found. Install Docker Desktop / Engine first."
  docker info &>/dev/null || die "Docker is not running. Start it first."
  (docker compose version >/dev/null 2>&1) || die "docker compose not found. Update Docker / Compose."

  info "Building + starting container..."
  cd "$REPO_DIR"
  docker compose up -d --build
  success "vilinks container is running"

elif [[ "$MODE" == "2" ]]; then
  info "Setting up native Python venv in $DATA_DIR/venv"
  command -v python3 &>/dev/null || die "python3 not found"
  python3 -m venv "$DATA_DIR/venv"
  "$DATA_DIR/venv/bin/pip" install -r "$REPO_DIR/requirements.txt" >/dev/null
  success "Dependencies installed"

  info "Starting vilinks"
  VILINKS_PORT="$PORT" VILINKS_BASE_HOST="$SHORT_HOST" VILINKS_DATA_DIR="$DATA_DIR" "$REPO_DIR/scripts/run.sh" start
else
  die "Unknown mode"
fi

# Verify
info "Verifying..."
if curl -sf "http://localhost:$PORT/healthz" &>/dev/null; then
  success "vilinks is up"
else
  warn "Still starting — check logs"
  if [[ "$MODE" == "1" ]]; then
    echo "  docker compose logs -f"
  else
    echo "  tail -f $DATA_DIR/vilinks.log"
  fi
fi

echo ""
echo -e "  ${GREEN}vilinks installed!${NC}"
if [[ "$PORT80_BUSY" == "true" || ! "$FORWARD80" =~ ^[Yy]$ ]]; then
  echo "  → http://$SHORT_HOST:$PORT/"
else
  echo "  → http://$SHORT_HOST/"
fi

echo ""
