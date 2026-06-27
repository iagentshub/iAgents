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

## Workspaces and collaboration

### User roles

| Role | Description |
|------|-------------|
| `admin` | Full access to the administration panel and all resources. |
| `standard` | Normal user with access to their own resources. |
| `guest` | Temporary session without an account. Limited access. |

### Data model

Every user has a **personal workspace** (virtual — id = username, no DB row). Team workspaces have their own rows:

- **`workspaces`** — Name, creator, and creation date.
- **`workspace_members`** — User–workspace relationship with role (`owner` / `admin` / `member`).
- **`workspace_invitations`** — Username-based invitations with `pending` status.
- **`workspace_groups`** / **`workspace_group_members`** — Groups within a workspace for resource sharing.
- **`resource_groups`** — Resource–group relationship with permissions.

### Granular permissions

Permissions are managed at group level. The structure is per resource type with a default policy and overrides:

```json
{
  "agents":      { "default": "deny", "items": { "agent-id": { "use": true } } },
  "connections": { "default": "deny", "items": { "conn-id":  { "direct": false, "via_agent": true } } },
  "knowledge":   { "default": "deny", "items": { "know-id":  { "view": true } } }
}
```

### Invitation flow

1. The workspace owner invites a user from **Profile → Workspaces** by entering their username.
2. The invitee sees the invitation under **Profile → Workspaces → Invitations** and accepts or rejects it.
3. On acceptance, the user joins the workspace with the `member` role.

### Ownership transfer

An owner can transfer ownership to an existing member before deleting their account:
`POST /api/workspaces/{id}/transfer-ownership` with `{ "username": "new_owner" }`.

### GDPR — right to erasure

Users can request permanent account deletion from **Profile → Privacy**:

- 30-day grace period with a cancellation link sent by email.
- Workspace owners must transfer or delete their workspaces before requesting deletion.
- The purge cascades: messages, conversations, knowledge, connections, tokens, agents, skills, and the user account.
- Data export available at any time (`GET /api/auth/me/export` → ZIP).
