<div align="center">
  <a href="docs/en/index.md">🇬🇧 English</a> &nbsp;·&nbsp;
  <a href="docs/es/index.md">🇪🇸 Español</a>
</div>

<br>

<h1 align="center">iAgents Hub</h1>

<p align="center">
  Plataforma para crear, gestionar y compartir agentes de IA. Conecta tus propias claves de LLM, organiza los agentes en espacios de trabajo y despliega en un servidor propio en un solo comando.<br><br>
  <em>Platform to create, manage and share AI agents. Connect your own LLM keys, organise agents in groups and self-host with a single command.</em>
</p>

---

## Instalación / Install

Una única URL por sistema operativo. El instalador despliega la plataforma
completa (backend FastAPI y frontend React) y pregunta qué **modo**
quieres (Docker o sin Docker):

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
1. En una instalación nueva pregunta el modo: **Docker** (recomendado, incluye PostgreSQL opcional) o **sin Docker** (Python/Node directos, SQLite).
2. Permite instalar la aplicación **completa**, solo el **backend** o solo el **frontend**. El frontend aislado solicita la URL de su backend.
3. En las actualizaciones detecta y conserva automáticamente ambas elecciones.
4. Instala únicamente las dependencias y repositorios necesarios para los componentes elegidos.
5. Arranca los servicios y muestra sus URLs y, si hay backend, las credenciales de administración.

Para saltarte los prompts (reinstalación no interactiva / CI):

```bash
IAGENTSHUB_MODE=docker bash install.sh
IAGENTSHUB_MODE=local IAGENTSHUB_COMPONENT=backend bash install.sh
```

> **Imagen Docker:** `ghcr.io/iagentshub/app:latest`, generada automáticamente por GitHub Actions.

Una vez instalado:

`gaia.py` es el entrypoint de una CLI Python modular en `gaia_cli/`, sin
dependencias externas y con el mismo uso en Linux, macOS y Windows:

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
python3 gaia.py start --hub         # Docker, imagen de GitHub Container Registry
python3 gaia.py start --dev         # Docker, hot reload con código local
python3 gaia.py start --local       # sin Docker (uvicorn + proxy Python)

python3 gaia.py push                # construir y subir la imagen React :latest

python3 gaia.py reset                     # borra la BD y TODOS los volúmenes, reinstala desde cero
python3 gaia.py reset --local             # borra iAgents/data/ y reinstala desde cero
```

> ⚠️ `reset` es **irreversible**: borra usuarios, agentes, skills, conexiones y todo el historial. Pide confirmación escrita (`RESET`) desde un terminal, y no hay forma de omitirla.

---

| | |
|---|---|
| 🇪🇸 Español | [docs/es/index.md](docs/es/index.md) |
| 🇬🇧 English | [docs/en/index.md](docs/en/index.md) |

---

[MIT](LICENSE)
