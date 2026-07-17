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

## Administrador inicial

En el primer arranque, si no existe ningún usuario con rol `admin`, el backend crea uno automáticamente y muestra las credenciales en los logs del servicio:

```
docker logs iagentshub-backend-1 2>&1 | grep -A6 "Administrador"
```

Las variables que controlan este comportamiento son:

| Variable | Valor por defecto | Descripción |
|---|---|---|
| `GAIA_ADMIN_EMAIL` | `admin@localhost` | Email (y nombre de usuario) de la cuenta administrador inicial. |
| `GAIA_ADMIN_RESET` | *(vacío)* | Pon `true` para resetear la contraseña del admin en el próximo arranque. **Quitar después del arranque.** |

---

## Registro de cuentas

| Variable | Opciones | Descripción |
|---|---|---|
| `GAIA_REGISTRATION` | `open` / `closed` / `invite` | Controla quién puede crear nuevas cuentas. `invite` (por defecto) requiere que un administrador cree la cuenta manualmente. |
| `GAIA_EMAIL_VERIFY` | `false` / `true` | Si `true`, los nuevos usuarios reciben un correo de verificación antes de poder acceder. Requiere configuración SMTP (pendiente). |

---

## Variante de frontend

`install.sh` / `install.ps1` fijan estas variables automáticamente según lo que elijas durante la instalación — solo relevante si editas `.env` a mano.

| Variable | Opciones | Descripción |
|---|---|---|
| `GAIA_FRONTEND_VARIANT` | `vanilla` / `react` | Solo en modo local (`--local`, sin Docker). Qué frontend sirve `gaia.py`. Si es `react`, ejecuta `npm run build` la primera vez (requiere Node.js) y sirve el resultado estático de `dist/`. |
| `IMAGE_TAG` | `latest` / `vanilla` / cualquier tag | Solo en modo Docker Hub (`--hub`). Qué tag de la imagen unificada se descarga: `latest` es la build de React, `vanilla` la de Vanilla. |

---

## Secreto de sesión

Debe generarse de forma aleatoria antes del primer arranque y no cambiarse mientras haya sesiones activas. Si no se define, el sistema usa un valor de emergencia almacenado en los datos de la plataforma — aceptable en desarrollo, no en producción.

---

## Repositorios privados

Los repositorios de código (backend, frontend, skills) pueden estar en GitHub con acceso privado. Añade un token de acceso personal con permiso de lectura a la configuración. El script de arranque lo inyecta de forma automática y transparente.
