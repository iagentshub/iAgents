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
| `settings.json` | Configuración global de la instancia (tema, idioma, secreto JWT de emergencia) |
| `users.json` | Cuentas de usuario creadas mediante autenticación |
| `agents/` | Configuraciones de los agentes (instrucciones, personalidad, skills asignadas) |
| `connections/` | Claves de API de los proveedores de IA |
| `memory/` | Memoria acumulada por cada agente entre conversaciones |
| `skills/` | Skills sincronizadas desde el repositorio de skills en cada arranque |

---

## Qué se versiona

Solo `settings.json` se incluye en el repositorio como valor por defecto. El resto de los datos no se versiona: contienen información específica de cada instalación que no debe compartirse.

---

## Persistencia

El directorio vive en el sistema de ficheros del host y no depende del ciclo de vida de los contenedores. Para borrar todos los datos de la plataforma, elimina el directorio `data/` manualmente.
