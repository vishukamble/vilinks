#!/bin/bash
set -e

DB="${VILINKS_DB:-$HOME/.vilinks/vilinks.db}"
BACKUP_FILE="$1"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${CYAN}→${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $1"; }
die()     { echo -e "${RED}✗${NC} $1"; exit 1; }

[[ -n "$BACKUP_FILE" ]] || die "Usage: ./restore.sh <backup-file.json>"
[[ -f "$BACKUP_FILE" ]] || die "Backup file not found: $BACKUP_FILE"

mkdir -p "$(dirname "$DB")"

python3 - <<PY
import sqlite3
conn = sqlite3.connect("$DB")
conn.executescript('''
CREATE TABLE IF NOT EXISTS links (
  slug TEXT PRIMARY KEY,
  url TEXT NOT NULL,
  description TEXT DEFAULT '',
  hit_count INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_hit_at DATETIME
);
''')
conn.close()
PY

echo ""
python3 - "$BACKUP_FILE" << 'PYEOF'
import sys, json
with open(sys.argv[1], encoding='utf-8') as f:
    data = json.load(f)
print(f"  Backup from : {data.get('exported_at', 'unknown')}")
print(f"  Links       : {data.get('count', '?')}")
print(f"  File        : {sys.argv[1]}")
PYEOF
echo ""

read -p "  Mode — (m)erge keep existing / (r)eplace wipe first [m/r, default m]: " MODE
MODE="${MODE:-m}"

if [[ "$MODE" == "r" || "$MODE" == "R" ]]; then
  warn "Replace mode — all existing links will be deleted"
  read -p "  Are you sure? [y/N]: " CONFIRM
  [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]] || { echo "Aborted."; exit 0; }
fi

info "Restoring..."

python3 - "$DB" "$BACKUP_FILE" "$MODE" << 'PYEOF'
import sys, sqlite3, json

db_path, backup_path, mode = sys.argv[1], sys.argv[2], sys.argv[3].lower()

with open(backup_path, encoding='utf-8') as f:
    data = json.load(f)

links = data.get('links', [])
conn = sqlite3.connect(db_path)

if mode == 'r':
    conn.execute('DELETE FROM links')
    conn.commit()
    print('  Cleared existing links')

inserted = skipped = 0
for link in links:
    try:
        conn.execute(
            """
            INSERT INTO links (slug, url, description, hit_count, created_at, updated_at, last_hit_at)
            VALUES (:slug, :url, :description, :hit_count, :created_at, :updated_at, :last_hit_at)
            """,
            link,
        )
        inserted += 1
    except sqlite3.IntegrityError:
        skipped += 1

conn.commit()
conn.close()
print(f"  Inserted : {inserted}")
print(f"  Skipped  : {skipped} (duplicate slugs)")
PYEOF

success "Restore complete → $DB"

# If docker compose is running, restart it so you see new data immediately
if command -v docker &>/dev/null; then
  if docker ps --format '{{.Names}}' | grep -q '^vilinks$' 2>/dev/null; then
    info "Restarting container..."
    docker restart vilinks >/dev/null
    success "Container restarted"
  fi
fi
