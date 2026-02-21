import os

from flask import Flask

from .db import init_db
from .routes import bp


def create_app() -> Flask:
    app = Flask(__name__)

    # Ensure DB exists
    init_db()

    # Template globals
    base_host = os.environ.get("VILINKS_BASE_HOST", "vi")

    @app.context_processor
    def inject_globals():
        return {
            "BASE_HOST": base_host,
            "BASE_PREFIX": f"{base_host}/",
        }

    app.register_blueprint(bp)
    return app
