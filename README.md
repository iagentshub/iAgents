<div align="center">
  <a href="docs/en/index.md">🇬🇧 English</a> &nbsp;·&nbsp;
  <a href="docs/es/index.md">🇪🇸 Español</a>
</div>

<br>

<h1 align="center">iAgents Hub</h1>

<p align="center">
  Plataforma para crear, gestionar y compartir agentes de IA. Conecta tus propias claves de LLM, organiza los agentes en espacios de trabajo y despliega en un servidor propio en un solo comando.<br><br>
  <em>Platform to create, manage and share AI agents. Connect your own LLM keys, organise agents in workspaces and self-host with a single command.</em>
</p>

---

## Instalación / Install

Una única URL por sistema operativo. El script pregunta interactivamente qué
**frontend** quieres (Vanilla o React) y qué **modo** (Docker o sin Docker):

| | Plataforma | Comando |
|---|---|---|
| 🐳🐧🍎 | **Linux / macOS** | `curl -fsSL .../install.sh \| bash` |
| 🪟 | **Windows** | `irm .../install.ps1 \| iex` |

```bash
curl -fsSL https://raw.githubusercontent.com/iagentshub/iAgents/main/install.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/iagentshub/iAgents/main/install.ps1 | iex
```

El script:
1. Pregunta el frontend: **Vanilla** (estático, sin build) o **React** (SPA, requiere Node.js).
2. Pregunta el modo: **Docker** (recomendado, incluye PostgreSQL opcional) o **sin Docker** (Python/Node directos, SQLite).
3. Instala lo que falte (Docker no instala nada más; sin Docker instala Python 3.11+, git y, si eliges React, Node.js — todo vía el gestor de paquetes nativo: apt/dnf/yum/pacman/zypper, Homebrew o winget).
4. Arranca la aplicación y muestra la URL, el email de admin y la contraseña generada.

Para saltarte los prompts (reinstalación no interactiva / CI):

```bash
IAGENTSHUB_FRONTEND=vanilla IAGENTSHUB_MODE=docker bash install.sh
```

> **Docker Hub:** [`iagenthub/app:latest`](https://hub.docker.com/r/iagenthub/app) (React) · `iagenthub/app:vanilla` (Vanilla)

Una vez instalado:

`gaia.py` es un único script Python (sin dependencias externas) — igual en Linux, macOS y Windows:

```bash
cd ~/iagentshub/iAgents
python3 gaia.py start --local     # start (if you chose "no Docker")
python3 gaia.py stop --local      # stop
python3 gaia.py restart --local   # restart
python3 gaia.py logs --local      # tail logs
```

```bat
cd %USERPROFILE%\iagentshub\iAgents
python gaia.py start --local     rem start (if you chose "no Docker")
python gaia.py stop --local      rem stop
python gaia.py restart --local   rem restart
python gaia.py logs --local      rem tail logs
```

---

### ⚙️ Modos avanzados — con repositorio clonado

```bash
git clone https://github.com/iagentshub/iAgents.git
cd iagentshub/iAgents
cp .env.example .env          # edita GAIA_AGENTS_SECRET y GAIA_FRONTEND_URL
python3 gaia.py start               # Docker, imágenes locales
python3 gaia.py start --hub         # Docker, imágenes de Docker Hub
python3 gaia.py start --dev         # Docker, hot reload con código local
python3 gaia.py start --local       # sin Docker (uvicorn + proxy Python)

python3 gaia.py push                      # construir y subir TODAS las imágenes (:latest + :vanilla)
python3 gaia.py push --frontend=vanilla   # construir y subir solo :vanilla
python3 gaia.py push --frontend=react     # construir y subir solo :latest
```

---

| | |
|---|---|
| 🇪🇸 Español | [docs/es/index.md](docs/es/index.md) |
| 🇬🇧 English | [docs/en/index.md](docs/en/index.md) |

---

[MIT](LICENSE)
