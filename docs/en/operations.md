<div align="center">
  <a href="index.md">← Index</a> &nbsp;·&nbsp;
  <a href="../es/operations.md">🇪🇸 Ver en Español</a>
</div>

<br>

# Operations

Installation is a single script per OS (`install.sh` / `install.ps1`) and day-to-day management is **a single cross-platform Python script** (`gaia.py`, no external dependencies — the same file on Linux, macOS and Windows) from the project root.

---

## One-command installation

One URL per operating system. The script interactively asks:

1. **Frontend** — Vanilla (static, no build) or React (SPA, requires Node.js).
2. **Mode** — Docker (recommended, includes optional PostgreSQL) or without Docker (Python/Node directly, SQLite).

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
IAGENTSHUB_FRONTEND=vanilla IAGENTSHUB_MODE=docker bash install.sh
```
```powershell
$env:IAGENTSHUB_FRONTEND = "vanilla"; $env:IAGENTSHUB_MODE = "docker"
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
| `push` | Builds the unified images (both variants by default) and pushes them to Docker Hub *(Docker only)* |

---

## Execution modes

**Production mode** — the default behavior (no flags). Always downloads the latest version of each repository from GitHub before building. Recommended for real environments.

**Development mode** (`--dev`) — uses the developer's local repositories (`../backend_fastapi`, `../frontend_vanilla` or `../frontend_react` via profile) instead of downloading from GitHub. Allows iterating without pushing every change.

**Hub mode** (`--hub`) — uses the pre-built unified image from Docker Hub (backend + frontend in a single container). This is the mode `install.sh` uses on the Docker branch. The image tag (`latest`=React, `vanilla`=Vanilla) is controlled by `IMAGE_TAG` in `.env`.

**Local mode** (`--local`) — no Docker: uvicorn plus a Python proxy serve the app (SQLite). Which frontend gets served (Vanilla or React) is controlled by `GAIA_FRONTEND_VARIANT` in `.env`; if it's `react`, `gaia.py` runs `npm run build` the first time (or whenever `dist/` is missing) and serves that output as static files — there's no persistent Vite server.

---

## Publishing the unified images (`push`)

```bash
python3 gaia.py push                      # build and push ALL variants: :latest and :vanilla
python3 gaia.py push --frontend=vanilla   # limit the build/push to iagenthub/app:vanilla
python3 gaia.py push --frontend=react     # limit the build/push to iagenthub/app:latest
```

In production (CI), each frontend independently publishes its own variant of the unified image: `frontend_vanilla`'s workflow publishes `:vanilla` and `frontend_react`'s publishes `:latest`.

---

## Private repositories

If your repositories are on GitHub with private access, add a personal access token to the configuration. The script injects it automatically when starting in production mode.

---

## Updating

The update command stops the services, downloads the latest code, and restarts them. Existing data is not affected.
