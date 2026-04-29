<div align="center">
  <a href="index.md">← Index</a> &nbsp;·&nbsp;
  <a href="../es/config.md">🇪🇸 Ver en Español</a>
</div>

<br>

# Configuration

Configuration is set in an environment variables file at the project root. Copy the example file and fill in the required values before the first startup. This file is never committed to version control.

---

## What can be configured

| Setting | Description |
|---|---|
| Public port | The port on which the platform is accessible from a browser. Defaults to 80. |
| Session secret | Key used to sign session tokens. Required in production. |
| CORS origins | Domains allowed to access the API. |
| Repositories | URLs of the backend, frontend, and skills repositories. |
| GitHub token | Required to access private repositories. |
| Skills language | The language in which skills are served (`es` or `en`). |
| Local paths (dev) | Paths to local repositories for development mode. |

---

## Session secret

Must be generated randomly before the first startup and not changed while sessions are active. If not set, the system uses a fallback value stored in the platform data — acceptable in development, not in production.

---

## Private repositories

The code repositories (backend, frontend, skills) can be hosted privately on GitHub. Add a personal access token with read permission to the configuration. The startup script injects it automatically and transparently.
