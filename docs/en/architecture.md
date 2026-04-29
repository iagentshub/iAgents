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
