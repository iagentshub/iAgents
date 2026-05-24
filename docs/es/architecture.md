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

## Sistema de equipos

### Roles de usuario

| Rol | Descripción |
|-----|-------------|
| `admin` | Acceso total al panel de administración y a todos los recursos. |
| `gestor` | Puede crear equipos, invitar miembros y definir permisos granulares sobre sus recursos. |
| `standard` | Usuario normal con acceso a sus propios recursos. Se convierte en `gestor` al crear su primer equipo. |
| `guest` | Sesión temporal sin cuenta. Acceso limitado. |

Un usuario con rol `standard` asciende automáticamente a `gestor` al crear un equipo. Si elimina todos los equipos que gestiona, vuelve a `standard`.

### Modelo de datos

Tres tablas adicionales en la base de datos gestionan los equipos:

- **`teams`** — Nombre del equipo, creador y fecha de creación.
- **`team_members`** — Relación usuario–equipo con flag de gestor y permisos JSON granulares.
- **`team_invitations`** — Invitaciones por email con estado (`pending` / `accepted` / `rejected` / `expired`) y caducidad configurable (48 h por defecto).

### Permisos granulares

Los permisos de cada miembro se almacenan como JSON en `team_members.permissions`. La estructura es por tipo de recurso (`agents`, `connections`, `knowledge`) con una política por defecto (`deny` o `allow`) y excepciones por recurso individual:

```json
{
  "agents":      { "default": "deny", "items": { "agent-id": { "use": true } } },
  "connections": { "default": "deny", "items": { "conn-id":  { "direct": false, "via_agent": true } } },
  "knowledge":   { "default": "deny", "items": { "know-id":  { "view": true } } }
}
```

Las conexiones tienen dos ejes de permiso independientes:
- `direct` — el miembro ve y usa la conexión desde la página de Conexiones.
- `via_agent` — cuando un agente permitido invoca esta conexión, el acceso se permite aunque `direct` sea `false`.

### Flujo de invitación

1. El gestor envía una invitación desde el panel (`/manager/`) → el sistema genera un token y envía un email con un enlace a `/profile/?tab=teams&token=…`.
2. El usuario invitado ve la invitación en **Perfil → Equipos** y la acepta o rechaza.
3. Al aceptar, el usuario se incorpora al equipo con permisos vacíos (política `deny` por defecto).
4. El gestor ajusta los permisos desde el modal de su panel.

### Panel de gestor

Los gestores disponen de un panel dedicado en `/manager/` con dos pestañas:

- **Equipo** — tabla de miembros con acciones (editar permisos, hacer gestor, expulsar).
- **Invitaciones** — envío de nuevas invitaciones y cancelación de las pendientes.

El panel aparece en la navegación lateral únicamente cuando `role === 'gestor'` o `manages_teams === true` en la respuesta de `/api/auth/me`.
