#!/bin/bash
set -euo pipefail

DATA_DIR="${VILINKS_DATA_DIR:-$HOME/.vilinks}"
CFG_FILE="${VILINKS_CONFIG:-$DATA_DIR/config.env}"

if [[ -f "$CFG_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$CFG_FILE"
  set +a
fi

DB="${VILINKS_DB:-$DATA_DIR/vilinks.db}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${1:-vilinks-backup-$TIMESTAMP.json}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${CYAN}→${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
die()     { echo -e "${RED}✗${NC} $1"; exit 1; }

[[ -f "$DB" ]] || die "No database found at $DB — start vilinks at least once."

info "Backing up from $DB..."

python3 - "$DB" "$BACKUP_FILE" << 'PYEOF'
import sys, sqlite3, json
from datetime import datetime, timezone

db_path, out_path = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
rows = conn.execute("SELECT * FROM links ORDER BY created_at ASC").fetchall()
conn.close()

data = {
    "version": 1,
    "exported_at": datetime.now(timezone.utc).isoformat(),
    "count": len(rows),
    "links": [dict(r) for r in rows],
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)

print(f"Exported {len(rows)} links")
PYEOF

success "Backup saved → $BACKUP_FILE"