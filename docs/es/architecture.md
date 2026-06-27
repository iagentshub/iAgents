<div align="center">
  <a href="index.md">← Índice</a> &nbsp;·&nbsp;
  <a href="../en/architecture.md">🇬🇧 Read in English</a>
</div>

<br>

# Arquitectura global

iAgentsHub está compuesto por cuatro repositorios independientes que trabajan juntos como un único sistema.

---

## Los cuatro repositorios

| Repositorio | Rol |
|---|---|
| **iagentshub** | Orquestador. Contiene la configuración de despliegue y el script de arranque. |
| **backend** | El servicio central. Gestiona agentes, skills, memoria y conexiones con proveedores de IA. |
| **frontend** | La interfaz web. Permite crear y gestionar agentes desde el navegador. |
| **skills** | El catálogo de skills. Colección de capacidades reutilizables que los agentes pueden usar. |

El repositorio `iagentshub` es el único que el usuario necesita clonar. El resto se obtienen automáticamente al desplegar.

---

## Cómo encajan en tiempo de ejecución

Al arrancar la plataforma ocurre lo siguiente, en orden:

1. Se construyen las imágenes del backend y el frontend desde sus repositorios.
2. Un servicio de inicialización prepara la estructura de datos, genera la configuración inicial y sincroniza las skills desde el repositorio de skills.
3. El backend arranca una vez que la inicialización completa con éxito.
4. El frontend arranca y comienza a servir la interfaz web.

El frontend actúa como punto de entrada único: sirve la interfaz y redirige las peticiones al backend de forma transparente.

---

## Modo producción y modo desarrollo

La plataforma puede arrancar en dos modos:

**Modo producción** — descarga siempre la última versión de cada repositorio desde GitHub antes de construir. Garantiza que el entorno refleja el estado actual de los repositorios remotos.

**Modo desarrollo** — usa los repositorios locales del desarrollador en lugar de descargar desde GitHub. Permite iterar rápidamente sin hacer push de cada cambio.

En ambos modos el comportamiento de la plataforma es idéntico. La única diferencia es el origen del código.

---

## Repositorios de contenido frente a repositorios de código

El backend y el frontend son **repositorios de código**: su evolución sigue ciclos de desarrollo convencionales con revisiones y releases.

Las skills y los agentes son **repositorios de contenido**: su contenido puede modificarlo cualquier colaborador, los cambios son visibles de forma inmediata y el historial refleja fielmente qué capacidades existen y cuándo se añadieron.

Esta separación permite gestionar el contenido con la misma trazabilidad que el código, sin mezclar cambios funcionales con cambios editoriales.

---

## Persistencia de datos

Todos los datos de la plataforma —configuración, agentes, memoria, claves de API, skills— se almacenan en el directorio `data/` del host. Este directorio sobrevive a reinicios, actualizaciones y reconstrucciones del sistema.

Las skills se sincronizan en cada arranque desde el repositorio de skills. El resto de los datos se conservan entre arranques sin intervención manual.

---

## Memoria activa de los agentes

Cuando un agente tiene la memoria activada, el sistema genera y mantiene automáticamente un fichero de memoria para ese agente. Tras cada conversación, el backend actualiza ese fichero con los hechos relevantes extraídos del diálogo: preferencias del usuario, contexto del proyecto, decisiones tomadas y cualquier dato que el agente deba recordar en futuras sesiones.

En la siguiente conversación, el contenido de ese fichero se incorpora al contexto del agente de forma automática, sin intervención del usuario.

---

## Workspaces y colaboración

### Roles de usuario

| Rol | Descripción |
|-----|-------------|
| `admin` | Acceso total al panel de administración y a todos los recursos. |
| `standard` | Usuario normal con acceso a sus propios recursos. |
| `guest` | Sesión temporal sin cuenta. Acceso limitado. |

### Modelo de datos

Cada usuario tiene un **workspace personal** virtual (id = username, sin fila en BD). Los workspaces de equipo tienen entrada propia:

- **`workspaces`** — Nombre, creador y fecha de creación.
- **`workspace_members`** — Relación usuario–workspace con rol (`owner` / `admin` / `member`).
- **`workspace_invitations`** — Invitaciones por username con estado `pending`.
- **`workspace_groups`** / **`workspace_group_members`** — Grupos dentro de un workspace para compartir recursos.
- **`resource_groups`** — Relación recurso–grupo con permisos.

### Permisos granulares

Los permisos se gestionan a nivel de grupo. La estructura es por tipo de recurso con política por defecto y excepciones:

```json
{
  "agents":      { "default": "deny", "items": { "agent-id": { "use": true } } },
  "connections": { "default": "deny", "items": { "conn-id":  { "direct": false, "via_agent": true } } },
  "knowledge":   { "default": "deny", "items": { "know-id":  { "view": true } } }
}
```

### Flujo de invitación

1. El propietario invita desde **Perfil → Workspaces** introduciendo el username del invitado.
2. El invitado ve la invitación en **Perfil → Workspaces → Invitaciones** y la acepta o rechaza.
3. Al aceptar, el usuario se incorpora al workspace con rol `member`.

### Transferencia de propiedad

Un propietario puede transferir la titularidad a otro miembro antes de eliminar su cuenta:
`POST /api/workspaces/{id}/transfer-ownership` con `{ "username": "nuevo_propietario" }`.

### GDPR — derecho al olvido

Los usuarios pueden solicitar la eliminación completa de su cuenta desde **Perfil → Privacidad**:

- Período de gracia de 30 días con enlace de cancelación por email.
- El propietario de workspaces debe transferirlos o eliminarlos antes de solicitar el borrado.
- La purga elimina en cascada: mensajes, conversaciones, knowledge, conexiones, tokens, agentes, skills y la cuenta de usuario.
- Exportación de datos disponible en cualquier momento (`GET /api/auth/me/export` → ZIP).
