# Saneamiento — estado y trabajo pendiente

Documento de trabajo del plan de saneamiento derivado de la auditoría del 3 de
agosto de 2026. Recoge lo hecho, lo que queda y las decisiones abiertas.

Última actualización: 5 de agosto de 2026.

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
No se puede hacer todavía: **el esquema no sabe qué campos acepta la mayoría de
endpoints**, porque el cuerpo se parsea a mano. Generar tipos a partir de él
produciría firmas vacías que dan una falsa sensación de seguridad.

Contado al integrar los banners de notificación, el reparto real es **43
cuerpos a mano frente a 23 con pydantic** (65/35), no «casi todos a mano» como
decía esta nota. Y va en la buena dirección: los banners llegaron con un
`NotificationBannerPayload` que valida el rango de fechas en un
`model_validator`. Cada handler que se convierte acerca el codegen a merecer la
pena; el umbral no es «todos», es que quede poca superficie sin describir.

Mientras tanto, el contrato de rutas cubre lo que sí se puede comprobar hoy:
que una ruta no desaparezca en silencio.

### Fase 4 — deuda estructural

#### Hecho

**OPS-05 — el instalador de Windows no arrancaba.**
Poner un linter a `install.ps1` era, sobre el papel, la tarea más aburrida de
la lista. Lo primero que devolvió PSScriptAnalyzer fueron **25 errores de
parseo**. No eran del analizador: el fichero estaba en UTF-8 **sin BOM**, y
Windows PowerShell 5.1 —el shell por defecto de Windows, el que usa cualquiera
que siga el README— lo lee como ANSI. Cada carácter de caja de las cabeceras
(`╔`, `═`, `╣`) son tres bytes UTF-8 que se convierten en tres caracteres
basura; uno de ellos rompe el cierre de una cadena, y a partir de ahí los `>`
de las líneas siguientes se parsean como **redirección de salida**. El
instalador solo funcionaba bajo pwsh 7.

El arreglo son tres bytes. Lo que costó fue mirar.

La verja no puede ser "que CI lo parsee": el runner es pwsh 7 sobre Linux y
lee UTF-8 sin BOM perfectamente, así que quitar el BOM otra vez pasaría
inadvertido. Se comprueban **los bytes** explícitamente, en pre-commit y en el
workflow. El analizador va detrás, limitado a `Error,ParseError`: de las 85
advertencias restantes 61 son `Write-Host`, que en un instalador de consola es
justo lo que hay que usar, y 20 son falsos positivos de variables asignadas
dentro de un `ForEach-Object` (que sí conserva el ámbito del llamador —
comprobado, no supuesto).

También entra `ruff` sobre `gaia.py`, que ya pasaba limpio.

**OPS-05 — `pytest tests/ -q` fuera de pre-commit.**
CI ya corría la suite entera en cada push y cada PR, así que el hook eran 14
minutos duplicados por commit. Un cuarto de hora es exactamente lo que empuja a
tirar de `--no-verify`, y eso además se salta ruff. Se quedan tres guardianes
estructurales, **20 s**: contrato de rutas, frontera del invitado y `json_body`.
No son tests de negocio; vigilan que el contorno de la API no se mueva sin que
nadie se entere. Es el fallo que sale barato en el commit y caro tres commits
después — el de prompts de la integración anterior habría saltado aquí.

**BE-11 — código muerto y silencios.**
`update_user_profile()` y su tabla `_PROFILE_SQL`: borrados, junto con los tres
tests que existían solo para darles cobertura. No hay endpoint que edite el
perfil, así que los campos se escriben en el registro y no se vuelven a tocar
nunca. Si algún día hace falta editarlos, la función vuelve con su endpoint.

Los cinco `_db_path` que ninguna clase leía: borrados. El **parámetro** se
queda, porque lo pasan una veintena de sitios y quitarlo es un barrido por
ficheros que ahora mismo están recibiendo commits de otros; el campo no, porque
hacía creer que cada storage hablaba con *ese* fichero cuando la conexión la
abre siempre `open_db()` con la config global.

Los `Protocol` de `chat.py` se quedan —evitan un import circular con
`app.storage.storage`— pero sin `@runtime_checkable`, que hacía creer en una
comprobación en tiempo de ejecución que nunca existió, y con `_MemoryStorage` y
`_SkillStorage` declarados `async`, que es como se les llama desde el primer
día.

Dos `except: pass` pasan a registrar: el del purgado por GDPR, que se tragaba
en silencio el agente de un usuario que había pedido que le borraran los datos,
y el de la verificación de `.admin_pass`, que era la diferencia entre "la
contraseña del fichero sirve" y "gaia.py enseña una obsoleta". El de
`flog._drop_conn` se queda mudo a propósito, con comentario: se llega ahí
porque la conexión ya falló, y logear desde el handler de logs es montar una
recursión.

Segunda pasada sobre BE-11: **17 silencios menos**. Los tres del export GDPR
ahora distinguen JSON malformado de fallos inesperados, conservan el dato bruto
cuando procede y dejan aviso; el fallo al escribir o proteger `.admin_pass`
también registra el `OSError` sin impedir el arranque. En las migraciones SQLite
se han eliminado otros trece: las columnas se añaden mediante una operación
idempotente que solo tolera la carrera entre procesos si comprueba que la
columna ya apareció, y la limpieza de tokens antiguos ya no oculta errores de
esquema o de escritura. El inventario baja de **33 a 16**.

Tercera pasada sobre BE-11: **cerrado el inventario de silencios**. El recuento
anterior omitía dos `pass` de salud del servidor porque el comentario estaba en
la propia línea del `except`; por tanto quedaban 18, no 16. Los 18 han salido:
locales, knowledge y SSE de agentes; parsing de streaming; sincronización y
prueba de recursos; Watchtower y las tres métricas opcionales de administración;
y los siete de Centinel. Las degradaciones parciales siguen siendo degradables,
pero registran qué se omitió. En Centinel, además, una cola llena descarta el
evento viejo y conserva el más reciente, evitando perder un `done`/`aborted` y
dejar el SSE esperando para siempre. Las cancelaciones esperadas se expresan con
`contextlib.suppress` y los fallos de proceso o estado compartido dejan aviso.

Un barrido AST confirma que el único `except` con `pass` que queda en `app/` es
`flog._drop_conn`, el silencio deliberado ya documentado: el propio logger no
puede logear que falló cerrando su conexión sin arriesgar recursión. Verificado
con Ruff completo y **227 tests** de las rutas y servicios afectados.

Cuarta pasada sobre BE-11: **cerrado el falso contrato `db_path`**. Los siete
storages respaldados por SQLite (`AccountStorage`, `BillingStorage`,
`ChatStorage`, `ConnectionStorage`, `GroupStorage`, `GroupShareStorage` y
`KnowledgeStorage`) ya no aceptan una ruta que nunca utilizaban: la conexión
sigue abriéndose mediante `open_db()` y su configuración global. Se han
actualizado las **68 llamadas** y retirado **42 imports** que quedaron muertos,
incluidos los imports de `DB_FILE` por valor. Un test de contrato fija las siete
firmas sin argumentos; el barrido AST no encuentra llamadas antiguas ni otro
constructor de storage con `db_path`. Verificado con compilación, Ruff, **86
tests de storage** y **312 tests** de las rutas y flujos afectados. El único
constructor que conserva `db_path` es `flog._DBHandler`, que sí abre esa ruta.

**FE-08 — tercera grafía.**
«iAgentsHub» → «iAgents Hub» en `pricing`, `legacy`, la navegación y un stub de
billing, en los dos idiomas. Con un test que recorre `lib/` y `assets/locales/`
para que no haya una cuarta, porque nadie se lee los `.json` de locales enteros.
Ojo: el nombre **nativo** de la app sí es «iAgents» a secas, y eso no se toca.

**BE-10 — Claude ya escribe según genera.**
Pedía `"stream": true` y luego se guardaba los deltas hasta tener la respuesta
entera: era el único proveedor donde el usuario miraba una pantalla quieta toda
la generación y luego le aparecía todo de golpe. La maquinaria que hacía falta
—cola, hilo, heartbeat cada 10 s para que nginx no confunda la espera con un
cuelgue— ya estaba escrita a mano dentro de la rama OpenAI-compat. Se ha sacado
a `_stream_tokens()` y ahora la usan las dos, en vez de copiarla: treinta líneas
duplicadas de cola y heartbeat son como se acaba arreglando el bug en una sola.

`asyncio` estaba diferido dentro de `stream_chat()`. Es stdlib, no había ciclo
que romper; sube al principio del módulo. Uno menos de los 77.

El test comprueba que salen cuatro eventos `token` en orden para cuatro deltas,
y se ha verificado que **falla** si se desconecta el callback.

**BE-12 — Ollama también, y ya están los tres.**
Salió de documentar BE-10: al escribir «los dos caminos usan el helper» había
que mirar el tercero, y Ollama pedía `"stream": False` y devolvía la respuesta
de una vez. Al menos era honesto —no prometía un stream que luego no daba— pero
el usuario veía exactamente lo mismo que con Claude: una pantalla quieta y todo
de golpe.

Con `_stream_tokens()` ya hecho, el arreglo fue un `on_token` y cambiar el
parser: **Ollama responde NDJSON**, un objeto JSON por línea, no SSE, así que
no hay prefijo `data: ` que quitar. El recuento de tokens solo viene en el
último objeto, el del `done:true`.

Mismo test que en Claude, y también verificado desconectando el callback.

**BE-08 — la premisa era falsa, y eso cambia el trabajo.**
El plan decía: «no partir por tamaño; los imports diferidos dentro de funciones
señalan dónde está cada ciclo». Medido: **131 imports diferidos y 4 ciclos
reales** en 105 módulos. Y tres de los cuatro son la jerarquía de modelos de
agente (`models.agent` con `openai_agent`, `github_agent` y `claude_agent`),
que es el patrón normal de una clase base que conoce a sus subclases para
construirlas. El único ciclo de verdad discutible es
`routes.accounts ↔ routes.connections`.

O sea: los imports diferidos **no marcan ciclos**. Marcan dos cosas distintas
que conviene no confundir:

1. **Los que deben quedarse.** 27 son de `app.config.data` y `app.config.session`
   — rutas y config que los tests reescriben. Subirlos los congelaría al
   directorio de la fase de colección: es exactamente la trampa que documenta
   `CLAUDE.md`, la que hizo que la puerta de licencias no se activara nunca.
2. **Los que son costumbre.** El resto.

Hecho en `storage.py`, que era el punto de partida que marcaba el plan: tenía
**33 diferidos, 31 de ellos a `app.storage.db`**, y `db.py` no alcanza a
`storage.py` ni directa ni indirectamente. Arriba los 31; el fichero baja de
1.439 a 1.403 líneas y el total de diferidos de 162 a 131.

`IS_PG` es el caso interesante y no se sube: es un **booleano** que el conftest
reescribe con `monkeypatch.setattr(db, "IS_PG", False)`. Traerlo por valor
congelaría el del arranque y, en una máquina con `DATABASE_URL` a Postgres, la
suite entera generaría SQL con marcadores `$n` contra SQLite. Se lee como
`_db.IS_PG`, que consulta el valor en cada llamada. Hay un test que falla si
alguien lo reintroduce por valor — no comprueba comportamiento sino la forma
del módulo, porque el fallo solo se ve en el entorno de otro.

Queda partir los ficheros grandes de verdad (`admin.py` 1.786, `db.py` 1.515),
pero ahora con el criterio correcto: por responsabilidad, no persiguiendo
ciclos que no existen.

**BE-08 — completado el corte por responsabilidad.**
`admin.py` deja de ser un router monolítico de 1.786 líneas y pasa a ser un
paquete con un router compartido y cinco módulos: actualización, estadísticas,
usuarios, recursos y exploración. La superficie pública no cambia: el contrato
conserva las 220 rutas y los tests que parcheaban colaboradores internos apuntan
ahora al submódulo propietario.

`db.py` baja de 1.556 a **262 líneas** y queda limitado a detección del backend,
`AsyncConn` y ciclo de vida de conexiones. Las 1.307 líneas de migraciones
SQLite/PostgreSQL viven en `db_migrations.py`; `migrate_schema()` sigue siendo
el único orquestador público. El helper de compactación que usa el storage se
importa directamente desde el módulo nuevo, sin fingir que pertenece a la capa
de conexión.

Verificado con Ruff, compilación de los módulos, **165 tests críticos**
(administración, auth relacionada, contrato de rutas, frontera de invitado,
guardia de `json_body` y migraciones) y la suite completa de storage:
**219 pasan, 1 skip**.

Ese subconjunto no lo detectó: `__init__.py` importaba sus submódulos con
`from app.api.routes.admin import (...)` — su propia ruta absoluta — y el
detector estático de ciclos (`tests/test_ciclos_de_import.py`) lo lee como el
módulo importándose a sí mismo. Salió al correr la suite **completa**
(`1 failed, 1556 passed`), no en el subconjunto dirigido: exactamente el caso
que el guardián existe para atrapar. Arreglado a `from . import (...)` —
import relativo, el idiomático para un `__init__.py` que agrega sus propios
submódulos — y no vuelve a aparecer en una segunda pasada completa
(**1557 passed, 1 skipped, 0 failed**). El corte de responsabilidad y el
retiro del contrato `db_path` (cuarta pasada) y el endurecimiento de
silencios en auth/licenses/gdpr/Centinel (tercera pasada de BE-11, ver abajo)
quedaron mezclados en un único commit: los cambios se pisaban archivo por
archivo (p. ej. `storage.py` lleva a la vez el origen nuevo de
`_compact_resource_data` y la eliminación de `ConnectionStorage.__init__`) y
separarlos a mano con `git add -p` era más riesgo que beneficio para una
prolijidad de historial.

**FE-09 — la UI de banners ya tiene red.**
Los 33 ficheros de `bbf6c23` entraron sin un solo test. Ahora hay **20**, en
dos ficheros: el modelo y los dos repositorios por un lado, y por otro la
tarjeta de administración y el diálogo de alta y edición, montados a través de
`AdminPage` porque son `part` privados. La suite de Flutter pasa de 187 a 207.

No se tocó nada de `lib/`. Los tests se validaron **rompiendo el código de
producción a propósito**, ocho veces —quitar el `sort`, invertir la comparación
del rango, anular la validación del formulario, saltarse la confirmación de
borrado, quitar el `Uri.encodeComponent` del id, cambiar el `put` por `post`,
hacer que `_safeList` propague en vez de devolver vacío— y comprobando que cada
mutación tumbaba el test que le tocaba.

Un detalle que salió al hacerlo: **no hay lógica de vigencia en el cliente**.
Quién está vigente lo decide `/api/settings/notification-banners/active` en el
servidor y Flutter solo pinta lo que llega. La única regla temporal del cliente
es la validación del formulario, y ahí las fronteras que importan son el rango
invertido y el de duración cero — que es justo lo que distingue un `isAfter` de
un `isBefore` negado.

**El conflicto de Ollama, que conviene recordar.**
BE-12 y un commit de `origin` tocaron a la vez la firma de `_do_ollama_call`:
uno le añadía `api_key` como cuarto parámetro y el otro `on_token`. Git lo marcó
como conflicto —eso salió bien— pero la resolución obvia era la peligrosa:
`_stream_tokens` llama a `fn(*args, _on_token)`, con el callback como **último
posicional**, así que dejar `api_key` detrás habría metido la función de
callback dentro de una cabecera `Authorization`. Sin excepción, sin test rojo:
un `Bearer <function _on_token at 0x...>` viajando al proveedor.

Resuelto con `api_key` antes y `on_token` el último, y un comentario en la
firma diciendo que ese orden no es negociable. La lección general: cuando el
conflicto es sobre **el orden de unos parámetros posicionales**, que compile y
que los tests pasen no demuestra nada — hay que comprobar qué argumento acaba
en qué sitio.

**OPS-06 — `CLAUDE.md` estaba fuera de todo repo.**
Vivía solo en la raíz de la carpeta de trabajo, que no es un repo: sin
historial, sin sincronizar, y perdido en cuanto alguien clonara de cero. Ya son
12 KB describiendo justo lo que sale caro redescubrir — la trampa del import
por valor, el BOM del instalador, la regla del invitado, los ciclos que no
existen.

No se puede simplemente mover: Claude Code lo carga desde la raíz de la carpeta
de trabajo, y este repo es un **hermano** de esa raíz, no un padre. Si se
mueve, deja de cargarse. Así que la copia versionada vive aquí y la de la raíz
se queda donde tiene que estar.

Dos ficheros iguales derivan solos, de modo que hay un hook que los compara
byte a byte. Si falta el de la raíz no dice nada, porque en CI y en un clon
suelto no existe.

**FE-06 — accesibilidad.**
El «4 `Semantics` en 251 ficheros» del plan asustaba más de lo debido: en
Flutter, un `Tooltip` que envuelve ya pone la etiqueta semántica, y la
navegación entera los tenía. Contando bien —mirando también lo que envuelve al
botón, no solo sus argumentos— quedaban **once** botones de solo icono sin
ningún nombre accesible: un lector de pantalla anunciaba «botón» y nada más.
Entre ellos el de mostrar/ocultar contraseña del login y los de enviar y detener
del chat. Ya tienen `tooltip:`; las cadenas `show_password`/`hide_password`
llevaban traducidas desde siempre sin que nadie las usara.

En React, `@axe-core/playwright` llevaba en `package.json` sin que lo importara
nadie. Ya hay un spec que audita las cinco páginas públicas contra WCAG 2.1 A y
AA. **Pasan las cinco sin tocar nada**: 12 reglas evaluadas, 0 incumplimientos.
Solo las normativas, no las `best-practice` de axe, que traen criterios
discutibles y convertirían la verja en ruido. CI ya corría todos los specs de
`e2e/`, así que entra sola.

Los dos guardianes se han verificado rompiéndolos a propósito. El de Flutter
tuvo dos falsos negativos antes de servir: buscaba «tooltip» como subcadena y
el comentario que explicaba el arreglo contenía la palabra, así que el test
pasaba justo en el botón que lo había motivado.

Segunda pasada sobre FE-06: **teclado y contraste del tema central cubiertos**.
El único `GestureDetector` accionable que quedaba era cada nodo del grafo de
recursos: se podía abrir y arrastrar con ratón, pero no alcanzarlo con Tab ni
activarlo sin puntero. Ahora cada nodo expone semántica de botón, entra en el
recorrido de foco con un contorno visible y responde a Enter y Espacio; el
gesto de arrastre se conserva. Una regresión recorre el diálogo con Tab y abre
la vista rápida con Enter. Otra fija el orden inicial de la navegación lateral:
Dashboard → Explorar → Agentes.

Los acentos tampoco cumplían siempre como texto o fondo: naranja sobre blanco
quedaba en **2,80:1**, y red, azul y púrpura sobre el fondo oscuro no llegaban
a **4,5:1**. El tema deriva ahora la variante mínima más cercana que supera AA
contra su superficie y elige negro o blanco para `onPrimary`; el mismo color se
aplica a `FilledButton`. Un guardián recorre los **14 identificadores de tema**
y exige 4,5:1 en las dos combinaciones. Verificado con análisis dirigido sin
incidencias y **22 tests** de tema, grafo, navegación y botones.

**FE-10 — contratos de banners cerrados.**
Editar y borrar comparten ahora la misma validación del identificador: un `id`
ausente, vacío o de tipo incorrecto no abre el formulario ni la confirmación,
no llama al backend y muestra un error localizado. Esto elimina tanto el
`CastError` del borrado como la recreación accidental que podía provocar la
ruta de edición al interpretar un `id` ausente como un alta.

`NotificationBanner.fromJson` ya no convierte cualquier valor de `message` a
texto. El contrato de `/active` exige una cadena ya resuelta en el idioma del
usuario; recibir el mapa interno de idiomas o cualquier otro tipo provoca un
`FormatException` explícito en vez de pintar su representación de depuración.
Verificado con análisis dirigido sin incidencias, JSON de locales válido y
**21 tests** de modelo, repositorio y widget. El análisis global conserva **19
avisos informativos preexistentes**, todos fuera de los ficheros de FE-10.

**FE-06 — colores de estado de Admin y Centinel, derivados AA.**
Verde/naranja/rojo escritos como literal se pintaban como texto o icono
directamente sobre `scheme.surface` — la tabla de logs (`_levelColor`), el
veredicto de una prueba de Centinel (`_verdictBanner`) y el aviso de tope de
usuarios (`_capNotice`) — fuera del contrato de `ColorScheme`: la misma
constante pasa AA en un tema y falla en el otro, igual que el naranja de la
primera pasada de FE-06. `AppTheme.statusColor(color, surface)` expone la
derivación que ya usaba `_accessibleAccent` para los 14 identificadores;
donde el fondo lleva un tinte al 12 % del color semántico, ese fondo se
conserva y solo el texto/icono se deriva. Las badges compartidas
(`OriginBadge`, `InactiveBadge`, `ResourceTypeBadge`) se revisaron y no
tenían el bug: fondo sólido + texto blanco fijo, no dependen de
`scheme.surface`. Verificado con `flutter analyze` (19 avisos preexistentes)
y **213 tests**, incluido uno que exige 4,5:1 para `statusColor` contra las
dos superficies.

Con esto, FE-06 no tiene pendientes abiertos.

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
si un invitado entra en *Workflows* verá un 403 donde antes veía
una lista vacía —que "funcionaba" por accidente, no por diseño—.

Lo correcto es **ocultar esas secciones al invitado en el cliente**, no abrir más
endpoints en el backend.

**Prompts** ya no está en esa lista: es guest-aware por diseño y sus 4
endpoints con rama `is_guest` están abiertos (ver arriba). *Workflows* y las
acciones de activar/desactivar prompt del grupo sí seguían cerradas y ya se
ocultan en el cliente: `_visibleMainItems(role)` saca `workflows` del catálogo
de navegación para `role == 'guest'` (sidebar expandido y rail contraído leen
del mismo catálogo, así que basta un cambio), y el botón de activar/desactivar
de la tarjeta de Prompts comprueba el mismo rol. 210→212 tests, dos nuevos
cubren el sidebar y el rail.

**Facturación queda fuera, y no por descuido.** No hay una entrada de sidebar
llamada "Facturación" que ocultar: el perfil lee `/api/billing/subscription`
y ya traga cualquier error (403 incluido), cayendo a `tier: 'free'` — el
invitado nunca ve un fallo ahí. El único punto sin guardia es el checkout
público (`/app/checkout`), alcanzable desde Precios sin sesión siquiera; si un
invitado intenta suscribirse, la llamada a `/api/billing/subscribe` falla y el
error se muestra inline en la propia página, no como un 403 crudo. Cerrarle el
paso a un invitado ahí es una decisión de producto (¿bloquear antes de
intentar? ¿redirigir a registro?), no un ocultamiento mecánico como los otros
dos. Queda abierta.

### 3. Descartado a propósito

- **Centinel (BE-07)** — decisión tomada: se queda como está. Son ~1.460 líneas
  en el backend más ~2.000 portadas a los clientes, pero se usa en soporte.
- **Los 37 `fetch` crudos de vanilla y su linter** — el repo se retira.
- **El modelo blob/relacional de la BD** — la deuda es real (cada consulta por un
  campo interno exige parsear JSON) pero no está dando problemas medibles.

### 4. Resuelta — la divergencia de `CLAUDE.md` no existía

Esta entrada describía un problema que **no se sostiene al mirar el disco**, y
se deja escrita en vez de borrarse porque el error es instructivo:

| Lo que decía | Lo que hay |
|---|---|
| existe `iAgents/CLAUDE.md`, 274 líneas | **no existe**: `iAgents/` solo tiene `data/` |
| `gaia.py` está en `iAgents/` | está en `iagentshub/` |
| el de la raíz tiene 76 líneas | tiene **274** |
| los dos han divergido | **idénticos**, 12.115 bytes cada uno |

O sea que la raíz describe el reparto de carpetas correctamente y no hay nada
que fusionar. Lo que sí era cierto es la pega al hook: `files: ^CLAUDE\.md$`
solo lo dispara cuando ese fichero entra en un commit **de este repo**, y la
copia que se edita a diario es la de la raíz, que no está en ningún repo. Podía
reescribirse entera sin que saltara nada — que es probablemente lo que hizo
pensar que había pasado. Ya corre con `always_run`: comparar dos ficheros son
microsegundos.

La lección, que aplica a todo este documento: **una afirmación sobre el
contenido del disco se comprueba con `ls` antes de escribirla.** Esta llegó a
convertirse en una decisión abierta con dos opciones de resolución, ninguna de
las cuales tenía sentido.

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
