<div align="center">
  <a href="index.md">← Índice</a> &nbsp;·&nbsp;
  <a href="../en/operations.md">🇬🇧 Read in English</a>
</div>

<br>

# Operaciones

La instalación se hace con un único script por SO (`install.sh` / `install.ps1`) y la gestión diaria con **un único script Python multiplataforma** (`gaia.py`, sin dependencias externas — el mismo fichero en Linux, macOS y Windows) desde la raíz del proyecto.

---

## Instalación de un solo comando

Una única URL por sistema operativo. El script instala la plataforma completa
(backend FastAPI y frontend React) y pregunta por el **modo**: Docker
(recomendado, incluye PostgreSQL opcional) o sin Docker (Python/Node directos,
SQLite).

El mismo comando sirve para instalar y actualizar. Tras la primera instalación,
el instalador guarda la modalidad y los componentes elegidos y los reutiliza
automáticamente. Se puede instalar la aplicación completa, solo el backend o
solo el frontend. En este último caso solicita la URL del backend remoto y
mantiene `/api` bajo el mismo origen mediante un proxy inverso.

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
IAGENTSHUB_MODE=docker bash install.sh
IAGENTSHUB_MODE=local IAGENTSHUB_COMPONENT=backend bash install.sh
IAGENTSHUB_MODE=docker IAGENTSHUB_COMPONENT=frontend \
  IAGENTSHUB_API_URL=https://api.ejemplo.com bash install.sh
```
```powershell
$env:IAGENTSHUB_MODE = "docker"
$env:IAGENTSHUB_COMPONENT = "backend"
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
| `push` | Construye la imagen unificada React y la sube a GitHub Container Registry *(solo Docker)* |
| `reset` | Borra la base de datos y todos los datos, y reinstala desde cero *(pide confirmación)* |

---

## Modos de ejecución

**Modo producción** — el comportamiento por defecto (sin flags). Descarga siempre la última versión de cada repositorio desde GitHub antes de construir. Recomendado para entornos reales.

**Modo desarrollo** (`--dev`) — usa los repositorios locales del desarrollador (`../backend_fastapi` y `../frontend_react`) en lugar de descargar desde GitHub. Permite iterar sin hacer push de cada cambio.

**Modo Hub** (`--hub`) — usa la imagen unificada React pre-construida de GitHub Container Registry (backend + frontend en un único contenedor). El tag se controla con `IMAGE_TAG` en `.env`.

**Modo local** (`--local`) — sin Docker: uvicorn + un proxy Python sirven la app React (SQLite). `gaia.py` ejecuta `npm run build` cuando falta `dist/` o cambian las dependencias y sirve ese resultado como estático.

---

## Publicar las imágenes unificadas (`push`)

```bash
python3 gaia.py push  # construye y sube ghcr.io/iagentshub/app:latest
```

En producción, CI publica la imagen unificada React con el tag `:latest` y un tag de versión inmutable.

---

## Instalación desde cero (`reset`)

Borra por completo la base de datos (usuarios, agentes, skills, conexiones cifradas, chats, memoria) y reinstala desde cero. Es **irreversible** — el script pide escribir `RESET` para confirmar y no hay forma de omitirlo: fuera de un terminal (CI, `cron`, una tubería) el comando aborta sin tocar nada. `reset` no está pensado para automatizarse.

```bash
python3 gaia.py reset            # Docker: docker compose down -v + start (borra todos los volúmenes)
python3 gaia.py reset --dev      # igual, en modo desarrollo
python3 gaia.py reset --hub      # igual, en modo Hub
python3 gaia.py reset --local    # borra iAgents/data/ y reinstala
```

> ⚠️ El compose por defecto (sin flags) es el que usa un despliegue en producción típico. Ejecutar `reset` ahí borra los datos reales — verifica en qué servidor/directorio estás antes de confirmar.

---

## Repositorios privados

Si los repositorios están en GitHub con acceso privado, añade un token de acceso personal a la configuración. El script lo inyecta automáticamente al arrancar en modo producción.

---

## Actualizar

El comando de actualización detiene los servicios, descarga el código más reciente y los reinicia. Los datos existentes no se modifican.
