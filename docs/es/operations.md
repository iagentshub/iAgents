<div align="center">
  <a href="index.md">← Índice</a> &nbsp;·&nbsp;
  <a href="../en/operations.md">🇬🇧 Read in English</a>
</div>

<br>

# Operaciones

Todo se gestiona con un único script desde la raíz del proyecto.

---

## Primer arranque

Clona el repositorio, copia el fichero de configuración de ejemplo, completa los valores necesarios y ejecuta el script de arranque. La plataforma estará disponible en `http://localhost` al finalizar.

---

## Comandos disponibles

| Comando | Qué hace |
|---|---|
| `start` | Construye e inicia todos los servicios |
| `stop` | Detiene los servicios |
| `update` | Descarga la última versión y reinicia |
| `logs` | Muestra la actividad en tiempo real |
| `status` | Estado actual de los servicios |

---

## Modos de ejecución

**Modo producción** — el comportamiento por defecto. Descarga siempre la última versión de cada repositorio desde GitHub antes de construir. Recomendado para entornos reales.

**Modo desarrollo** — se activa con el flag `--dev`. En lugar de descargar desde GitHub, usa los repositorios locales del desarrollador. Permite iterar sin hacer push de cada cambio.

---

## Repositorios privados

Si los repositorios están en GitHub con acceso privado, añade un token de acceso personal a la configuración. El script lo inyecta automáticamente al arrancar en modo producción.

---

## Actualizar

El comando de actualización detiene los servicios, descarga el código más reciente y los reinicia. Los datos existentes no se modifican.
