#!/usr/bin/env bash
set -euo pipefail

RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; GREEN=$'\033[0;32m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'
info(){ echo "${CYAN}→${NC} $*"; }
ok(){ echo "${GREEN}✓${NC} $*"; }
warn(){ echo "${YELLOW}⚠${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DATA_DIR="${VILINKS_DATA_DIR:-$HOME/.vilinks}"
CFG_FILE="${VILINKS_CONFIG:-$DATA_DIR/config.env}"
PREFIX="${VILINKS_PREFIX:-vi}"
PORT="${VILINKS_PORT:-8765}"

# Load config if present
if [[ -f "$CFG_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$CFG_FILE" || true
  set +a
  PREFIX="${VILINKS_PREFIX:-$PREFIX}"
  PORT="${VILINKS_PORT:-$PORT}"
fi

echo ""
echo "  vilinks uninstaller"
echo ""

# Stop docker
if command -v docker &>/dev/null; then
  info "Stopping docker (if running)..."
  (cd "$REPO_DIR" && docker compose down) >/dev/null 2>&1 || true
  ok "Docker stopped (if it was running)"
fi

# Stop native
if [[ -x "$REPO_DIR/scripts/run.sh" ]]; then
  info "Stopping native vilinks (if running)..."
  "$REPO_DIR/scripts/run.sh" stop >/dev/null 2>&1 || true
fi

# Remove port forward
if [[ "$(uname)" == "Darwin" ]]; then
  info "Removing macOS pf redirect + LaunchDaemon (if present)..."
  sudo rm -f /etc/pf.anchors/vilinks 2>/dev/null || true
  sudo rm -f /Library/LaunchDaemons/com.vilinks.portforward.plist 2>/dev/null || true

  if sudo grep -q 'pf.anchors/vilinks' /etc/pf.conf 2>/dev/null; then
    sudo cp /etc/pf.conf /etc/pf.conf.vilinks.uninstall.bak
    # delete the 3 lines we added
    sudo sed -i '' '/# vilinks/d;/rdr-anchor "vilinks"/d;/pf\.anchors\/vilinks/d' /etc/pf.conf 2>/dev/null || true
    sudo pfctl -f /etc/pf.conf >/dev/null 2>&1 || true
  fi
  ok "macOS port forward removed"

elif [[ "$(uname)" == "Linux" ]]; then
  info "Removing iptables redirect (if present)..."
  if command -v iptables &>/dev/null; then
    sudo iptables -t nat -D OUTPUT     -p tcp -d 127.0.0.1 --dport 80 -j REDIRECT --to-port "$PORT" 2>/dev/null || true
    sudo iptables -t nat -D PREROUTING -p tcp              --dport 80 -j REDIRECT --to-port "$PORT" 2>/dev/null || true
  fi
  ok "Linux port forward removed"
fi

# Remove hosts entry
info "Removing /etc/hosts entry for $PREFIX..."
if grep -qE "^127\.0\.0\.1[[:space:]]+$PREFIX(\s|$)" /etc/hosts 2>/dev/null; then
  sudo cp /etc/hosts /etc/hosts.vilinks.bak
  if [[ "$(uname)" == "Darwin" ]]; then
    sudo sed -i '' "/^127\.0\.0\.1[[:space:]]\+$PREFIX\(\s\|$\)/d" /etc/hosts
  else
    sudo sed -i "/^127\.0\.0\.1[[:space:]]\+$PREFIX\(\s\|$\)/d" /etc/hosts
  fi
  ok "Hosts entry removed"
else
  ok "Hosts entry not present"
fi

echo ""
ok "vilinks removed"
echo "Data preserved at: $DATA_DIR"
echo "To fully wipe: rm -rf $DATA_DIR"
echo ""