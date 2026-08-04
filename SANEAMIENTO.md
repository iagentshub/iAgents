# Saneamiento — estado y trabajo pendiente

Documento de trabajo del plan de saneamiento derivado de la auditoría del 3 de
agosto de 2026. Recoge lo hecho, lo que queda y las decisiones abiertas.

Última actualización: 4 de agosto de 2026.

---

## Cómo está repartido el trabajo

Los repos son independientes, así que ningún cambio es atómico entre backend y
clientes. **Orden obligatorio: backend primero** siempre que cambie el contrato.

Fases 1, 2 y 3 **mergeadas a `main`** en los cinco repos. Sin pushear.

| Repo | Ramas integradas |
|---|---|
| `backend` | `saneamiento/fase-1` + `saneamiento/fase-3` |
| `frontend_react` | `saneamiento/fase-1` |
| `app_flutter` | `saneamiento/fase-2` + `saneamiento/fase-3` |
| `vs_code` | `saneamiento/fase-3` |
| `iagentshub` | `saneamiento/fase-1` |

### La integración no fue un merge sin más

Mientras corrían las fases, `main` avanzó por su cuenta: 6 commits en backend,
13 en app_flutter, 2 en el orquestador. Trabajo nuevo —login con GitHub por
OAuth Device Flow, gestión de prompts, cuentas de proveedor— **construido sobre
una base donde `require_auth` todavía significaba invitado**.

Git resolvió los merges sin un solo conflicto de texto, que es exactamente
cuando hay que desconfiar: el riesgo no era textual sino semántico. Se
comprobó, no se supuso:

- **Los 15 endpoints nuevos** se auditaron con el mismo script AST que derivó
  el allowlist original. Los 2 sin guardia son el device flow de GitHub,
  público por definición —estás iniciando sesión, aún no tienes una— y con
  rate limit propio.
- **De los 13 con guardia, 4 estaban mal cerrados.** Ver abajo.
- **`request.json()` crudo**: el test que recorre las rutas confirma que ningún
  handler nuevo se saltó `json_body()`.
- **El contrato de rutas** (220) no cambió al integrar la fase 1.
- **`conftest.py`**, tocado por las dos fases en sitios distintos, conserva
  ambos cambios: el parche de `licenses` y el recorrido de `INSTANCES`.

#### Prompts: el merge lo cerró y no debía

La primera pasada de esta auditoría dio por bueno que Prompts quedara cerrado
al invitado, razonando que era «coherente con workflows y facturación». **Era
falso, y la suite lo demostró con 12 tests en rojo.**

El error de método: se comprobó qué guardia tenía cada endpoint nuevo, pero no
lo único que decide la respuesta —**si el código es consciente del invitado**—,
que es justo el criterio con el que se derivó el allowlist original.

`prompts.py` tiene 6 ramas `is_guest(...)`, `GuestSession` tiene un campo
`prompts`, y `main` traía tests que exigen que el invitado liste, lea, guarde y
borre sus prompts privados en la sesión efímera. Workflows y facturación no
tienen ni una rama `is_guest`; ahí sí era correcto cerrar.

Reaplicada la regla mecánica sobre el árbol mergeado salen **exactamente 4**
endpoints con rama `is_guest` y guardia que excluye al invitado, los 4 de
prompts. Ahora usan `require_group_session`. `activate` y `deactivate` no
tienen rama de invitado —operan sobre el estado del grupo en BD— y siguen
cerrados.

`test_guest_boundary.py` fija ahora prompts en las dos direcciones.

**La lección, para la próxima integración:** al mergear trabajo nuevo sobre la
fase 1, no basta con mirar guardias. Hay que volver a correr la derivación:

```
endpoints con rama is_guest()  ∧  guardia sin "session"  →  mal cerrados
```

---

## Hecho

### Fase 1 — críticos

| | Qué era | Verificación |
|---|---|---|
| **BE-01** | `require_auth` estaba aliasada al rango `guest`: ~140 endpoints privados aceptaban sesiones de invitado | 32 endpoints al allowlist (derivado de las ramas `is_guest`, no a ojo), 106 cerrados. 19 tests de frontera |
| **BE-02** | El logger abría una conexión SQLite nueva **por cada registro**, con el DDL entero, síncrono en el event loop. Con `RequestLoggerMiddleware` eso era 4 sentencias DDL por petición HTTP | `QueueHandler`/`QueueListener` de stdlib + conexión persistente. 38 tests |
| **BE-03** | `settings.json` se leía del disco en **toda** petición, incluidas las que el middleware iba a dejar pasar | Reordenado + invalidación explícita. `tests/middleware` pasa de 0 a 11 tests |
| **BE-04** | El modo de registro `invite` se rechazaba con 422 aunque el backend lo implementa y el `.env` real lo usa | Los 3 modos, derivados de `config/session.py` |
| **OPS-02** | `pytest-timeout` no estaba declarado: el `timeout=30` se ignoraba en silencio y `rtests.py` aborta en entorno limpio. `cryptography` llegaba solo como extra de `python-jose` | Ambas directas, hashes validados con `--require-hashes` |
| **FE-01** | La calculadora de precios no tenía un solo assert | `pricing-model.ts` + 19 tests de tramos frontera |
| **OPS-04** | 334 MB de `node_modules` rancios, `frontend/` vacío, `.DS_Store` rastreado, 6 docs huérfanos | Borrado |

**Suite backend: 1363 pasan, 0 fallan** (baseline previa: 1329).
**React: 34 tests**, tsc, eslint, build y guardián de arquitectura limpios.

### Fase 2

| | Qué era |
|---|---|
| **FE-02** | `frontend_vanilla` retirado en local. Ningún workflow lo construía y ninguna imagen lo desplegaba: `ghcr.io/iagentshub/frontend` lo publica React |
| — | Nombre del producto unificado: `about`, `docs` y `seo` de Flutter decían «iAgents» donde React dice «iAgents Hub», con **las mismas frases** |
| **FE-07** | Cabecera compartida en about, docs y support (−80 líneas de JSX duplicado) |
| **OPS-03** | Imágenes sin versión fijadas; contradicciones de `GAIA_REGISTRATION`, `GAIA_MAX_GUEST_SESSIONS` y healthcheck resueltas |

### Fase 3 — contrato de API y seguridad restante

| | Qué era | Cómo quedó |
|---|---|---|
| **FE-05** | `/openapi.json` abierto en producción: `create_app()` gateaba `docs_url` tras `GAIA_DEV_MODE` pero no `openapi_url`, así que el esquema completo de la API era público | Los dos se cierran juntos — `/docs` sin esquema no sirve de nada |
| **FE-05** | Tres clientes con el contrato escrito a mano en otros repos: renombrar una ruta no rompía ninguna compilación | La superficie queda congelada en `tests/api/contrato_rutas.txt` (220 rutas). Se actualiza con `--actualizar-contrato` |
| **FE-04** | La extensión aceptaba HTTP solo en localhost; Flutter aceptaba además todo el rango privado. **El mismo hub en `192.168.1.50` funcionaba en la app y la extensión lo rechazaba** | Misma definición de «red local» y **la misma tabla de casos** en los dos lenguajes: 35 tests TS, 30 Dart |
| **BE-05** | La contraseña temporal del admin en claro. Ver abajo: escondía un bug destructivo | Se vacía —no se borra— desde `_touch_password_changed_at`, el único punto por el que pasan los tres caminos que cambian contraseña |
| **BE-06** | El contador del rate limit vive en memoria del proceso y uvicorn arranca `GAIA_WORKERS` procesos: con el default de 4, los 5 intentos de login eran 20 | Se reparte la cuota. `WORKERS` pasa a `config/server.py` como fuente única |
| **BE-09** | Mandar `[]` como cuerpo a `/api/auth/register` —público— daba `AttributeError` y **500**. Los 43 handlers hacían `.get()` sobre lo que devolviera `request.json()` | `json_body()` garantiza objeto y devuelve 400. Un test recorre las rutas para que nadie use `request.json()` crudo |
| **BE-09** | `/api/billing/quote` era el único POST de billing sin freno | Con límite. Sigue sin auth a propósito: solo calcula un precio con datos públicos |
| **BE-09** | `birth_date`, `gender`, `country` y `phone` iban del registro a la BD sin tope: con el registro abierto, 2 MB por cuenta | Acotados |

**Suite backend: 1524 pasan, 1 skip, 0 fallan.** Flutter 185, vs_code 35,
React 34 + tsc + eslint + build + guardián de arquitectura.

#### BE-05 escondía un bug destructivo

El log decía *«borrar tras primer login»*, pero `ensure_admin_user()` lee el
fichero ausente como «instalación nueva»: **seguir esa instrucción hacía que el
siguiente reinicio regenerase la contraseña y tirase la que el usuario acababa
de elegir.** El propio ALTO-8 lo disparaba solo, al borrar el fichero tras un
cambio de contraseña.

Y solo cubría 1 de los 3 caminos que cambian una contraseña —ni el token de
recuperación ni el reseteo por admin lo tocaban— y encima dependía de
`GAIA_DATA_DIR`: sin esa variable no borraba nada.

Probado en ambos sentidos: sin el arreglo, 4 de los 5 tests nuevos fallan,
incluido el de la regeneración destructiva.

#### Lo que BE-09 no necesitaba

El plan pedía pydantic en billing. No hace falta: `validate_plan()` ya valida
tier e intervalo en la capa de servicio y devuelve 400. El agujero real era el
**tipo del cuerpo**, no los campos.

---

## Pendiente

### Bloqueado por falta de Docker

Docker Desktop no estaba levantado, así que estas dos quedaron fuera. **No se
aplicaron a medias: no se tocaron.**

#### 1. Verificar en vivo las 308 antes de archivar `frontend_vanilla` en GitHub

La copia local se borró (el repo está limpio, pusheado y el remoto intacto:
`git clone https://github.com/iagentshub/frontend_vanilla.git` lo recupera).
**El repo de GitHub sigue vivo y así debe seguir hasta hacer esta comprobación.**

La equivalencia de rutas se probó estáticamente, comparando una a una lo que
servía vanilla con lo que cubren React y la redirección 308. Apareció un único
hueco, `/skills`, ya corregido (era un alias legacy a `/knowledge`, y Flutter no
tiene ruta `/skills` porque las skills viven dentro de Conocimiento).

Falta recorrer con navegador, sobre la imagen unificada levantada:

```
/            /docs      /pricing     /about      /support
/dashboard   /agents    /orchestrations   /u/<usuario>   /checkout   /skills
```

Las seis últimas deben aterrizar en `/app/...` (Flutter).

#### 2. `USER` en los Dockerfiles — **no es la línea única que decía el plan**

Los cinco contenedores corren como root. El plan original lo daba por trivial;
no lo es, y por eso se dejó pendiente en vez de improvisarlo:

- **`backend/Dockerfile`** — escucha en 8765 (no necesita root) pero escribe en
  el volumen `/data`. Añadir `USER` a secas rompe **las instalaciones ya
  existentes**, porque el volumen creado antes pertenece a root y el proceso sin
  privilegios ya no puede escribirlo. Hace falta un entrypoint que arranque como
  root, ajuste la propiedad de `/data` y baje privilegios (`su-exec`/`gosu`).
- **`frontend_react/Dockerfile`** y **`docker/Dockerfile.unified`** — nginx
  necesita root para escuchar en el puerto 80. Requiere pasar a
  `nginxinc/nginx-unprivileged` con un puerto >1024, o dar
  `CAP_NET_BIND_SERVICE`. La unificada además lleva supervisord con nginx y
  uvicorn juntos.

Nada de esto se puede verificar sin levantar los contenedores, y un fallo aquí
deja a los usuarios sin poder arrancar tras actualizar.

#### 3. Fragmento compose compartido

El par `watchtower` + `docker-proxy` y el bloque de entorno están copiados
literalmente en tres composes. Se puede unificar con `extends:` o `include:`,
pero **necesita `docker compose config` para validarse** y ese comando exige el
daemon. Reestructurar YAML de despliegue sin poder validarlo no compensa.

---

### Aplazado de la fase 3, con motivo

**Generar tipos de Dart y TypeScript desde el esquema (la otra mitad de FE-05).**
No se puede hacer todavía y no por falta de ganas: casi todos los handlers
parsean el JSON a mano, así que **el esquema no sabe qué campos acepta cada
endpoint**. Generar tipos a partir de él produciría firmas vacías que dan una
falsa sensación de seguridad. Requiere antes cuerpos pydantic en los routers
que faltan. Mientras tanto, el contrato de rutas cubre lo que sí se puede
comprobar hoy: que una ruta no desaparezca en silencio.

### Fase 4 — deuda estructural

| | Qué hacer |
|---|---|
| **BE-11** | `update_user_profile()` en `app/auth/auth.py` **no tiene ni un llamador**, junto con su tabla `_PROFILE_SQL`. Encontrado al buscar quién escribe `birth_date`/`gender`/`country`/`phone`: solo el registro |
| **FE-08** | Tercera grafía del producto, encontrada al integrar: los locales de Flutter dicen «iAgentsHub» sin espacio en `pricing`, `legacy` y `nav` (`app_title`), donde React dice «iAgents Hub». La fase 2 solo unificó `about`, `docs` y `seo` |
| **BE-08** | `admin.py` 1.737 líneas, `db.py` 1.515, `storage.py` 1.146. **No partir por tamaño**: los 77 imports diferidos dentro de funciones señalan dónde está cada ciclo. Empezar por `storage.py`, que son cuatro clases independientes en un fichero |
| **BE-11** | Cinco storages reciben una ruta que ignoran (hay un `# informational only` reconociéndolo). Cuatro `Protocol` de `chat.py` nunca se usan en un `isinstance` y uno declara síncrono un método que se llama con `await`. 36 `except: pass` a triar — prioritarios los de `flog.py:58` y `auth/auth.py:726,814` |
| **BE-10** | Claude pide `"stream": true` y luego acumula la respuesta entera: el usuario no ve nada hasta el final. El camino OpenAI-compat ya resuelve lo difícil (cola, hilo, heartbeat, reintentos de DNS); reutilizarlo cambiando el parser |
| **FE-06** | Flutter tiene **4 `Semantics` en 251 ficheros** y ahora es el único cliente privado. Empezar por navegación y formularios de auth. En React, `@axe-core/playwright` está instalado y sin usar: conectarlo al smoke test que ya existe |
| **OPS-05** | `install.ps1` (714 líneas) no tiene linter mientras su gemelo `install.sh` tiene shellcheck en pre-commit y en CI. El repo orquestador solo hace `py_compile`. Mover `pytest tests/ -q` de pre-commit a CI: una suite entera por commit empuja a saltarse el hook |

---

## Decisiones abiertas

### 1. `iAgents/data/` — no es la copia obsoleta que suponía el plan

Los datos dicen lo contrario de lo que asumía la auditoría:

| | `iAgents/data/hub.db` | `iagentshub/data/hub.db` |
|---|---|---|
| Modificada | **2 ago 2026** | 16 jul 2026 |
| Usuarios | **2** | 1 |
| Agentes | **4** | 1 |

**No se ha tocado.** Si `iAgents/` es la instalación viva, la que sobra es la
otra. Conviene confirmarlo antes de borrar ninguna de las dos.

### 2. El invitado en Flutter

Flutter **no distingue al invitado** tras el login: lo lleva al mismo shell con
la navegación completa. El demo funciona (agentes, conexiones, chat, skills,
conocimiento, memoria) y se abrió además el catálogo público de *Explorar*, pero
si un invitado entra en *Workflows* o *Facturación* verá un 403 donde antes veía
una lista vacía —que "funcionaba" por accidente, no por diseño—.

Lo correcto es **ocultar esas secciones al invitado en el cliente**, no abrir más
endpoints en el backend. Queda por hacer en `app_flutter`.

**Prompts** ya no está en esa lista: es guest-aware por diseño y sus 4
endpoints con rama `is_guest` están abiertos (ver arriba). Los que sí siguen
cerrados y hay que ocultar en el cliente son *Workflows*, *Facturación* y las
acciones de activar/desactivar prompt del grupo.

### 3. Descartado a propósito

- **Centinel (BE-07)** — decisión tomada: se queda como está. Son ~1.460 líneas
  en el backend más ~2.000 portadas a los clientes, pero se usa en soporte.
- **Los 37 `fetch` crudos de vanilla y su linter** — el repo se retira.
- **El modelo blob/relacional de la BD** — la deuda es real (cada consulta por un
  campo interno exige parsear JSON) pero no está dando problemas medibles.

---

## Trampa conocida al escribir tests del backend

Varios módulos importan rutas de `app.config.data` **por valor**
(`from app.config.data import SETTINGS_FILE`). El binding se fija al importar el
módulo, así que si un fichero de test lo importa a nivel superior, queda
apuntando al directorio de colección de pytest y ningún monkeypatch posterior lo
corrige.

Ya mordió: `licenses.py` no estaba parcheado en el conftest y la puerta de
licencias **no se activaba nunca**, devolviendo 200 donde debía dar 403 — en
silencio y solo en la ejecución completa de la suite. Corregido, con un guardia
(`test_el_modulo_apunta_al_settings_de_los_tests`) que falla si vuelve a pasar.

Al añadir un módulo que importe rutas por valor, parchearlo en `patch_data_dir`.
