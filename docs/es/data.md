<div align="center">
  <a href="index.md">← Índice</a> &nbsp;·&nbsp;
  <a href="../en/data.md">🇬🇧 Read in English</a>
</div>

<br>

# Datos

Todos los datos de la plataforma se almacenan en el directorio `data/` del host. Este directorio se crea y se inicializa automáticamente en el primer arranque y sobrevive a reinicios, actualizaciones y reconstrucciones.

---

## Qué contiene

| Ruta | Contenido |
|---|---|
| `settings.json` | Configuración global de la instancia (secreto JWT, SMTP, límites) |
| `hub.db` | Base de datos SQLite principal. Contiene usuarios, conversaciones, mensajes, conexiones (API keys cifradas), knowledge, workspaces, grupos y tokens de uso. En producción se sustituye por PostgreSQL vía `DATABASE_URL`. |
| `agents/` | Configuraciones de agentes en ficheros `config.json` por scope (`private/` y `public/`) |
| `skills/` | Skills en ficheros `SKILL.md` por scope (`private/` y `public/`) |
| `memory/` | Ficheros de memoria por agente. Se crean y actualizan automáticamente tras cada conversación cuando el agente tiene la memoria activada. |
| `logs/` | Ficheros de log diarios (`YYYYMMDD.log`). Accesibles desde el panel de administración → Logs. |

---

## Base de datos

Las tablas principales son:

| Tabla | Contenido |
|---|---|
| `users` | Cuentas, roles, hash de contraseña, tokens GDPR |
| `conversations` / `messages` | Historial de chats |
| `connections` | Credenciales de proveedores (API keys cifradas con AES) |
| `knowledge_folders` / `knowledge_items` | Documentos y URLs de conocimiento |
| `workspaces` / `workspace_members` / `workspace_invitations` | Workspaces de equipo y membresías |
| `workspace_groups` / `workspace_group_members` / `resource_groups` | Grupos y permisos compartidos |
| `accounts` | Cuentas externas vinculadas (Google, etc.) |
| `token_daily` | Uso de tokens por día y proveedor |

Las migraciones son incrementales y se aplican automáticamente al arrancar (`_migrate_sqlite` y `_migrate_pg` en `app/storage/db.py`).

---

## Exportación de datos (GDPR Art. 20)

Cada usuario puede descargar todos sus datos desde **Perfil → Privacidad → Descargar mis datos**. El archivo ZIP incluye perfil, conexiones, knowledge, conversaciones completas, workspaces, tokens de uso, agentes y skills.

---

## Qué se versiona

Solo `settings.json` se incluye en el repositorio como valor por defecto. El resto de los datos no se versiona: contienen información específica de cada instalación que no debe compartirse.

---

## Persistencia

El directorio vive en el sistema de ficheros del host y no depende del ciclo de vida de los contenedores. Para borrar todos los datos de la plataforma, elimina el directorio `data/` manualmente.
