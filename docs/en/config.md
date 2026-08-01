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

## Initial administrator

On first startup, if no user with the `admin` role exists, the backend creates one automatically and prints the credentials to the service logs:

```
docker logs iagentshub-backend-1 2>&1 | grep -A6 "Administrador"
```

The variables controlling this behaviour are:

| Variable | Default | Description |
|---|---|---|
| `GAIA_ADMIN_EMAIL` | `admin@localhost.com` | Email (and username) for the initial admin account. |
| `GAIA_ADMIN_RESET` | *(empty)* | Set to `true` to reset the admin password on the next startup. **Remove after use.** |

---

## Account registration

| Variable | Options | Description |
|---|---|---|
| `GAIA_REGISTRATION` | `open` / `closed` / `invite` | Controls who can create new accounts. `invite` (default) requires an administrator to create accounts manually. |
| `GAIA_EMAIL_VERIFY` | `false` / `true` | If `true`, new users receive a verification email before they can log in. Requires SMTP configuration (pending). |

---

## Frontend image

| Variable | Options | Description |
|---|---|---|
| `IMAGE_TAG` | `latest` / any React tag | Docker Hub mode only (`--hub`). Which unified React image version to pull. |

---

## Session secret

Must be generated randomly before the first startup and not changed while sessions are active. If not set, the system uses a fallback value stored in the platform data — acceptable in development, not in production.

---

## Private repositories

The code repositories (backend, frontend, skills) can be hosted privately on GitHub. Add a personal access token with read permission to the configuration. The startup script injects it automatically and transparently.
