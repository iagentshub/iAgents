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

## Instalación rápida / Quick install

Solo necesitas Docker:

```bash
curl -fsSL https://raw.githubusercontent.com/iagentshub/iagentshub/main/install.sh | bash
```

El script descarga la configuración, te pide el dominio y el email de administrador, y arranca la aplicación. Para actualizar, ejecuta el mismo comando.

> **Docker Hub:** `iagenthub/backend` · `iagenthub/frontend`

---

## Otros modos de despliegue / Other deploy modes

**Linux / macOS — con repositorio clonado**

```bash
git clone https://github.com/iagentshub/iagentshub.git
cd iagentshub
cp .env.example .env   # edita GAIA_AGENTS_SECRET y GAIA_FRONTEND_URL
./gaia.sh start        # Docker, imágenes de GitHub
./gaia.sh start --hub  # Docker, imágenes de Docker Hub
./gaia.sh start --dev  # Docker, código local con hot reload
./gaia.sh start --local  # sin Docker (uvicorn + proxy Python)
```

**Windows**

```bat
git clone https://github.com/iagentshub/iagentshub.git
cd iagentshub
copy .env.example .env
gaia.bat start
```

---

| | |
|---|---|
| 🇪🇸 Español | [docs/es/index.md](docs/es/index.md) |
| 🇬🇧 English | [docs/en/index.md](docs/en/index.md) |

---

[MIT](LICENSE)
