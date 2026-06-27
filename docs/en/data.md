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
| `settings.json` | Global instance configuration (JWT secret, SMTP, limits) |
| `hub.db` | Main SQLite database. Contains users, conversations, messages, connections (encrypted API keys), knowledge, workspaces, groups, and token usage. Replaced by PostgreSQL in production via `DATABASE_URL`. |
| `agents/` | Agent configurations as `config.json` files per scope (`private/` and `public/`) |
| `skills/` | Skills as `SKILL.md` files per scope (`private/` and `public/`) |
| `memory/` | Memory files per agent. Created and updated automatically after each conversation when the agent has memory enabled. |
| `logs/` | Daily log files (`YYYYMMDD.log`). Accessible from the admin panel → Logs. |

---

## Database

The main tables are:

| Table | Contents |
|---|---|
| `users` | Accounts, roles, password hash, GDPR tokens |
| `conversations` / `messages` | Chat history |
| `connections` | Provider credentials (API keys encrypted with AES) |
| `knowledge_folders` / `knowledge_items` | Knowledge documents and URLs |
| `workspaces` / `workspace_members` / `workspace_invitations` | Team workspaces and memberships |
| `workspace_groups` / `workspace_group_members` / `resource_groups` | Groups and shared permissions |
| `accounts` | Linked external accounts (Google, etc.) |
| `token_daily` | Daily token usage per provider |

Migrations are incremental and applied automatically on startup (`_migrate_sqlite` and `_migrate_pg` in `app/storage/db.py`).

---

## Data export (GDPR Art. 20)

Each user can download all their data from **Profile → Privacy → Download my data**. The ZIP file includes profile, connections, knowledge, full conversations, workspaces, token usage, agents, and skills.

---

## What is committed

Only `settings.json` is included in the repository as a default value. All other data is not committed: it contains installation-specific information that should not be shared.

---

## Persistence

The directory lives on the host filesystem and does not depend on the container lifecycle. To erase all platform data, delete the `data/` directory manually.
