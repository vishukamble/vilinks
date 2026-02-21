import os
from app import create_app

app = create_app()

if __name__ == "__main__":
    host = os.environ.get("VILINKS_BIND", "127.0.0.1")
    port = int(os.environ.get("VILINKS_PORT", "8765"))
    app.run(host=host, port=port, debug=False)