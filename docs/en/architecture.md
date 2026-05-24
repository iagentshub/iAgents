<div align="center">
  <a href="index.md">← Index</a> &nbsp;·&nbsp;
  <a href="../es/architecture.md">🇪🇸 Ver en Español</a>
</div>

<br>

# Global Architecture

iAgentsHub is made up of four independent repositories that work together as a single system.

---

## The four repositories

| Repository | Role |
|---|---|
| **iagentshub** | Orchestrator. Contains the deployment configuration and the startup script. |
| **backend** | The core service. Manages agents, skills, memory, and AI provider connections. |
| **frontend** | The web interface. Allows creating and managing agents from a browser. |
| **skills** | The skills catalog. A collection of reusable capabilities that agents can use. |

The `iagentshub` repository is the only one users need to clone. The rest are obtained automatically when deploying.

---

## How they fit together at runtime

When the platform starts, the following happens in order:

1. Images for the backend and frontend are built from their repositories.
2. An initialization service prepares the data structure, generates the initial configuration, and syncs skills from the skills repository.
3. The backend starts once initialization completes successfully.
4. The frontend starts and begins serving the web interface.

The frontend acts as the single entry point: it serves the interface and transparently forwards requests to the backend.

---

## Production mode and development mode

The platform can start in two modes:

**Production mode** — always downloads the latest version of each repository from GitHub before building. Ensures the environment reflects the current state of the remote repositories.

**Development mode** — uses the developer's local repositories instead of downloading from GitHub. Allows iterating quickly without pushing every change.

In both modes the platform behaves identically. The only difference is the source of the code.

---

## Content repositories vs. code repositories

The backend and frontend are **code repositories**: their evolution follows conventional development cycles with reviews and releases.

Skills and agents are **content repositories**: their content can be modified by any contributor, changes are visible immediately, and the history faithfully tracks which capabilities exist and when they were added.

This separation allows managing content with the same traceability as code, without mixing functional changes with editorial changes.

---

## Data persistence

All platform data — configuration, agents, memory, API keys, skills — is stored in the `data/` directory on the host. This directory survives restarts, updates, and rebuilds.

Skills are synced on every startup from the skills repository. All other data is preserved between startups without manual intervention.

---

## Active agent memory

When an agent has memory enabled, the system automatically creates and maintains a memory file for that agent. After each conversation, the backend updates that file with the relevant facts extracted from the dialogue: user preferences, project context, decisions made, and any information the agent should recall in future sessions.

In the next conversation, the contents of that file are automatically incorporated into the agent’s context, with no user intervention required.

---

## Team system

### User roles

| Role | Description |
|------|-------------|
| `admin` | Full access to the administration panel and all resources. |
| `gestor` | Can create teams, invite members, and define granular permissions over their resources. |
| `standard` | Normal user with access to their own resources. Promoted to `gestor` upon creating their first team. |
| `guest` | Temporary session without an account. Limited access. |

A `standard` user is automatically promoted to `gestor` when they create a team. If they delete all teams they manage, they revert to `standard`.

### Data model

Three additional database tables manage teams:

- **`teams`** — Team name, creator, and creation date.
- **`team_members`** — User–team relationship with a manager flag and granular JSON permissions.
- **`team_invitations`** — Email invitations with status (`pending` / `accepted` / `rejected` / `expired`) and configurable expiry (48 h by default).

### Granular permissions

Each member’s permissions are stored as JSON in `team_members.permissions`. The structure is per resource type (`agents`, `connections`, `knowledge`) with a default policy (`deny` or `allow`) and per-resource overrides:

```json
{
  "agents":      { "default": "deny", "items": { "agent-id": { "use": true } } },
  "connections": { "default": "deny", "items": { "conn-id":  { "direct": false, "via_agent": true } } },
  "knowledge":   { "default": "deny", "items": { "know-id":  { "view": true } } }
}
```

Connections have two independent permission axes:
- `direct` — the member can see and use the connection directly from the Connections page.
- `via_agent` — when an allowed agent invokes this connection, access is permitted even if `direct` is `false`.

### Invitation flow

1. The manager sends an invitation from the panel (`/manager/`) → the system generates a token and sends an email with a link to `/profile/?tab=teams&token=…`.
2. The invited user sees the invitation in **Profile → Teams** and accepts or rejects it.
3. On acceptance, the user joins the team with empty permissions (default `deny` policy).
4. The manager adjusts permissions from the modal in their panel.

### Manager panel

Managers have a dedicated panel at `/manager/` with two tabs:

- **Team** — member table with actions (edit permissions, make manager, remove).
- **Invitations** — send new invitations and cancel pending ones.

The panel appears in the sidebar navigation only when `role === ‘gestor’` or `manages_teams === true` in the `/api/auth/me` response.
