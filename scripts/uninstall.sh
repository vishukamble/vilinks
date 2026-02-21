#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}→${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $1"; }

echo ""
echo "  vilinks uninstaller"
echo ""

# Best-effort read host/port from .env
SHORT_HOST="vi"
PORT="8765"
if [[ -f "$REPO_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$REPO_DIR/.env" || true
  SHORT_HOST="${VILINKS_BASE_HOST:-$SHORT_HOST}"
  PORT="${VILINKS_PORT:-$PORT}"
fi

DATA_DIR="${VILINKS_DATA_DIR:-$HOME/.vilinks}"

# Stop docker container if present
if command -v docker &>/dev/null; then
  if docker ps --format '{{.Names}}' | grep -q '^vilinks$' 2>/dev/null; then
    info "Stopping docker container..."
    docker stop vilinks >/dev/null || true
    docker rm vilinks >/dev/null || true
    success "Container removed"
  fi
  if [[ -f "$REPO_DIR/docker-compose.yml" ]]; then
    (cd "$REPO_DIR" && docker compose down) >/dev/null 2>&1 || true
  fi
fi

# Stop native if running
if [[ -f "$DATA_DIR/vilinks.pid" ]]; then
  info "Stopping native vilinks..."
  "$REPO_DIR/scripts/run.sh" stop >/dev/null 2>&1 || true
fi

# Remove port forward
if [[ "$(uname)" == "Darwin" ]]; then
  info "Removing macOS pf redirect (if present)..."
  sudo rm -f /etc/pf.anchors/vilinks 2>/dev/null || true
  if sudo grep -q '# vilinks' /etc/pf.conf 2>/dev/null; then
    sudo cp /etc/pf.conf /etc/pf.conf.vilinks.uninstall.bak
    sudo sed -i '' '/# vilinks/,+2d' /etc/pf.conf 2>/dev/null || true
    sudo pfctl -f /etc/pf.conf >/dev/null 2>&1 || true
  fi
  success "pf cleanup done"

elif [[ "$(uname)" == "Linux" ]]; then
  info "Removing iptables redirect (if present)..."
  if command -v iptables &>/dev/null; then
    sudo iptables -t nat -D OUTPUT     -p tcp -d 127.0.0.1 --dport 80 -j REDIRECT --to-port "$PORT" 2>/dev/null || true
    sudo iptables -t nat -D PREROUTING -p tcp              --dport 80 -j REDIRECT --to-port "$PORT" 2>/dev/null || true
  fi
  success "iptables cleanup done"
fi

# Remove hosts entry
info "Removing /etc/hosts entry for $SHORT_HOST..."
if grep -qE "^127\\.0\\.0\\.1[[:space:]]+$SHORT_HOST(\\s|$)" /etc/hosts 2>/dev/null; then
  sudo cp /etc/hosts /etc/hosts.vilinks.bak
  sudo sed -i.bak "/^127\\.0\\.0\\.1[[:space:]]\+$SHORT_HOST\(\s\|$\)/d" /etc/hosts
  success "Hosts entry removed"
else
  success "Hosts entry not present"
fi

echo ""
success "vilinks removed"
echo "Data preserved at: $DATA_DIR"
echo "To fully wipe: rm -rf $DATA_DIR"
echo ""
