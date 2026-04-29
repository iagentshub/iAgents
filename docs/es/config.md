<div align="center">
  <a href="index.md">← Índice</a> &nbsp;·&nbsp;
  <a href="../en/config.md">🇬🇧 Read in English</a>
</div>

<br>

# Configuración

La configuración se establece en un fichero de variables de entorno en la raíz del proyecto. Al clonar, copia el fichero de ejemplo y completa los valores antes del primer arranque. Este fichero no se versiona.

---

## Qué se puede configurar

| Ajuste | Descripción |
|---|---|
| Puerto público | El puerto en el que la plataforma es accesible desde el navegador. Por defecto, el 80. |
| Secreto de sesión | Clave usada para firmar los tokens de sesión. Obligatorio en producción. |
| Orígenes CORS | Dominios desde los que se permite el acceso a la API. |
| Repositorios | URLs de los repositorios de backend, frontend y skills. |
| Token de GitHub | Necesario para acceder a repositorios privados. |
| Idioma de las skills | El idioma en que se sirven las skills (`es` o `en`). |
| Rutas locales (dev) | Rutas a los repositorios locales para el modo desarrollo. |

---

## Secreto de sesión

Debe generarse de forma aleatoria antes del primer arranque y no cambiarse mientras haya sesiones activas. Si no se define, el sistema usa un valor de emergencia almacenado en los datos de la plataforma — aceptable en desarrollo, no en producción.

---

## Repositorios privados

Los repositorios de código (backend, frontend, skills) pueden estar en GitHub con acceso privado. Añade un token de acceso personal con permiso de lectura a la configuración. El script de arranque lo inyecta de forma automática y transparente.
