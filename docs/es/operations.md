<div align="center">
  <a href="index.md">← Índice</a> &nbsp;·&nbsp;
  <a href="../en/operations.md">🇬🇧 Read in English</a>
</div>

<br>

# Operaciones

La instalación se hace con un único script por SO (`install.sh` / `install.ps1`) y la gestión diaria con **un único script Python multiplataforma** (`gaia.py`, sin dependencias externas — el mismo fichero en Linux, macOS y Windows) desde la raíz del proyecto.

---

## Instalación de un solo comando

Una única URL por sistema operativo. El script pregunta interactivamente:

1. **Frontend** — Vanilla (estático, sin build) o React (SPA, requiere Node.js).
2. **Modo** — Docker (recomendado, incluye PostgreSQL opcional) o sin Docker (Python/Node directos, SQLite).

### 🐳🐧🍎 Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/iagentshub/iAgents/main/install.sh | bash
```

### 🪟 Windows

Ejecuta en PowerShell (como Administrador si eliges el modo sin Docker, para poder instalar dependencias con winget):

```powershell
irm https://raw.githubusercontent.com/iagentshub/iAgents/main/install.ps1 | iex
```

### Ayuda del instalador

```bash
bash install.sh --help
```
```powershell
# Descarga el script primero — "irm ... | iex" no admite pasar argumentos
irm https://raw.githubusercontent.com/iagentshub/iAgents/main/install.ps1 -OutFile install.ps1
powershell -File install.ps1 --help
```

### Saltarte los prompts (CI / reinstalación no interactiva)

```bash
IAGENTSHUB_FRONTEND=vanilla IAGENTSHUB_MODE=docker bash install.sh
```
```powershell
$env:IAGENTSHUB_FRONTEND = "vanilla"; $env:IAGENTSHUB_MODE = "docker"
irm https://raw.githubusercontent.com/iagentshub/iAgents/main/install.ps1 | iex
```

> **Nota:** El modo sin Docker utiliza SQLite como base de datos. Para entornos de producción o con múltiples usuarios concurrentes se recomienda el modo Docker con PostgreSQL.

---

## Primer arranque (con repositorio clonado)

Clona el repositorio, copia el fichero de configuración de ejemplo, completa los valores necesarios y ejecuta el script de arranque. La plataforma estará disponible en `http://localhost` al finalizar.

El backend crea automáticamente una cuenta administrador la primera vez que arranca. El script muestra siempre las credenciales al finalizar `start` o `update`:

```
  ╔══════════════════════════════════════════╗
  ║       Acceso de administrador            ║
  ╠══════════════════════════════════════════╣
  ║  Email      › admin@example.com
  ║  Contraseña › (sin cambios)
  ╚══════════════════════════════════════════╝
```

Si se generó una contraseña nueva (primer inicio o reset forzado), aparece en el campo _Contraseña_. En caso contrario se muestra _(sin cambios)_.

Para forzar un nuevo reset, añade `GAIA_ADMIN_RESET: "true"` al bloque `environment` del servicio `backend` en `docker-compose.dev.yml`, ejecuta `python3 gaia.py update --dev` y copia la contraseña que aparece. **Elimina esa línea inmediatamente después** para evitar resets accidentales en futuros reinicios.

---

## Ayuda y comandos disponibles

```bash
python3 gaia.py --help              # Docker (o el modo elegido con --local/--hub/--dev)
python3 gaia.py --help --local      # ayuda específica del modo sin Docker
```

En Windows: `python gaia.py --help` (mismo fichero, misma sintaxis).

| Comando | Qué hace |
|---|---|
| `start` | Construye e inicia todos los servicios |
| `stop` | Detiene los servicios |
| `restart` | Detiene y vuelve a arrancar los servicios (sin descargar nada nuevo) |
| `update` | Descarga la última versión y reinicia *(solo Docker)* |
| `logs` | Muestra la actividad en tiempo real |
| `status` | Estado actual de los servicios |
| `push` | Construye las imágenes unificadas (ambas variantes por defecto) y las sube a Docker Hub *(solo Docker)* |

---

## Modos de ejecución

**Modo producción** — el comportamiento por defecto (sin flags). Descarga siempre la última versión de cada repositorio desde GitHub antes de construir. Recomendado para entornos reales.

**Modo desarrollo** (`--dev`) — usa los repositorios locales del desarrollador (`../backend_fastapi`, `../frontend_vanilla` o `../frontend_react` según el profile) en lugar de descargar desde GitHub. Permite iterar sin hacer push de cada cambio.

**Modo Hub** (`--hub`) — usa la imagen unificada pre-construida de Docker Hub (backend + frontend en un único contenedor). Es el modo que usa `install.sh` en la rama Docker. El tag de imagen (`latest`=React, `vanilla`=Vanilla) se controla con `IMAGE_TAG` en `.env`.

**Modo local** (`--local`) — sin Docker: uvicorn + un proxy Python sirven la app (SQLite). El frontend servido (Vanilla o React) se controla con `GAIA_FRONTEND_VARIANT` en `.env`; si es `react`, `gaia.py` ejecuta `npm run build` la primera vez (o si faltara `dist/`) y sirve ese resultado como estático — no hay servidor Vite persistente.

---

## Publicar las imágenes unificadas (`push`)

```bash
python3 gaia.py push                      # construye y sube TODAS las variantes: :latest y :vanilla
python3 gaia.py push --frontend=vanilla   # limita el build/push a iagenthub/iagentshub:vanilla
python3 gaia.py push --frontend=react     # limita el build/push a iagenthub/iagentshub:latest
```

En producción (CI), cada frontend publica su propia variante de la imagen unificada de forma independiente: el workflow de `frontend_vanilla` publica `:vanilla` y el de `frontend_react` publica `:latest`.

---

## Repositorios privados

Si los repositorios están en GitHub con acceso privado, añade un token de acceso personal a la configuración. El script lo inyecta automáticamente al arrancar en modo producción.

---

## Actualizar

El comando de actualización detiene los servicios, descarga el código más reciente y los reinicia. Los datos existentes no se modifican.
