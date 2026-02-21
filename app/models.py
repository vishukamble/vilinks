from __future__ import annotations

from typing import Optional

from .db import get_db


def get_all_links():
    with get_db() as conn:
        return conn.execute("SELECT * FROM links ORDER BY created_at DESC").fetchall()


def get_link(slug: str):
    with get_db() as conn:
        return conn.execute("SELECT * FROM links WHERE slug = ?", (slug,)).fetchone()


def create_link(slug: str, url: str, description: str = "") -> None:
    with get_db() as conn:
        conn.execute(
            "INSERT INTO links (slug, url, description) VALUES (?, ?, ?)",
            (slug, url, description),
        )


def update_link(slug: str, url: str, description: str = "") -> None:
    with get_db() as conn:
        conn.execute(
            "UPDATE links SET url=?, description=?, updated_at=CURRENT_TIMESTAMP WHERE slug=?",
            (url, description, slug),
        )


def delete_link(slug: str) -> None:
    with get_db() as conn:
        conn.execute("DELETE FROM links WHERE slug = ?", (slug,))


def record_hit(slug: str) -> None:
    with get_db() as conn:
        conn.execute(
            "UPDATE links SET hit_count=hit_count+1, last_hit_at=CURRENT_TIMESTAMP WHERE slug=?",
            (slug,),
        )


def get_stats() -> dict:
    with get_db() as conn:
        total_links = conn.execute("SELECT COUNT(*) AS c FROM links").fetchone()["c"]
        total_hits = conn.execute("SELECT COALESCE(SUM(hit_count),0) AS s FROM links").fetchone()["s"]
        latest_created = conn.execute(
            "SELECT created_at FROM links ORDER BY created_at DESC LIMIT 1"
        ).fetchone()
        latest_hit = conn.execute(
            "SELECT last_hit_at FROM links WHERE last_hit_at IS NOT NULL ORDER BY last_hit_at DESC LIMIT 1"
        ).fetchone()

    return {
        "total_links": int(total_links or 0),
        "total_hits": int(total_hits or 0),
        "latest_created": latest_created["created_at"] if latest_created else None,
        "latest_hit": latest_hit["last_hit_at"] if latest_hit else None,
    }
