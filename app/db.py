import os
import sqlite3

DEFAULT_DB = os.path.expanduser("~/.vilinks/vilinks.db")


def get_db_path() -> str:
    return os.environ.get("VILINKS_DB", DEFAULT_DB)

def get_db() -> sqlite3.Connection:
    db_path = get_db_path()
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    return conn