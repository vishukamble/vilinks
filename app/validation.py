import re
from urllib.parse import urlparse

SLUG_RE = re.compile(r"^[a-z0-9-]{2,40}$")
RESERVED = {"healthz", "static", "favicon.ico", "links", "help"}


def is_valid_slug(slug: str) -> bool:
    return bool(SLUG_RE.match(slug)) and slug not in RESERVED


def is_valid_url(url: str) -> bool:
    try:
        p = urlparse(url)
        return p.scheme in ("http", "https") and bool(p.netloc)
    except Exception:
        return False


def validate_link(slug: str, url: str):
    errors = []
    if not is_valid_slug(slug):
        errors.append("Alias must be 2–40 lowercase letters, numbers, or hyphens.")
    if not is_valid_url(url):
        errors.append("URL must start with http:// or https://")
    return errors
