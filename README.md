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

Elige el método que mejor se adapte a tu entorno:

| | Plataforma | Requisitos | Comando |
|---|---|---|---|
| 🐳 | **Linux / macOS** (recomendado) | Docker | `curl -fsSL .../install.sh \| bash` |
| 🍎 | **macOS** sin Docker | macOS 12+ | `curl -fsSL .../install-local-mac.sh \| bash` |
| 🪟 | **Windows** sin Docker | Windows 10/11 + winget | `irm .../install-local-windows.ps1 \| iex` |

---

### 🐳 Linux / macOS con Docker (recomendado para producción)

```bash
curl -fsSL https://raw.githubusercontent.com/iagentshub/iagentshub/main/install.sh | bash
```

Descarga la configuración, te pide el dominio y el email del administrador, y arranca la aplicación. Para actualizar, ejecuta el mismo comando.

> **Docker Hub:** [`iagenthub/iagentshub`](https://hub.docker.com/r/iagenthub/iagentshub)

---

### 🍎 macOS sin Docker

Instala Python y git automáticamente via Homebrew si no están presentes. Usa SQLite como base de datos.

```bash
curl -fsSL https://raw.githubusercontent.com/iagentshub/iagentshub/main/install-local-mac.sh | bash
```

Una vez instalado:

```bash
cd ~/iagentshub/iagentshub
./gaia.sh start --local   # arrancar
./gaia.sh stop --local    # parar
./gaia.sh logs --local    # ver logs
```

---

### 🪟 Windows sin Docker

Instala Python y git automáticamente via winget si no están presentes. Usa SQLite como base de datos. Ejecuta en **PowerShell como Administrador**:

```powershell
irm https://raw.githubusercontent.com/iagentshub/iagentshub/main/install-local-windows.ps1 | iex
```

Una vez instalado:

```bat
cd %USERPROFILE%\iagentshub\iagentshub
gaia.bat start --local   rem arrancar
gaia.bat stop --local    rem parar
gaia.bat logs --local    rem ver logs
```

---

### ⚙️ Modos avanzados — con repositorio clonado

```bash
git clone https://github.com/iagentshub/iagentshub.git
cd iagentshub/iagentshub
cp .env.example .env          # edita GAIA_AGENTS_SECRET y GAIA_FRONTEND_URL
./gaia.sh start               # Docker, imágenes locales
./gaia.sh start --hub         # Docker, imágenes de Docker Hub
./gaia.sh start --dev         # Docker, hot reload con código local
./gaia.sh start --local       # sin Docker (uvicorn + proxy Python)
```

---

| | |
|---|---|
| 🇪🇸 Español | [docs/es/index.md](docs/es/index.md) |
| 🇬🇧 English | [docs/en/index.md](docs/en/index.md) |

---

[MIT](LICENSE)
