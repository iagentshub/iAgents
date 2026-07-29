<div align="center">
  <a href="https://www.iagentshub.com/">
    <img src="https://www.iagentshub.com/og-image.png" alt="iAgentsHub" width="720">
  </a>

  <h1>iAgentsHub</h1>

  <p>
    <strong>Create and orchestrate AI agents with your own providers, knowledge, and tools.</strong><br>
    Open source, multi-provider, and deployable on your infrastructure.
  </p>

  <p>
    <strong>Crea y orquesta agentes de IA con tus propios proveedores, conocimiento y herramientas.</strong><br>
    Código abierto, multiproveedor y desplegable en tu infraestructura.
  </p>

  <p>
    <a href="https://www.iagentshub.com/"><strong>Website</strong></a>
    ·
    <a href="https://www.iagentshub.com/docs"><strong>Documentation</strong></a>
    ·
    <a href="https://www.iagentshub.com/pricing/"><strong>Managed service</strong></a>
    ·
    <a href="#quick-start--inicio-rápido"><strong>Self-host</strong></a>
  </p>

  <p>
    <a href="https://github.com/iagentshub/iAgents/actions/workflows/validate.yml">
      <img src="https://github.com/iagentshub/iAgents/actions/workflows/validate.yml/badge.svg" alt="Validation">
    </a>
    <a href="https://hub.docker.com/r/iagenthub/app">
      <img src="https://img.shields.io/docker/pulls/iagenthub/app?label=Docker%20pulls" alt="Docker pulls">
    </a>
    <img src="https://img.shields.io/badge/languages-English%20%7C%20Español-555" alt="English and Spanish">
  </p>
</div>

---

## Why iAgentsHub? / ¿Por qué iAgentsHub?

iAgentsHub brings agents, providers, knowledge, memory, skills, workflows, and
teams together in one platform. You choose which AI providers process each
request and where the platform is deployed.

iAgentsHub reúne agentes, proveedores, conocimiento, memoria, skills, workflows
y equipos en una sola plataforma. Tú eliges qué proveedores procesan cada
solicitud y dónde se despliega la plataforma.

| | English | Español |
| --- | --- | --- |
| **Control** | Use your own provider keys and infrastructure | Usa tus propias claves e infraestructura |
| **Orchestration** | Build multi-step and branching agent workflows | Crea flujos de agentes con múltiples pasos y ramificaciones |
| **Portability** | Export agents to the tools where you work | Exporta agentes a las herramientas donde trabajas |
| **Collaboration** | Share agents, knowledge, and resources with your team | Comparte agentes, conocimiento y recursos con tu equipo |

## What you can build / Qué puedes construir

- **Specialized assistants:** combine model providers, instructions, memory,
  knowledge, and reusable skills.
- **Agent workflows:** connect specialized agents in sequential, parallel, and
  branching processes.
- **Shared AI workspaces:** organize agents and resources for a team without
  duplicating them.
- **Portable agents:** create once and export to supported external tools.
- **Private deployments:** run the platform on infrastructure you control.

## Choose how to use it / Elige cómo utilizarlo

### Self-hosted

Deploy the complete stack on your own server with Docker or run the services
locally. You manage the infrastructure and connect your own AI provider keys.

Despliega el sistema completo en tu servidor con Docker o ejecuta los servicios
localmente. Tú administras la infraestructura y conectas tus propias claves.

### Managed service

Use the hosted service when you prefer iAgentsHub to manage the infrastructure,
updates, and backups. See the current options on the
[pricing page](https://www.iagentshub.com/pricing/).

Utiliza el servicio gestionado si prefieres que iAgentsHub administre la
infraestructura, las actualizaciones y las copias de seguridad. Consulta las
opciones actuales en la [página de precios](https://www.iagentshub.com/pricing/).

## Quick start / Inicio rápido

The interactive installer lets you choose the web interface and whether to use
Docker or a local installation.

El instalador interactivo permite elegir la interfaz web y si quieres utilizar
Docker o una instalación local.

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/iagentshub/iAgents/main/install.sh | bash
```

### Windows

```powershell
irm https://raw.githubusercontent.com/iagentshub/iAgents/main/install.ps1 | iex
```

The installer:

1. Lets you choose the frontend.
2. Lets you choose Docker or local mode.
3. Checks and installs the required system dependencies.
4. Starts the application and displays its URL and generated admin credentials.

El instalador:

1. Permite elegir el frontend.
2. Permite elegir Docker o modo local.
3. Comprueba e instala las dependencias necesarias del sistema.
4. Inicia la aplicación y muestra su URL y las credenciales de administración generadas.

For non-interactive installations:

```bash
curl -fsSL https://raw.githubusercontent.com/iagentshub/iAgents/main/install.sh |
  IAGENTSHUB_FRONTEND=react IAGENTSHUB_MODE=docker bash
```

> Docker Hub: [`iagenthub/app:latest`](https://hub.docker.com/r/iagenthub/app)

## Operations / Operaciones

`gaia.py` provides the same management interface on Linux, macOS, and Windows.

```bash
python3 gaia.py start --local
python3 gaia.py stop --local
python3 gaia.py restart --local
python3 gaia.py logs --local
```

### Advanced modes / Modos avanzados

```bash
git clone https://github.com/iagentshub/iAgents.git
cd iAgents
cp .env.example .env

python3 gaia.py start         # Docker, local images
python3 gaia.py start --hub   # Docker Hub images
python3 gaia.py start --dev   # Docker with local hot reload
python3 gaia.py start --local # Local processes without Docker
```

See the operations and configuration guides before deploying a public or
production instance.

Consulta las guías de operaciones y configuración antes de publicar una
instancia o utilizarla en producción.

## Architecture / Arquitectura

```text
iAgents
├── deployment and lifecycle management
├── backend_fastapi
├── frontend_react
└── data services and reverse proxy
```

This repository is the public entry point and deployment layer for the complete
iAgentsHub platform. Component repositories contain their own development and
testing instructions.

Este repositorio es el punto de entrada público y la capa de despliegue de la
plataforma completa. Los repositorios de componentes contienen sus propias
instrucciones de desarrollo y pruebas.

| Component | Purpose |
| --- | --- |
| [`backend_fastapi`](https://github.com/iagentshub/backend_fastapi) | Agents, skills, memory, workflows, workspaces, and provider connections |
| [`frontend_react`](https://github.com/iagentshub/frontend_react) | Main React and TypeScript web application |

## Documentation / Documentación

| English | Español |
| --- | --- |
| [Documentation index](docs/en/index.md) | [Índice de documentación](docs/es/index.md) |
| [Architecture](docs/en/architecture.md) | [Arquitectura](docs/es/architecture.md) |
| [Configuration](docs/en/config.md) | [Configuración](docs/es/config.md) |
| [Operations](docs/en/operations.md) | [Operaciones](docs/es/operations.md) |
| [Data](docs/en/data.md) | [Datos](docs/es/data.md) |
| [Secrets](docs/en/secrets.md) | [Secretos](docs/es/secrets.md) |

## Project status / Estado del proyecto

iAgentsHub is under active development. Interfaces, configuration, and
deployment behavior may change before the first stable release.

iAgentsHub está en desarrollo activo. Las interfaces, la configuración y el
despliegue pueden cambiar antes de la primera versión estable.

Bug reports, proposals, documentation improvements, and contributions are
welcome through [GitHub Issues](https://github.com/iagentshub/iAgents/issues).
