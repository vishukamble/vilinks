# vilinks

A tiny, local-first GoLinks-style URL shortener you can run on your own machine.

- Type `http://vi/anything` (optional port-80 forward) → redirects to the full URL
- Web UI to **create / edit / delete** links
- SQLite storage in `~/.vilinks/`
- Works with **Docker** or **native Python**

> Default short hostname is `vi` (so you type `vi/`). You can pick a different one during install.

## Quick start (macOS / Linux)

```bash
curl -fsSL -o /tmp/vilinks-install.sh https://raw.githubusercontent.com/vishukamble/vilinks/main/install.sh \
  && bash /tmp/vilinks-install.sh
```

## Quick start (Windows)

Open PowerShell **as Administrator** (recommended for `http://vi/`), then:

```powershell
powershell -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/vishukamble/vilinks/main/install.ps1 | iex"
```

If you don't run as admin, you'll still be able to use `http://vi.localhost:8765/`.

## Where data lives

- DB: `~/.vilinks/vilinks.db`
- Config: `~/.vilinks/config.env`

## CLI-ish operations

- Backup:
  ```bash
  ./scripts/backup.sh
  ```
- Restore:
  ```bash
  ./scripts/restore.sh path/to/backup.json
  ```

## Development

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

Then open `http://localhost:8765/`.

## License

MIT (see `LICENSE`).
