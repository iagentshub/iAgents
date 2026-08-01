<div align="center">
  <a href="index.md">← Index</a> &nbsp;·&nbsp;
  <a href="../es/operations.md">🇪🇸 Ver en Español</a>
</div>

<br>

# Operations

Installation is a single script per OS (`install.sh` / `install.ps1`) and day-to-day management is **a single cross-platform Python script** (`gaia.py`, no external dependencies — the same file on Linux, macOS and Windows) from the project root.

---

## One-command installation

One URL per operating system. The script installs the full platform (FastAPI
backend plus React frontend) and asks for the **mode**: Docker
(recommended, includes optional PostgreSQL) or without Docker (Python/Node
directly, SQLite).

The same command installs and updates. After the first installation, the
installer records both the selected mode and components and reuses them
automatically. It can install the full application, the backend only, or the
frontend only. A frontend-only installation asks for the remote backend URL
and keeps `/api` on the same origin through a reverse proxy.

### 🐳🐧🍎 Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/iagentshub/iAgents/main/install.sh | bash
```

### 🪟 Windows

Run in PowerShell (as Administrator if you pick the non-Docker mode, so it can install dependencies via winget):

```powershell
irm https://raw.githubusercontent.com/iagentshub/iAgents/main/install.ps1 | iex
```

### Installer help

```bash
bash install.sh --help
```
```powershell
# Download the script first — "irm ... | iex" can't pass arguments
irm https://raw.githubusercontent.com/iagentshub/iAgents/main/install.ps1 -OutFile install.ps1
powershell -File install.ps1 --help
```

### Skipping the prompts (CI / non-interactive reinstall)

```bash
IAGENTSHUB_MODE=docker bash install.sh
IAGENTSHUB_MODE=local IAGENTSHUB_COMPONENT=backend bash install.sh
IAGENTSHUB_MODE=docker IAGENTSHUB_COMPONENT=frontend \
  IAGENTSHUB_API_URL=https://api.example.com bash install.sh
```
```powershell
$env:IAGENTSHUB_MODE = "docker"
$env:IAGENTSHUB_COMPONENT = "backend"
irm https://raw.githubusercontent.com/iagentshub/iAgents/main/install.ps1 | iex
```

> **Note:** The non-Docker mode uses SQLite as the database. For production environments or high concurrency, the Docker mode with PostgreSQL is recommended.

---

## First launch (with cloned repository)

Clone the repository, copy the example configuration file, fill in the required values, and run the startup script. The platform will be available at `http://localhost` when it finishes.

The backend automatically creates an administrator account the first time it starts. The script always prints the credentials when `start` or `update` finishes:

```
  ╔══════════════════════════════════════════╗
  ║       Acceso de administrador            ║
  ╠══════════════════════════════════════════╣
  ║  Email      › admin@example.com
  ║  Contraseña › (sin cambios)
  ╚══════════════════════════════════════════╝
```

If a new password was generated (first startup or forced reset), it appears in the _Contraseña_ field. Otherwise _(sin cambios)_ is shown.

To force a password reset, add `GAIA_ADMIN_RESET: "true"` to the `environment` block of the `backend` service in `docker-compose.dev.yml`, run `python3 gaia.py update --dev`, and copy the password that appears. **Remove that line immediately afterwards** to prevent accidental resets on future restarts.

---

## Help and available commands

```bash
python3 gaia.py --help              # Docker (or whichever mode via --local/--hub/--dev)
python3 gaia.py --help --local      # help specific to the non-Docker mode
```

On Windows: `python gaia.py --help` (same file, same syntax).

| Command | What it does |
|---|---|
| `start` | Builds and starts all services |
| `stop` | Stops the services |
| `restart` | Stops and starts the services again (no new download) |
| `update` | Downloads the latest version and restarts *(Docker only)* |
| `logs` | Shows live activity |
| `status` | Current status of the services |
| `push` | Builds the unified React image and pushes it to GitHub Container Registry *(Docker only)* |
| `reset` | Wipes the database and all data, and reinstalls from scratch *(asks for confirmation)* |

---

## Execution modes

**Production mode** — the default behavior (no flags). Always downloads the latest version of each repository from GitHub before building. Recommended for real environments.

**Development mode** (`--dev`) — uses the developer's local repositories (`../backend_fastapi` and `../frontend_react`) instead of downloading from GitHub. Allows iterating without pushing every change.

**Hub mode** (`--hub`) — uses the pre-built unified React image from GitHub Container Registry (backend + frontend in a single container). The tag is controlled by `IMAGE_TAG` in `.env`.

**Local mode** (`--local`) — no Docker: uvicorn plus a Python proxy serve the React app (SQLite). `gaia.py` runs `npm run build` when `dist/` is missing or dependencies change, then serves the static output.

---

## Publishing the unified images (`push`)

```bash
python3 gaia.py push  # build and push ghcr.io/iagentshub/app:latest
```

In production, CI publishes the unified React image with `:latest` and an immutable version tag.

---

## Fresh install (`reset`)

Completely wipes the database (users, agents, skills, encrypted connections, chats, memory) and reinstalls from scratch. This is **irreversible** — the script requires typing `RESET` to confirm, unless `--yes` is passed (useful for scripts, but use with care: it doesn't distinguish environments).

```bash
python3 gaia.py reset            # Docker: docker compose down -v + start (wipes all volumes)
python3 gaia.py reset --dev      # same, in development mode
python3 gaia.py reset --hub      # same, in Hub mode
python3 gaia.py reset --local    # wipes ../iagentshub/data/ and reinstalls
```

> ⚠️ The default compose (no flags) is the one a typical production deployment uses. Running `reset` there wipes real data — double-check which server/directory you're in before confirming.

---

## Private repositories

If your repositories are on GitHub with private access, add a personal access token to the configuration. The script injects it automatically when starting in production mode.

---

## Updating

The update command stops the services, downloads the latest code, and restarts them. Existing data is not affected.
