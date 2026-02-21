import os
import sqlite3

DB_PATH = os.environ.get(
    "VILINKS_DB",
    os.path.expanduser("~/.vilinks/vilinks.db"),
)


def get_db() -> sqlite3.Connection:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    with get_db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS links (
                slug        TEXT PRIMARY KEY,
                url         TEXT NOT NULL,
                description TEXT DEFAULT '',
                hit_count   INTEGER DEFAULT 0,
                created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
                last_hit_at DATETIME
            );

            CREATE INDEX IF NOT EXISTS idx_links_created_at ON links(created_at);
            """
        )
