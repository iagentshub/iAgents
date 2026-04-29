<div align="center">
  <a href="index.md">← Index</a> &nbsp;·&nbsp;
  <a href="../es/data.md">🇪🇸 Ver en Español</a>
</div>

<br>

# Data

All platform data is stored in the `data/` directory on the host. This directory is created and initialized automatically on the first startup and survives restarts, updates, and rebuilds.

---

## What it contains

| Path | Contents |
|---|---|
| `settings.json` | Global instance configuration (theme, language, fallback secret) |
| `users.json` | User accounts created through authentication |
| `agents/` | Agent configurations (instructions, personality, assigned skills) |
| `connections/` | API keys for AI providers |
| `memory/` | Memory accumulated by each agent between conversations |
| `skills/` | Skills synced from the skills repository on every startup |

---

## What is committed

Only `settings.json` is included in the repository as a default value. All other data is not committed: it contains installation-specific information that should not be shared.

---

## Persistence

The directory lives on the host filesystem and does not depend on the container lifecycle. To erase all platform data, delete the `data/` directory manually.
