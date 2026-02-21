#!/bin/bash
set -euo pipefail

DATA_DIR="${VILINKS_DATA_DIR:-$HOME/.vilinks}"
CFG_FILE="${VILINKS_CONFIG:-$DATA_DIR/config.env}"
PID_FILE="$DATA_DIR/vilinks.pid"
LOG_FILE="$DATA_DIR/vilinks.log"
VENV_DIR="$DATA_DIR/venv"

mkdir -p "$DATA_DIR"

# Load config if present
if [[ -f "$CFG_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$CFG_FILE"
  set +a
fi

PORT="${VILINKS_PORT:-8765}"
PREFIX="${VILINKS_PREFIX:-vi}"
export VILINKS_BASE_URL="${VILINKS_BASE_URL:-http://${PREFIX}.localhost:${PORT}/}"
export VILINKS_DB="${VILINKS_DB:-$DATA_DIR/vilinks.db}"

start() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "vilinks already running (pid $(cat "$PID_FILE"))"
    exit 0
  fi

  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "venv not found at $VENV_DIR. Use install.sh (Python mode) to create it."
    exit 1
  fi

  export VILINKS_BIND="${VILINKS_BIND:-127.0.0.1}"
  export VILINKS_PORT="$PORT"
  export VILINKS_PREFIX="$PREFIX"

  local repo_root
  repo_root="$(cd "$(dirname "$0")/.." && pwd)"

  nohup "$VENV_DIR/bin/python" "$repo_root/app.py" > "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  echo "vilinks started (pid $(cat "$PID_FILE"))"
  echo "Open: $VILINKS_BASE_URL"
}

stop() {
  if [[ -f "$PID_FILE" ]]; then
    PID="$(cat "$PID_FILE")"
    if kill -0 "$PID" 2>/dev/null; then
      kill "$PID" || true
      sleep 1
    fi
    rm -f "$PID_FILE"
    echo "vilinks stopped"
  else
    echo "vilinks not running"
  fi
}

status() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "running (pid $(cat "$PID_FILE"))"
  else
    echo "stopped"
  fi
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  status) status ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
  ;;
esac