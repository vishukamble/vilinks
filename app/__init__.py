import os
from pathlib import Path
from flask import Flask

from .db import init_db
from .routes import bp

ROOT = Path(__file__).resolve().parent.parent  # repo root (where templates/ and static/ live)

def create_app() -> Flask:
    app = Flask(
        __name__,
        template_folder=str(ROOT / "templates"),
        static_folder=str(ROOT / "static"),
        static_url_path="/static",
    )

    init_db()

    prefix = os.environ.get("VILINKS_PREFIX", "vi")
    port = int(os.environ.get("VILINKS_PORT", "8765"))
    base_url = os.environ.get("VILINKS_BASE_URL", f"http://{prefix}.localhost:{port}/")

    @app.context_processor
    def inject_globals():
        return {
            "prefix": prefix,
            "prefix_slash": f"{prefix}/",
            "base_url": base_url.rstrip("/") + "/",
            "port": port,
        }

    app.register_blueprint(bp)
    return app