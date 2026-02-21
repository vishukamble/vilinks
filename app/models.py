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


def get_stats():
    with get_db() as conn:
        row = conn.execute(
            """
            SELECT
              (SELECT COUNT(*) FROM links) AS total_links,
              (SELECT COALESCE(SUM(hit_count), 0) FROM links) AS total_hits,
              (SELECT MAX(created_at) FROM links) AS latest_created,
              (SELECT MAX(last_hit_at) FROM links) AS latest_hit
            """
        ).fetchone()

        return {
            "total_links": row["total_links"],
            "total_hits": row["total_hits"],
            "latest_created": row["latest_created"],
            "latest_hit": row["latest_hit"],
        }