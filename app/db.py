import os
import sqlite3

DEFAULT_DB = os.path.expanduser(r"~/.vilinks/vilinks.db")


def get_db_path() -> str:
    return os.environ.get("VILINKS_DB", DEFAULT_DB)


def get_db() -> sqlite3.Connection:
    db_path = get_db_path()
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    # Better concurrent behavior
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
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
            CREATE INDEX IF NOT EXISTS idx_links_last_hit_at ON links(last_hit_at);
            """
        )