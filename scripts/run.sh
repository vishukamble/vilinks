#!/bin/bash
set -e

DATA_DIR="${VILINKS_DATA_DIR:-$HOME/.vilinks}"
PORT="${VILINKS_PORT:-8765}"
BASE_HOST="${VILINKS_BASE_HOST:-vi}"
PID_FILE="$DATA_DIR/vilinks.pid"
LOG_FILE="$DATA_DIR/vilinks.log"
VENV_DIR="$DATA_DIR/venv"

mkdir -p "$DATA_DIR"

start() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "vilinks already running (pid $(cat "$PID_FILE"))"
    exit 0
  fi
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "venv not found at $VENV_DIR. Run ./scripts/install.sh and choose Native Python."
    exit 1
  fi

  export VILINKS_BIND=127.0.0.1
  export VILINKS_PORT="$PORT"
  export VILINKS_BASE_HOST="$BASE_HOST"
  export VILINKS_DB="$DATA_DIR/vilinks.db"

  nohup "$VENV_DIR/bin/python" "$(cd "$(dirname "$0")/.." && pwd)/app.py" \
    > "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  echo "vilinks started (pid $(cat "$PID_FILE"))"
}

stop() {
  if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
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
