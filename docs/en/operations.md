<div align="center">
  <a href="index.md">← Index</a> &nbsp;·&nbsp;
  <a href="../es/operations.md">🇪🇸 Ver en Español</a>
</div>

<br>

# Operations

Everything is managed with a single script from the project root.

---

## One-command installation

Choose the method that best fits your environment:

### 🐳 Linux / macOS with Docker (recommended for production)

```bash
curl -fsSL https://raw.githubusercontent.com/iagentshub/iagentshub/main/install.sh | bash
```

### 🍎 macOS without Docker

Automatically installs Python and git via Homebrew if not present. Uses SQLite as the database.

```bash
curl -fsSL https://raw.githubusercontent.com/iagentshub/iagentshub/main/install-local-mac.sh | bash
```

### 🪟 Windows without Docker

Automatically installs Python and git via winget if not present. Uses SQLite as the database. Run in PowerShell as Administrator:

```powershell
irm https://raw.githubusercontent.com/iagentshub/iagentshub/main/install-local-windows.ps1 | iex
```

> **Note:** The non-Docker modes use SQLite as the database. For production environments or high concurrency, the Docker mode with PostgreSQL is recommended.

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

To force a password reset, add `GAIA_ADMIN_RESET: "true"` to the `environment` block of the `backend` service in `docker-compose.dev.yml`, run `./gaia.sh update --dev`, and copy the password that appears. **Remove that line immediately afterwards** to prevent accidental resets on future restarts.

---

## Available commands

| Command | What it does |
|---|---|
| `start` | Builds and starts all services |
| `stop` | Stops the services |
| `update` | Downloads the latest version and restarts |
| `logs` | Shows live activity |
| `status` | Current status of the services |

---

## Execution modes

**Production mode** — the default behavior. Always downloads the latest version of each repository from GitHub before building. Recommended for real environments.

**Development mode** — activated with the `--dev` flag. Instead of downloading from GitHub, uses the developer's local repositories. Allows iterating without pushing every change.

---

## Private repositories

If your repositories are on GitHub with private access, add a personal access token to the configuration. The script injects it automatically when starting in production mode.

---

## Updating

The update command stops the services, downloads the latest code, and restarts them. Existing data is not affected.
