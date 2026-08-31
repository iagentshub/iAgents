# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in
this working folder. It covers all five clones, so it is the one document
that goes stale without any single repo's tests noticing — check what you
read here against the tree before relying on it.

## This directory is not a repository

`all_iagenthub/` is a working folder holding **five independent git clones**.
There is no umbrella repo, no submodules, no workspace file.

| Directory | What it is |
|---|---|
| `backend_fastapi/` | FastAPI. The only server. Python 3.12 in the image, 3.11 locally. |
| `frontend_react/` | React 19 / Vite / TS. **Public pages only** — landing, pricing, docs, about, support. Also the nginx image that fronts everything. **El único repositorio privado**: el workflow que publica la imagen lo lee con `REPO_READ_TOKEN`, ver más abajo. |
| `app_flutter/` | Dart 3 / Flutter. The **entire authenticated app**, served under `/app/`. |
| `vs_code/` | VS Code extension. Talks to the backend with a PAT. |
| `iAgents/` | Orchestrator: `gaia.py`, `install.sh`, `install.ps1`, the compose files. Ships no product code — **and holds the live data** under `data/` (`hub.db`, `settings.json`), which is gitignored. |

Each directory name matches its remote under `github.com/iagentshub`
(`iagentshub/backend_fastapi`, `iagentshub/iAgents`, …). Older docs call the
backend `backend/` and the orchestrator `iagentshub/`; those names are retired
and GitHub will not give them back.

**No change is atomic across repos.** A contract change means separate commits
in separate repos that land at different times. **Backend first, always** — it
is the one every client depends on.

Each clone has its own `main`, its own CI, and its own remote under
`github.com/iagentshub`.

## Commands

Run these from inside the relevant clone, not from this folder.

### backend_fastapi

```bash
python3.11 rtests.py                               # full suite, ~4 min (1998 tests)
python3.11 -m pytest tests/api/test_routes_auth.py -q
python3.11 -m pytest tests/api/test_x.py::test_y -q
ruff check .
ruff check . --fix
python3.11 main.py                                 # dev server, port 8765
```

**Use the 3.11 interpreter explicitly.** There is no `.venv` here; on macOS
plain `python3` resolves to Xcode's 3.9 and every test fails on import. The
absolute path is `/opt/homebrew/bin/python3.11`. `rtests.py` is the entry point
that passes the flags `pytest.ini` expects (`--timeout=30`).

Pre-commit runs ruff plus three structural guards (`tests/api/test_contrato_rutas.py`,
`tests/api/test_guest_boundary.py`, `tests/utils/test_json_body.py`) — 20 s, not
the full suite. CI runs everything on push and PR. The guards are there to catch the API surface
drifting silently: a route vanishing, an endpoint changing guard, a handler
going back to raw `request.json()`.

`requirements.lock` is consumed with `--require-hashes`; regenerate it
with `pip-compile --generate-hashes`, never by hand.

After deliberately adding or removing a route:

```bash
python -m pytest tests/api/test_contrato_rutas.py --actualizar-contrato
```

### frontend_react

```bash
npm run check     # typecheck + lint + public:verify + csp-hash + test + prerender + seo:verify
npm test          # vitest run
npm run dev
```

`npm run check` is the gate, and `public:verify`
(`scripts/verify-public-only.mjs`) is what keeps React public-only. It fails on
three things, and the last one surprises people:

- a forbidden dependency — `@dnd-kit/core`, `@dnd-kit/sortable`,
  `@hookform/resolvers`, `@xyflow/react`, `react-hook-form`, `thinking-orbs`,
  `zod`. These belong to the authenticated app, which is Flutter.
- a route area outside `public` / `shared`.
- **the locale file list, which is frozen exactly**: `about`, `common`, `docs`,
  `landing`, `legal`, `pricing`, `seo`, `support`. Adding a locale file breaks
  the build until you add it to the script too.

`check` does **not** run the Playwright specs; they need a build and a server,
so CI runs them (`test:e2e:chromium`, every spec in `e2e/`). Among them
`a11y.spec.ts` audits the seven public pages with axe against WCAG 2.1 A and AA
— normative rules only, not axe's `best-practice` tag, which brings arguable
criteria that would turn the gate into noise. Run it locally with
`npx playwright test a11y --project=chromium`.

#### Adding a public page is six files, not one

A route in `router.tsx` is the part everyone remembers. The build then fails on
the rest, one gate at a time:

- `scripts/public-routes.mjs` — the single manifest that prerender, sitemap and
  `seo:verify` all read. A page missing here is never prerendered, so nginx
  404s a route the router swears exists.
- `src/i18n/public-paths.ts` — `publicBasePaths`, which types `Seo`'s
  `localizedPath` and drives the language switch. The `/en` variant is derived,
  never written out, so base paths are English words even in Spanish.
- `src/i18n/index.ts` — the `ns` list. The glob already loads the file; without
  the namespace `t()` returns the raw key.
- `scripts/verify-public-only.mjs` — the frozen locale list above.
- `assets/locales/{es,en}/seo.json` — `seo:verify` demands one `<title>`, one
  description, one `<h1>` and reciprocal hreflang per page.

nginx needs nothing: `try_files $uri $uri.html` already serves `dist/x.html`.

### app_flutter

```bash
flutter test
flutter test test/backend_url_test.dart
flutter analyze          # exits non-zero on infos, so `analyze && test` short-circuits
```

`app_flutter/CLAUDE.md` holds the conventions of that repo (state, listings,
i18n, file-size limits). What follows is only what a cross-repo change needs.

Several tests here assert facts about the tree rather than behaviour, so they
fail on files you may not think you touched:

- `a11y_iconos_test.dart` — every icon-only button needs an accessible name,
  from `tooltip:` or a wrapping `Tooltip`/`Semantics`. A screen reader
  announces an unnamed one as "button" and nothing else.
- `branding_config_test.dart` — the product is **"iAgents Hub"**, never
  "iAgentsHub". Note the *native* app name is plain "iAgents" and that is
  deliberate; the test only chases the concatenation.
- `backend_url_test.dart` — shares its case table with `vs_code/src/test/
  url.test.ts`. Change one, change both.
- `i18n_sin_literales_test.dart`, `i18n_claves_existentes_test.dart` and
  `locales_sin_huerfanos_test.dart` — the
  language is a **code, never a boolean**. `isEnglish ? … : …` and
  `languageCode == 'en' ? … : …` are banned in `features/auth`,
  `features/public`, `shared/widgets`, `shared/i18n` and `shared/state`: with a
  third language they don't fail, those screens just stay in Spanish. The second
  test compares `assets/locales/{es,en}/` against the namespaces the code
  actually loads — there are **five** (`resources`, `auth`, `common`, `nav`,
  `pricing`), and there used to be 25 files per language, 284 KB of bundle that
  nobody read. Translation takes **one argument**, the id: `tr('agents.publish')`,
  from `lib/utils/i18n.dart`. Calls used to carry the Spanish text as a fallback
  too, which hid every undeclared key — it looked right in Spanish and stayed
  Spanish in English. 50 had slipped through, including the activate/deactivate
  buttons on four screens. A missing key now shows the **id** and warns in the
  console. **The first segment of an id is the namespace the key lives in**:
  `tr('auth.identifier_required')` resolves only while `auth` is loaded, and a
  screen loads its own namespace, not all five. Eight `auth.*` keys and six
  `common.*` ones sat in `resources.json`, so the login screen printed the id
  in the username field and in the «coming soon» tooltip — the existence check
  never saw it, because it merges the six files into one set and forgets which
  one each key came from. The second guard in that same file is what notices,
  and it only looks at `tr()`/`trOr()`: the other three forms carry the page's
  bundle in front, so a key of theirs is found there whatever its prefix says.
  **Do not copy React's locale files here**: React has its own
  frozen list, and that is where this came from. The conventions are in
  `app_flutter/CLAUDE.md`.
- `feature_architecture_test.dart` — among other things, **a dialog is opened
  with `showAppDialog`, never with `showDialog`**. The helper (in
  `shared/widgets/motion/`) adds the app's transition and, more to the point,
  drops it entirely when the system asks for reduced motion. A direct call
  breaks nothing visible — the dialog still shows — which is why this test is
  the only thing that notices.
- `web_bundle_budget_test.dart` — **the Flutter version lives in
  `environment: flutter:` of `pubspec.yaml`, exact**, and every workflow that
  compiles the app reads it from there with `flutter-version-file`. See the
  section below: this one spans three repos.
- `deferred_routes_test.dart` — admin, Centinel, metadata, workflows and
  checkout are imported `deferred as` in `lib/app/router/internal_router.dart`
  and mounted through `DeferredPage`, which keeps 777 KB out of the initial web
  bundle. **Only the router may import those five files.** A plain `import`
  anywhere else pulls their code back into the main bundle and nothing visible
  breaks — this test is what notices. A heavy new screen goes in deferred too.

CI runs one more gate that `flutter test` cannot: `tool/check_web_bundle_size.sh`
after `tool/build_web.sh`. It fails if `main.dart.js` crosses the budget
written in the script, or if the build produced no deferred parts at all.

**Compile the web with `tool/build_web.sh`, never `flutter build web` directly.**
Its flags have their other half in the CSP nginx serves — the `location ^~ /app/`
block of `frontend_react/nginx.react.conf`. `--no-web-resources-cdn` keeps
CanvasKit on our own origin, which is why that policy no longer allows
`www.gstatic.com`; build without the flag and the authenticated app comes up
blank, with no error and no failing test. The command used to be copied into six
CI steps across four repos, so changing a flag meant four commits that landed at
different times. `web_bundle_budget_test.dart` fails if a workflow goes back to
calling `flutter build web` on its own.

**There are four callers, not three, and the fourth had no guard.** Besides the
workflows, `gaia build-push` builds the same image from the command line — and
it called `flutter build web` directly, so every image published that way served
an authenticated app that the CSP blanked out. `web_bundle_budget_test.dart`
never saw it: that test only reads files under `.github/workflows`. The guard
for this one is `test_gaia_build_push_compila_la_web_con_el_script` in
`iAgents/tests/test_docker_contexto.py`, which is where the other `build-push`
guards already live.

### vs_code

```bash
npm test          # compiles, then node --test out/test/*.test.js
npm run lint
```

Tests import from `../url`, never `../auth`: `auth.ts` imports `vscode`, which
does not exist outside an extension host.

### iAgents

```bash
python3.11 rtests.py          # 40 tests, ~2 s
```

`tests/test_structure.py` checks the project layout, `test_gaia_cli.py` the
CLI, and `test_backend.py` reaches into the backend clone — `BACKEND_DIR`
overrides its location, default `../backend_fastapi`.

Pre-commit runs shellcheck on `install.sh`, `docker compose config`,
`py_compile` on `gaia.py`, a BOM check on `install.ps1`, and the byte-for-byte
comparison of this file against the root copy. CI adds PSScriptAnalyzer and ruff.

**`install.ps1` must keep its UTF-8 BOM.** Without it, Windows PowerShell 5.1
— the default shell on Windows — reads the file as ANSI, mangles the box-
drawing characters in the banners, and from there parses `>` in later lines as
a redirection operator: 25 parse errors, installer dead on anything but pwsh 7.
CI cannot catch this by parsing (its pwsh 7 reads UTF-8 fine), so the byte
check is explicit in both the hook and the workflow.

## Architecture

### Two frontends, one origin

nginx (`frontend_react/nginx.react.conf`) serves React at the root and Flutter
web under `/app/`, proxying `/api/` to the backend. Public marketing pages are
React; **everything behind a login is Flutter**. Legacy public paths 308 to
`/app/…`. `frontend_vanilla` was a third frontend and is retired.

When you add a public route, it belongs in React. When you add an app screen,
it belongs in Flutter. Putting an authenticated route in React trips
`public:verify`.

**In dev there is no nginx.** `docker-compose.dev.yml` runs Vite's dev server in
that container, and it proxies `/api/` itself — so anything you reason about
from `nginx.react.conf` is not what answers your request while developing. Vite
also used to answer the CORS preflight before the proxy saw it, and without
`Access-Control-Allow-Credentials`: Flutter's browser client sends
`withCredentials = true`, so the browser aborted there and the login POST never
left — no request in the backend log at all, and in Dart a network error with no
body and no stack, visible only in the browser console. `server.cors: false` in
`vite.config.ts` hands the preflight back to the backend, which is the one that
owns `GAIA_CORS_ORIGINS` and the anti-CSRF check. Running the app with
`flutter run` puts it on a different port, so that origin has to be declared:
`GAIA_CORS_ORIGINS` in `iAgents/.env`, passed through by `docker-compose.dev.yml`.

The two directions cross exactly once: **the legal pages**. Privacy and terms
are React (`/privacy`, `/terms`, plus `/en/…`), but Flutter's register screen
has to link to them and gate the submit button on a checkbox — publishing the
documents and never collecting acceptance leaves the contract without proof of
consent. Flutter reaches them with `resolvePublicSiteUri`, not GoRouter: they
live at the origin root, outside `/app/`, so it is browser navigation. Note
the backend still stores neither the date nor the version accepted, so today
consent is required but cannot be evidenced after the fact.

### The Flutter version is one number, in app_flutter's pubspec

Three workflows compile the Flutter app: `app_flutter`'s own CI (both jobs) and
the `docker-publish` of `iAgents` and `backend_fastapi`, which check
`app_flutter` out to build the unified image. A fourth path, `gaia build-push`,
uses whatever the developer has installed.

Only the first one used to pin anything — 3.44.8, written by hand — while the
other two installed `channel: stable` and took whatever shipped that day. Those
other two are the ones that build **the image that actually deploys**, so
production was compiled by an SDK the CI had never validated. Nothing failed:
same app, two SDKs, and the one reaching users was the untested one.

Now `environment: flutter:` in `app_flutter/pubspec.yaml` is the single source
and every workflow reads it with `flutter-version-file`. **The version must be
exact** — the action requires a concrete version, and a range hands the decision
back to each runner. **The path is relative to the workspace**, not to the
step's `working-directory`: it is `app_flutter/pubspec.yaml` everywhere except
`app_flutter`'s own `validate` job, where the repo is the workspace root.

Raising it means editing one file — and then re-measuring the web bundle, since
`check_web_bundle_size.sh` records the version its budget was measured with.
`iAgents/tests/test_docker_contexto.py` fails if a workflow goes back to
deciding its own, reaching the sibling clones the way `test_backend.py` does and
skipping the ones that are not there.

### Two images, and only one of them ships

`ghcr.io/iagentshub/app` is what `install.sh` pulls, built from
`iAgents/docker/Dockerfile.unified` by **three** workflows — `iAgents`,
`backend_fastapi` and `app_flutter` — each with its own "Preparar contexto de
build" step — plus `gaia build-push`, which builds the same image from the
command line. `ghcr.io/iagentshub/backend` is the standalone backend and almost
nobody runs it. **A change to how the backend is packaged has to land in both.**
The unified image installed from `requirements.txt` for a long time while the
standalone used `requirements.lock` with `--require-hashes`: the image that
actually reaches production had the weaker supply-chain guarantee, and nothing
failed.

Docker only reads the `.dockerignore` at the **root of the build context**, and
that root is `build-ctx/`, not the backend clone — so `backend_fastapi/.dockerignore`
does not apply to the unified build. The unified image has its own, versioned at
`iAgents/docker/dockerignore.unified`, which every workflow copies in.

Both ignore files are **allowlists**. Otherwise `COPY . .` and `COPY backend/`
carry `tests/` (14 MB, more than `app/`), `docs/` and the checkout's `.git` into
the published image; the code layer changes on every build, so that weight is
re-downloaded by every install on every update. The backend needs exactly `app/`,
`main.py`, `requirements.lock` and — standalone only — `docker-entrypoint.sh`;
under the unified image supervisord runs `python /app/main.py` directly.

`tests/test_docker_contexto.py` in `iAgents` fails if a workflow — or
`build_push.py` — prepares a context without copying the ignore, or if the
Dockerfile goes back to `requirements.txt`. It reaches the sibling clones the way `test_backend.py` does
and skips the ones that are not there.

**`frontend_react` es privado, y por eso el workflow necesita un token que no
es el suyo.** El `GITHUB_TOKEN` de `iAgents` solo alcanza a `iAgents`: mientras
los cuatro repositorios fueron públicos la API de GitHub respondía sin
credencial, así que nadie se dio cuenta de que el acceso no venía del token.
Al privatizar uno, `verified_revisions.py resolve` empezó a morir con **404 —no
403—** en el primer paso del `preflight`, y con él los cuatro repos: diez runs
seguidos en rojo, ninguna imagen publicada en 28 h, y lo único que lo decía era
la pestaña Actions. El secreto es `REPO_READ_TOKEN`, en `iAgents`, y necesita
**lectura de contenido y de Actions** sobre el repositorio privado: solo con la
primera, `resolve` pasa y es `verify` quien falla, más tarde y en otro sitio.
Lo usan los dos pasos que llaman a `verified_revisions.py` y el `checkout` de
`frontend_react`; sin el secreto se cae de vuelta al token propio y vuelve el
404, que es lo correcto mientras la imagen no se pueda construir sin ese código.

**Y «de Actions», no «de checks», porque el permiso `Checks` no se le puede dar
a un PAT.** `verify` leía `/commits/{sha}/check-runs` — la Checks API, que
GitHub reservó a las GitHub Apps y retiró de la lista de permisos de los PAT
fine-grained. Con los cuatro repos públicos daba igual; con uno privado no
existía credencial acotada capaz de verificarlo, y el único PAT que servía era
uno clásico con scope `repo`, es decir escritura sobre todo. `check_state` pide
ahora `/actions/runs?head_sha=…` y los `/jobs` de cada run: **los cuatro checks
exigidos son jobs de Actions**, así que la respuesta es la misma y el permiso
`Actions: read` sí es asignable. Cuesta una llamada más por workflow run.
`test_no_se_pide_la_checks_api_que_un_pat_no_puede_leer` impide volver.

Y no se puede: de `frontend_react` la imagen no toma solo las páginas públicas,
toma **`nginx.react.conf`, que es el servidor entero** — el `proxy_pass` a
`/api/`, el `location ^~ /app/` con su CSP, `/env.js` y los 308 legacy. Una
imagen construida sin ese repositorio no se queda sin landing: se queda sin
servir la app Flutter y sin API. Hacer el repositorio opcional pasa antes por
mudar ese fichero a `iAgents`, junto al Dockerfile y el supervisord, que es
donde le corresponde estar.

### Authorization is four dependencies

`app/api/routes/auth/dependencies.py` defines the entire authorization surface,
re-exported from the `auth` package (it is a package now, not a module — import
from `app.api.routes.auth`, which is what ~18 files already do):

```python
require_auth          = require_role("standard")        # normal endpoint
require_group         = require_group_role("standard")  # + resolves active group
require_session       = require_role("guest")           # guest allowlist
require_group_session = require_group_role("guest")     # guest allowlist, group-scoped
require_admin                                            # admin only
```

Ranks are `guest:0 < standard:1 < admin:2`. **A new endpoint gets
`require_auth` and is therefore closed to guests.** Add `require_session` when
the endpoint belongs to the caller's own personal space, which is what the
guest now has in full — agents, skills, prompts, tools, knowledge, connections,
memory, workflows, saved chats, preferences. Keep it closed for anything that
is not his: admin, users, billing, platform settings, external OAuth accounts,
PATs and the VS Code pairing (long-lived credentials would outlive the session
that issued them), groups, social, and publishing to Explore.

That line used to be **derived**: an endpoint with an `is_guest(...)` branch was
exactly one that knew how to work against the in-process `GuestSession`. There
is no GuestSession any more — the guest is an ephemeral row in `users` and uses
the same storage as everyone — so the boundary is now a product decision
written down in `tests/api/test_guest_boundary.py`, which asserts both sides.
See `docs/adr/012-el-invitado-es-un-usuario-efimero.md`.

`require_auth` used to alias the `guest` rank, which left ~140 private
endpoints open to guest sessions. Do not widen it back.

### The guest is an ephemeral user, not a dict

`app/storage/guest.py` used to hold the demo session in a process `dict`. With
`GAIA_WORKERS>1` and no session affinity in the proxy, the guest lost his work
between any two requests — the agent he had just created was simply gone, no
error — and `MAX_SESSIONS` was per process, so the real cap was `workers × 200`.

A guest is now **a row in `users`** with `role='guest'`, whose `id` and
`username` are both the `guest:<id>` that already travelled in the JWT — which
is why `is_guest()` is still a prefix check with no query behind it. From there
he uses the same storage as anybody: **there is no `is_guest` branch left in a
handler**, and the 107 there used to be are gone.

What sets him apart is how long he lasts. Logging out runs `purge_user_data` on
him — the GDPR routine — and `purge_expired_guests()` sweeps the ones left
without a live session, hanging off the GDPR purge loop that already existed.
Expiry is **"no live session"**, never a TTL from signup: a TTL deletes the work
of a guest who is still using it.

Two things this hands you:

- **Any query that lists or counts users must exclude them**, or the guest shows
  up in the people search, the admin panel and the stats, appearing and
  vanishing between two reloads. Done in `queries/users.sql`, `auth:list_users`,
  `billing:list_users`, `admin_stats:user_counts`, `explore:user_id_by_username`
  and the public profile in `routes/users.py`.
- **Publishing is the one thing he cannot do**, and it lives in exactly one
  place: `assert_can_publish` in `app/services/publishing.py`, called wherever a
  resource goes public. What he published would vanish with his session.

Ver `docs/adr/012-el-invitado-es-un-usuario-efimero.md`.

### The session is three cookies and a row in the database

`ga_token` (the access JWT, `HttpOnly`), `ga_csrf` (readable by JS) and
`ga_refresh` (`HttpOnly`, scoped to `path=/api/auth`). They are emitted and
cleared together by `set_session_cookies` / `clear_session_cookies` in
`app/auth/cookies.py` — but **a handler that opens a session calls
`app.auth.sessions.open_session`**, which also writes the row that makes the
session revocable. Eight emitters across four modules go through it; one that
skipped the row would mint a token no logout can revoke, and nothing visible
would fail.

The access token carries a `sid` claim and **is not self-sufficient**:
`_assert_session_live()` queries the `sessions` table on every authenticated
cookie request, deliberately without a cache — caching the revoked state would
give back exactly the delay this removes, and with several workers a logout
would only apply in the worker that served it. `GAIA_ACCESS_EXPIRE_MINUTES`
(30) measures the access; `GAIA_JWT_EXPIRE_HOURS` (12) keeps its name but now
measures the **session**, and rotation pushes that deadline forward, so it is
hours of inactivity rather than since login.

`POST /api/auth/refresh` rotates the refresh token and keeps the previous hash
in `prev_refresh_hash`: presenting an already-rotated one means two clients
hold it, and the whole session is revoked. **A client that renews needs a lock**
— Flutter's `ApiClient` has one; without it six in-flight 401s fire six
renewals and the second arrives with a rotated token, which reads as theft.

Revocation happens on logout, `DELETE /api/auth/sessions[/{id}]`, password
change (from `_touch_password_changed_at` — `password_changed_at` alone never
touched the refresh), account deactivation, refresh reuse and GDPR deletion.
**A role change does not revoke**, on purpose: the role is read from the user
row on every request anyway. Changing group reissues the access with the same
`sid` (`reissue_access`), so it does not pile up rows. Ver
`docs/adr/008-sesiones-revocables.md`.

`CsrfMiddleware` puts two layers behind `SameSite=Lax`, which was the only
defence and does not cover a compromised subdomain — for the browser that is
"the same site". Both take `enforce | log | off`:

- `GAIA_CSRF_ORIGIN_CHECK` (default `enforce`) — `Origin`/`Referer` on unsafe
  methods, checked against `CORS_ORIGINS` **and** the request's own host.
- `GAIA_CSRF_TOKEN_CHECK` (default `enforce`) — `X-CSRF-Token` must equal
  `HMAC(secret, ga_token)`. This one needs the clients, so it inverts the
  usual rule: **the backend must not reach production before React and
  Flutter**. A cached bundle that does not send the header 403s on every
  mutation; `log` is the escape hatch and takes no redeploy, just the env var.

Two exemptions, both load-bearing: `Authorization: Bearer` skips everything (a
PAT is not an ambient credential — this is what keeps the VS Code extension
working), and a request with no `Origin` **and** no `Referer` passes layer 1
(Flutter native, the Stripe webhook, curl — a browser cannot be made to omit
`Origin` on a POST). Ver `docs/adr/006-csrf-en-dos-capas.md`.

### Request bodies

**The migration to pydantic is done: not one handler parses JSON by hand.**
This used to be 43 hand-parsed against 23 with a model. Declare a model for a
new endpoint that takes a body; there is no second style to choose from.

`app.utils.net.json_body(request)` was the intermediate step — it guarantees
the body is an object and returns 400 instead of a 500 when someone posts `[]`.
It now has **no callers left**, but the helper and its guard stay:
`tests/utils/test_json_body.py::test_ningun_handler_se_saltó_el_helper` walks
`app/api/routes/` and fails if a raw `await request.json()` reappears anywhere.
If you ever do need to parse by hand, that is the function to call.

`tests/api/contrato_rutas.txt` freezes the set of `METHOD /path`, which is the
one thing that must not drift silently. After deliberately adding or removing a
route, regenerate it with the command above.

It freezes the **set**, sorted alphabetically — not the order of registration,
which is what FastAPI actually resolves by. That matters when you split a route
module into a package: the order then becomes whatever isort does to the
imports in `__init__.py`, and a parametric route registered before a more
specific one makes the specific one unreachable — no error, no failing test,
just `item_id="packs"`. `tests/api/test_rutas_ensombrecidas.py` is the guard for
that. A path parameter does not cross `/`, so only routes with the same number
of segments can collide.

### Chat streaming

`stream_chat()` in `app/services/chat.py` is an async generator of SSE frames.
Providers do their blocking `urllib` work in a thread; `_stream_tokens()` owns
the queue that carries each delta back, plus a 10 s `: keep-alive` heartbeat so
nginx and the client don't read a slow first token as a hang.

**A streaming provider goes through `_stream_tokens`, never
`await asyncio.to_thread(...)` directly.** Claude and Ollama both did the
latter for a long time and the user watched a still screen until the whole
reply landed. All three paths use the helper now.

The wire format differs and the parser is the only part that should:
OpenAI-compat and Claude send SSE (`data: ` prefixed), **Ollama sends NDJSON**
— one JSON object per line, no prefix.

### Storage is dual-mode

`app/storage/db.py` targets SQLite (aiosqlite, WAL) or PostgreSQL (asyncpg
pool) from the same code, switching on `IS_PG` with `?` / `$n` placeholders.
Write SQL that works in both; `lower(…)` is fine, dialect-specific syntax is
not.

Rows are largely JSON blobs, so querying by an inner field means parsing JSON
in Python. Known debt, deliberate.

### The SQL lives in files, not in string literals

**Static SQL goes in `app/sql/` and the code asks for it by identifier.** There
is no second style: `tests/storage/test_sql_en_ficheros.py` walks `app/` and
fails if a constant `SELECT`/`INSERT`/… reaches a database call again.

```python
sql("schema/agents")           # app/sql/schema/agents.sql, whole file
sql("queries/agents:get_any")  # the `-- name: get_any` section
```

The schema is **one file per table** (36 of them, indexes alongside), because
consumers want a single table — `flog` creates `app_logs` before `init_db` and
used to carve it out of the full DDL by substring. Queries are **grouped per
module with sections** (43 files, 457 sections); a file per statement would be
six hundred files. `schema.py` keeps only what isn't SQL: the ordered table
list (foreign keys) and the per-dialect marker table. `SCHEMA_SQLITE` and
`SCHEMA_PG` still exist with the same value.

Three things stay in Python **on purpose**: the ~66 queries built at runtime
(optional filters, variable-length `IN`, table as a parameter), the `PRAGMA`s
in `db.py`, and `storage/migrations/` — a historical sequence whose SQL is
interleaved with the Python that transforms the data.

The exception is a query that is static except for the **length** of an `IN`
list. That one lives in the file with a `@name@` marker — the same marker
convention the schema uses for per-dialect types (`@BOOL@`, `@SERIAL@`) — and
the caller substitutes as many `?` as it has elements
(`resource_relations:workflow_agent_presentations` is the only one today).
`test_sql_contra_motores.py` resolves the marker to a single `?` before
preparing, so the query is still validated against both engines; leaving it out
would have excluded exactly the kind of query nobody sees on PostgreSQL until
deployment.

**The migration duplication between `sqlite.py` and `postgres.py` is closed.**
Those two files are now just their runner. The steps live in
`storage/migrations/steps/`, grouped by domain with **both dialects side by
side**, and the list of steps is declared **once**: `MIGRATION_PAIRS` holds one
`MigrationPair(version, name, sqlite, postgres)` per step, and each engine's
tuple is derived from it. Adding a step to one engine and forgetting the other
no longer compiles. Where the SQL is identical in both engines — index DDL,
mostly — a single function is passed to both sides (`steps/shared.py`).

Two things that look unifiable and are not. `_remove_obsolete_knowledge_pack_items`
is byte-for-byte identical in both engines but calls a step that is **not**:
sharing it would have made PostgreSQL run the SQLite variant. And the two
catch-up sequences in `migrations/legacy/` (`_catchup_sqlite.py`,
`_catchup_pg.py`) are **not split**: they are idempotent repairs kept in their
original order. Active tables belong exclusively to `app/sql/schema`; the
catch-up may add columns or repair legacy data, but it must not be required to
create a table used by a current query. `test_schema_usage.py` enforces that
boundary, while upgrade tests exercise the old-install path.

`tests/storage/test_migraciones_pg_traducidas.py` no longer reads
`postgres.py` as a file — it walks every function registered as a step's
PostgreSQL side, wherever it lives. Identifying them by file would leave the
guard looking at the wrong place the next time the code moves.

**A query that only works on one engine declares it** with `-- engine: pg` or
`-- engine: sqlite` under its name; the loader strips that line so it never
reaches the database. The two dialect variants of one operation stay **next to
each other in their domain's file** — splitting them into per-engine
directories is how a column gets added to one and forgotten in the other, which
is the original bug behind this whole item.

The failure mode moved: a typo in an identifier is no longer a visible SQL
syntax error but a `LookupError` on the branch that runs it — and some branches
only run on PostgreSQL. The guards cover all five ways that happens: SQL back in
Python, an identifier that doesn't resolve, a section nobody uses, dialect
syntax with no `-- engine:` declared (or one that contradicts it), and a
single-engine query used outside its `IS_PG` branch. Classification goes by the
query's **syntax**, not by whether the name ends in `_pg` — the convention is
exactly what gets forgotten. **Any test that greps the Python
for a table name now has a blind spot** — `test_schema_usage.py` had to learn
to read the `.sql` files.

`tests/storage/test_sql_contra_motores.py` *prepares* every query against a
real schema, which validates syntax, tables and columns without executing
anything. SQLite always runs (445 of the 457 sections). PostgreSQL needs
`GAIA_TEST_PG_DSN` and skips without it — and while it skips, those 12
PostgreSQL-only queries are never tried.

**The compose stack already runs a PostgreSQL, so there is no excuse for
skipping.** `iagents-postgres-1` publishes no port, so bridge it, create a
throwaway database, and point the DSN at it:

```bash
docker run -d --rm --name pgbridge --network iagents_default -p 15432:5432 \
  alpine/socat tcp-listen:5432,fork,reuseaddr tcp-connect:iagents-postgres-1:5432
docker exec iagents-postgres-1 psql -U gaia -d iagentshub -c "CREATE DATABASE test_sql_motores;"
export GAIA_TEST_PG_DSN="postgresql://gaia:$(docker exec iagents-postgres-1 printenv POSTGRES_PASSWORD)@127.0.0.1:15432/test_sql_motores"
```

**Not every query lives in `app/sql/`, and the catalogue only sees the ones that
do.** `PUBLICLY_AVAILABLE_SQL` is built in `app/services/social_catalog.py` and
carried `NOT inactive_resource.is_active`: `@BOOL@` is `INTEGER` in SQLite,
which accepts it, and `SMALLINT` in PostgreSQL, which answers *argument of NOT
must be type boolean* and turns the request into a 500. It took down the public
profile — that screen asks for resources, profile and follow status at once, so
one failure sinks all three. Two blind spots stacked on one line: a fragment
only Python knows about, and a PostgreSQL run that skips by default.
`_fragmentos_construidos_en_python()` in that same test file is where such a
fragment gets registered, with the minimal wrapper that makes it preparable.

Ver `docs/adr/007-sql-en-ficheros.md`.

### El grafo se arma en el cliente

Dibujar el grafo de recursos siempre estuvo en un solo sitio
(`AnimatedResourceGraph`), pero **armarlo** llegó a estar escrito ocho veces:
cuatro constructores en Dart y cuatro endpoints aquí, con la misma frase «un
agente usa una skill, un prompt, una tool…» repetida cuatro veces y el recorrido
de carpetas de un pack, tres. Habían divergido: el mismo agente enseñaba cosas
distintas según desde qué pantalla se abriera el grafo.

Hoy el backend entrega **relaciones planas** —`app/services/resource_relations.py`,
único sitio que las construye— y el ensamblado vive en
`app_flutter/lib/shared/graph/resource_graph_builder.dart`. Los nodos de carpeta
ya no viajan: el servidor manda el `path` de cada fichero y el árbol lo hace el
cliente.

El servidor solo participa donde el cliente no puede: el filtro
`public_dependencies` de un recurso publicado y los recursos ajenos de Admin.
Tres rutas `…/relations` cubren eso; los cuatro `…/graph` se retiraron, y se
retiraron **después** de que Flutter migrara — un bundle cacheado que siguiera
pidiéndolos habría dejado de funcionar. Dos guardas lo sostienen:
`tests/api/test_grafo_en_un_sitio.py` y, en Flutter,
`test/feature_architecture_test.dart`. Ver `docs/adr/010-el-grafo-se-arma-en-el-cliente.md`.

### La foto de perfil vive en su propia tabla

`user_avatars`, en bytes (`@BLOB@` → BLOB/BYTEA), no una columna de `users`.
Era un TEXT con el fichero en base64 —un tercio más grande— dentro de la tabla
que toca cada petición autenticada: `_USER_COLS` de `app/auth/user_lookup.py`
tenía que excluirla a mano, y saber si alguien tenía foto obligaba a comparar el
contenido (`avatar = ''`), que en PostgreSQL trae la imagen entera de su
almacenamiento externo solo para ver si está vacía. La migración 39 la mudó y
dropeó la columna.

Tres cosas que se aprendieron mudándola:

- **El catch-up legacy es `repeatable=True`**, así que corre en cada arranque.
  Dropear una columna sin quitarla de su lista la recrea en el siguiente
  arranque, en bucle y sin que nada falle. Pasó: la migración 40 es la 39 otra
  vez —el paso es idempotente— porque las bases que corrieron la 39 mientras el
  catch-up aún añadía la columna se quedaron con ella vacía para siempre, y una
  migración ya aplicada no vuelve a ejecutarse sola.
- **La versión de la URL es el `checksum`**, no un contador del cliente. El que
  había vivía en memoria de Flutter y volvía a cero al reconstruirse la
  pantalla, con lo que la URL reaparecía apuntando a la foto anterior. Ahora
  `GET …/avatar` sirve `ETag` + `Cache-Control: private, must-revalidate` y
  responde 304.
- **Nombrar la columna `owner_id` mete la tabla en el radar del guard de RGPD**
  automáticamente (`tests/auth/test_gdpr_cobertura.py`), que exige su `DELETE` y
  su exportación. Un `user_id` habría pasado desapercibido.

Subir avatar lleva `RateLimiter` **y** `Semaphore(1)`, el mismo par que la
transferencia de binarios de las tools: el cliente comprime a 512 px antes de
enviar, pero un `curl` no pasa por ahí y `max_request_bytes` vale 0 —sin
límite— mientras el administrador no diga otra cosa.

### The two sides of GDPR read the same table list

Deletion is `app/sql/queries/gdpr.sql` (27 `DELETE`s, run by
`purge_user_data`); export is `queries/gdpr_export.sql` (17 files in the ZIP,
built by `app/services/gdpr.py`). It is also **the guest's whole lifecycle**:
closing a guest session runs `purge_user_data` on it, so a resource that never
reaches the deletion routine now also survives a logout it should not have —
see `docs/adr/012-el-invitado-es-un-usuario-efimero.md`.

**A new resource has to reach both**, and no
table declares `REFERENCES users`, so the database drags nothing along behind
you: prompts, tools, memory and packs each got added without going back to the
deletion routine, and users who exercised their right to erasure left their rows
behind with an `owner_id` pointing at nobody.

`tests/auth/test_gdpr_cobertura.py` is what closes that — it reads
`app/sql/schema/*.sql`, takes every table whose column ends in `owner_id`
(`resource_source_links` calls its own `resource_owner_id`) and fails if one is
missing from a `DELETE`, filtered by the wrong column, or deleted but never
exported. Two tables are out on purpose and named in `EXCLUIDAS` with the reason;
add yours there rather than widening the guard. **Tables keyed by `username`
instead — `personal_access_tokens`, `vscode_auth_codes`, `subscriptions` — are
still outside all of this.** `user_agent_preferences` was one of them until the
guest started writing it from the chat; it is deleted and exported now, and its
`username` column holds the **id** (the writer is `require_auth`, which returns
the id), which is exactly the kind of mismatch the guard cannot see.

Migration 28 (`gdpr_orphan_resources`, both dialects) cleans up the rows left
behind by installs that ran the old routine. It is the only destructive
migration in the registry: it skips `__public__` and `admin` — neither is an
account, so neither is ever in `users` — and does nothing at all when `users` is
empty, where "not in users" is true of everything.

`_purge_user_files()` in `app/auth/gdpr.py` is **not** the deletion that
matters. Agents and skills live in their tables; that function only reaches the
`config.json` files that the file→DB migration copied and never removed. Export
used to read from there, which is why it shipped a well-formed ZIP with the two
central resources as empty lists and no error anywhere.

### La extracción de un documento no puede perder texto en silencio

Un fichero importado a conocimiento se guarda **solo como texto**: de los bytes
originales quedan `checksum` y `size_bytes`, nunca el contenido. Así que lo que
la extracción deje fuera no está en ninguna parte, y una ficha recortada que se
enseñe como completa es una pérdida definitiva que nadie puede ver.

Hasta 2026-08 `extract_document_text` recortaba a 500 000 caracteres en sus
siete salidas — PDF, OCR, texto plano y descarga de URL. Medido: un PDF de
**62 KB** con 400 páginas perdía el **69,5 %** de su texto, cortando por la
página 122. No había log, no había columna (`char_count` guardaba el número ya
recortado) y la interfaz pintaba esa cifra como si fuera el documento entero.

Hoy `extract_document` devuelve un `ExtractedDocument` con `truncated`,
`source_chars` y `reason`, que llega hasta tres columnas de `knowledge_items` y
hasta un badge en la ficha. Tres reglas:

- **La cota (`MAX_EXTRACTED_CHARS`, 20 M) es defensa del proceso, no recorte
  normal.** Está por encima de cualquier documento real; cuando muerde, se
  anota y se registra.
- **Ninguna ruta llama a `extract_document_text`**, que devuelve solo el `str` y
  por tanto pierde el aviso. Usan `_extract_document` de
  `knowledge/_shared.py`.
- **La extracción no va por `asyncio.to_thread`**, que es el executor por
  defecto de asyncio y por tanto el de `bcrypt`: unas cuantas subidas grandes
  paraban los logins sin que nada fallara. Va por `run_document_blocking`
  (`app/services/document_executor.py`), con su propio pool acotado.

Las tres las guarda `tests/storage/test_extraccion_sin_perdida_silenciosa.py`.
Ver `docs/adr/013-la-extraccion-no-pierde-texto-en-silencio.md`.

### Request size is one number and the admin owns it

The size of an upload is decided in **one** place: `max_request_bytes` in the
platform settings (Admin · Configuration · Uploads), applied by
`BodySizeLimitMiddleware` to **every** request, not just the multipart ones.
**0 means no limit, and 0 is the default.** `GAIA_BODY_MAX_BYTES` survives only
as the starting value when nobody has touched the panel.

**Y un techo por debajo del panel es el mismo fallo otra vez.** Este trabajo
revisó nginx, el middleware, el avatar y Flutter, pero no las rutas de
conocimiento, donde sobrevivieron 10 MB por documento, 10 MB por fichero de pack
y 50 MB por pack. Con el panel en «sin límite» la interfaz dejaba elegir el
fichero y era un literal de una ruta el que respondía 413 con un número que no
aparece en ninguna pantalla. Se fueron en 2026-08. El que se queda es
`_PACK_SESSION_MAX_TOTAL_BYTES`, que acumula entre varias peticiones y por eso
ningún middleware puede contarlo — ese es el criterio para añadir otro.

It used to be four numbers that disagreed: 10 MB announced by Flutter, 2 MB in
the middleware (with a dead 11 MB override for the avatar), 10 MB again inside
`upload_avatar`, and **1 MB in nginx** — which nobody had written, because it is
`client_max_body_size`'s default and it went first. The user picked a 4 MB PDF
the interface accepted and got nginx's **HTML** 413, not the `payload_too_large`
`APIError` the backend builds with `limit_bytes` inside.

Two rules keep it from growing back. **nginx never imposes a ceiling of its own**
(`client_max_body_size 0` in `frontend_react/nginx.react.conf`) — its 413 is a
page no client can parse, so the rejection has to be the backend's JSON. And
**the client never carries a copy of the number**: Flutter reads it from
`/api/settings/platform/public` into `UploadLimits`, which only skips a doomed
upload and puts the real figure in the message.

The middleware re-reads the value per request behind a cache invalidated on
write, the same pattern as `billing_enabled` — pinning it at construction time
would freeze it at boot and the panel would change nothing until a restart.
Unlimited is a warning in the startup audit (`body_limit`), because with nginx
out of the way it is the only thing standing between a `await file.read()` and
memory. Ver `docs/adr/011-un-solo-limite-de-tamano-y-lo-pone-el-admin.md`.

### El panel de administración se pagina como todo lo demás

Cuando se paginaron los listados del producto **el panel se quedó entero
fuera**: once `GET` de `/api/admin` devolvían `SELECT … FROM tabla` sin `WHERE`
y sin cota — los únicos del producto cuyo tamaño no lo decide un
usuario, sino la instalación. **Se retiraron los once**: no los pedía ningún
cliente, ni Flutter ni la extensión, así que no había bundle cacheado al que
esperar.

El inventario del panel se pide por `/api/v2/admin/explore`, que ya pagina y
cubre los once tipos con columnas normalizadas. De los listados por tipo solo
queda `/api/v2/admin/connections`, el único con consumidor: el selector de
conexiones LLM de la importación oficial, que necesita el catálogo completo y
lo recorre con el colector cursor. Los otros diez se escribieron y se retiraron
en el mismo trabajo, al comprobar que ninguna pantalla los llamaba — una ruta
publicada que nadie pide es superficie que mantener sin nadie a quien servir.

**La clave keyset del panel lleva `owner_id`, no solo `id`.** Varias de esas
tablas tienen PK compuesta `(id, owner_id)`. Para un usuario `id` basta, porque
solo ve lo suyo; el administrador ve todos los dueños a la vez y ahí
`(updated_at, id)` deja de ser única — y un keyset con clave repetida **se salta
filas en el corte de página sin que nada falle**. Por eso estos listados usan
`fetch_composite_cursor_page` y no el de dos columnas.

`GET /api/admin/memory` traía la columna `content` —la memoria de largo plazo de
cada agente de cada usuario, texto libre sin cota— para hacerle `len()` y
tirarla. Hoy es `LENGTH(content)` en SQL. Es la misma lección que la mudanza del
avatar, en otra tabla. La guarda que lo vigila mira **la proyección** de cada
spec, no la respuesta: es ahí donde se decide qué cruza el cable.

El nombre del dueño sale del `JOIN` (`list_groups` ya lo hacía) en vez de
`_username_map`, que era `SELECT id, username FROM users` **llamado nueve veces
por carga del panel**. Y los cuatro filtros del directorio de usuarios viajan a
SQL: aplicarlos en Python sobre una página devuelve resultados incompletos sin
que se note.

**`connection_id` de un agente es una columna, no solo un campo del blob.** La
pregunta «¿qué agentes usan esta conexión?» —la que hace el borrado de una
orquestación— se resolvía trayendo **todos** los agentes de la instalación y
filtrándolos en Python, mientras la pregunta equivalente sobre
`user_agent_preferences` ya era un `COUNT(*)` dos líneas más abajo, en la misma
función. La migración 45 promueve el campo, como ya estaban `name`, `scope` y
`official_source_id`: **el JSON sigue siendo la fuente y la columna es su
espejo**, mantenida por el upsert. Separarlas hace que el `COUNT` responda por
un estado que ya no existe, y eso lo vigila
`tests/storage/test_agente_conexion_columna.py`.

**Hay dos motores keyset y no son el mismo escrito dos veces.**
`cursor_page_query` usa comparación de tupla, `(posicion, id) < (?, ?)`, que es
lo que SQLite y PostgreSQL resuelven con un solo descenso por el índice
compuesto —en SQLite el plan pasa de `SCAN` a `SEARCH … USING INDEX`—, y solo
vale cuando todas las columnas del orden van en la misma dirección: es el caso
de los listados calientes (agentes, skills, prompts, herramientas,
conocimiento). `composite_cursor_page` expande a `(a<?) OR (a=? AND b<?) OR …`
porque sus consumidores mezclan direcciones (`sort_at DESC, resource_type ASC,
item_id ASC`), y SQL no admite tupla con órdenes mixtos. **Los dos devuelven
exactamente las mismas filas**, así que cambiar uno por otro no rompe ningún
test: solo degrada el plan, en silencio. Antes de fundirlos, mide.

**Y el arreglo de verdad estaba en el inventario, no en el listado.** Retirar
los once dejó a la vista que `/api/v2/admin/explore` —el que el panel sí pide,
desde que sus pestañas se migraron— arrastraba los mismos defectos que este
trabajo venía a quitar del otro lado:

- Hacía `SELECT *` sobre `memory_files` y `len(content)` en Python. **El
  `len()` que motivó este punto seguía vivo justo donde se ejecuta**; quitarlo
  del listado por tipo no lo tocaba. La proyección lleva ahora
  `LENGTH(content)`, y la guarda mira la proyección.
- No excluía a los invitados, así que aparecían y desaparecían del panel entre
  dos recargas pese a la regla de arriba.
- No servía `avatar_url` —la foto vive en `user_avatars`, no es una columna— ni
  los recuentos que pinta la tarjeta de grupo (`member_count`, `agents_count`,
  `status`…), así que el panel enseñaba iniciales y ceros. Los recuentos se
  piden solo para los identificadores de la página.

La lección para la próxima retirada: **el endpoint que se retira y el que se
queda pueden compartir el defecto**, y arreglar solo el que se va deja el fallo
donde de verdad corre.

**Un índice del esquema sobre una columna nueva necesita las dos
pre-migraciones.** El esquema se re-ejecuta entero en cada arranque y
`CREATE TABLE IF NOT EXISTS` no añade columnas a una tabla que ya existe, así
que su `CREATE INDEX` nombra una columna que en una base antigua no está.
`_SCHEMA_INDEX_DEPS` es la lista que las añade antes — y hasta ahora **solo la
leía SQLite**. En PostgreSQL, que es lo que corre en producción, no lo hacía
nadie: una base existente respondía *column … does not exist* al crear el
índice y **el backend no arrancaba**. Ahora hay `_pre_migrate_pg` leyendo la
misma lista. Esto no lo ve una suite con la base recién creada, que es
exactamente por qué apareció al probar contra el PostgreSQL del compose
partiendo de una tabla anterior a la columna.

**Contar recorriendo `AGENTS_DIR/*/config.json` da cero.** Son los ficheros que
dejó la migración fichero→base de datos y nadie borró, así que en cualquier
instalación creada después ese `glob` no encuentra nada. Estaba en dos sitios
—el recuento de agentes por grupo y `agents_public`/`agents_private` de
`GET /api/admin/stats`, que es la pantalla principal del panel—, y los dos
enseñaban **cero agentes** sin que nada fallara. Los dos salen ya de la tabla.
Lo único que aún lee esos ficheros es la migración que los importó y el borrado
por RGPD que los limpia.

**`tests/api/test_listados_con_cota.py` es lo que evita que vuelva a pasar.**
Recorre `app/api/routes/` y falla si un `GET` devuelve `list[...]` sin `limit`
ni `cursor`. Lo que ya estaba sin cota se declara en su `DEUDA` con el motivo
—hoy solo listados acotados por el usuario que pregunta y catálogos de tamaño
fijo—, y **esa lista solo puede encoger**: un segundo test falla si una entrada
deja de corresponder a un listado real.

### Rate limiting

**Every route limiter counts in the database, not in the process.** They are
built with `shared=True` and a stable `name`, and the counter lives in
`rate_limit_windows` — so the number written in the code is the cluster's limit
and it survives a redeploy. Two guards in `tests/test_ratelimit.py` walk
`app/api/routes/` and fail on a limiter that went back to a per-process counter,
or on one declared that nobody applies. Four had been sitting there dead since
their endpoints moved to another module.

The in-memory sliding window still exists for limiters without a stable name —
the constructor divides `calls` by `app.config.server.WORKERS`, because uvicorn
runs that many processes. Today only the tests take that path.

**An authenticated endpoint keys by `principal_key`, not by IP.** Behind a
corporate NAT one IP is the whole office; rotating IPs finds no ceiling. It
resolves the identity **without touching the database** — the PAT's hash, or the
already-signed JWT's `sub` — because it runs before the authorization dependency
and on the chat's hot path. It authorizes nothing: a forged token falls back to
the IP branch. Auth limiters stay keyed by IP, which is the only identity there
is before a session exists.

Above the per-user quota sits an IP ceiling `GAIA_RATE_IP_FACTOR` times looser
(5 by default), because a per-principal key alone hands a full quota to every
disposable account. At 0 it is off and the startup audit says so.

`_rate_limit_purge_loop` in `_lifespan` clears expired windows every 6 h; the
horizon is the longest window registered in the process, not a constant —
purging with the others' 60 s cutoff would give `auth-forgot`, which is an hour
long, its quota back.

Every instance registers itself in `ratelimit.INSTANCES`; the test fixture
clears that list rather than naming limiters one by one. Shared limiters keep
nothing there — the per-test SQLite file is what isolates them.

Ver `docs/adr/009-cuota-compartida-y-por-principal.md`.

## The trap that will bite you in backend tests

Several modules import paths **by value**:

```python
from app.config.data import DATA_DIR, SETTINGS_FILE
```

The binding is frozen when the module is first imported. If a test module
imports such a module at top level, pytest's **collection** phase freezes it to
the collection tmpdir (`tests/conftest.py:22`) and no later monkeypatch fixes
it. This already caused the license gate to never fire, silently returning 200
where 403 was expected — and only in a full-suite run.

`patch_data_dir` patches the known offenders (`cfg`, `auth_mod`,
`licenses_mod`). **Add yours when you introduce another.** In test files,
prefer the `tmp_data_dir` fixture over importing `DATA_DIR`.

This is why **~80 imports sit inside functions rather than at module top**, and
why you should not "tidy" them without checking which kind each one is:

- **`app.config.data` / `app.config.session`** — paths and config the tests
  rewrite. These must stay deferred.
- **Everything else** — habit. They are not breaking cycles: across **190 files
  in `app/`** the package has **3 real cycles**, all of them `models.agent` with
  its subclasses, and `tests/test_ciclos_de_import.py` freezes exactly those
  three. `storage.py` alone had 31 deferred imports of `app.storage.db`, which
  does not reach `storage.py` at all; they are now at the top.

A mutable value needs a third treatment: `storage.py` reads `_db.IS_PG` through
the module rather than importing the name, so `monkeypatch.setattr(db, "IS_PG",
…)` reaches it. `tests/storage/test_is_pg_en_tiempo_de_llamada.py` fails if
anyone converts it back.

## Conventions

Comments, commit messages, test names, and user-facing strings are in
**Spanish**. Code identifiers are English. Match the file you are editing.

Comments explain *why*, usually citing the failure that motivated the code.
Keep that style — a comment restating the line below it is noise here.

A `ponytail:` comment marks a **deliberate** simplification with a known
ceiling, and names the ceiling so the next reader doesn't mistake it for an
oversight (`ratelimit.py`, `tokens.py`, `flog.py`, plus one each in Flutter and
the VS Code extension — `grep -rn "ponytail:"` finds them). It is not a TODO.

**Ningún fichero de `app/` pasa de 600 líneas**, y lo vigila
`tests/test_tamano_de_ficheros.py`. Los siete que ya estaban por encima cuando
se puso la guarda están en su `DEUDA` con la medida de ese día **como techo**:
no pueden crecer más, y su entrada se borra al partirlos. Esa frase estuvo
escrita sin nada que la sostuviera y envejeció sola — de ahí el test.

**A blind `except Exception` either logs with context or does not exist.** ruff
enforces this (`BLE001`, `S110`, `S112` are in the `select` list). When the
width is genuinely the design — a loop that must not stop on one bad item, a
safety net inside an SSE stream that has already started emitting, the logger
itself, where logging would recurse — mark it `# noqa: BLE001` and say why on
the next line. Everything else logs through `flog` or gets deleted so the
global handlers in `app/api/app.py` can take it. `app.storage.db.DB_ERRORS` is
the tuple to catch when the expected failure is the database: it covers both
drivers, so it works in SQLite and PostgreSQL alike.

### Where the "why" lives

Long decision essays belong in `docs/adr/`, one file per decision, dated, in
Spanish only — they are internal engineering docs, so they sit outside the
bilingual `docs/es` + `docs/en` that document the product. Move a comment block
there when the reasoning is **transversal**: it spans files, or it is about
operations or deployment, and someone may need it without opening that
particular file. Leave it in the code when it explains the line right below it.
Where a block moved, a `# Ver docs/adr/NNN-….md` line stays behind.

## Config

Environment variables are `GAIA_*` and are read in `app/config/`.
`GAIA_DEV_MODE` gates `/docs` and `/openapi.json` together — both are closed in
production. `GAIA_REGISTRATION` is `open | closed | invite` (all three are
implemented; the single source is `app/config/session.py:REGISTRATION_MODES`).
`GAIA_MAX_GUEST_SESSIONS=0` disables guest access entirely.

**What it means for a variable to be missing is decided in one place**:
`app/config/startup_checks.py`. Each module still reads its own environment;
the audit interprets the result. `_lifespan` runs it before `init_db` and logs
which feature is disabled and because of which variable. Two levels — *warning*
when configuration is absent and a feature switches off (may well be
deliberate), *error* when the configuration contradicts itself (email
verification on with no SMTP, billing on with no Stripe keys, a typo in
`GAIA_REGISTRATION`). Errors do not abort unless `GAIA_STRICT_CONFIG=true`;
leaving a degraded-but-running install unable to start is the worse failure.
The report is at `GET /api/admin/config-audit` and in the Flutter admin panel,
names only, never values. **Add a check when you add a variable that turns a
feature on or off** — otherwise it goes back to failing silently.

**The background loops read their cadence from `app/config/maintenance.py`**,
not from a literal in the loop body: GDPR purge, log purge, rate-limit purge and
the workflow tick. Each has a **floor**, and that is the point — these numbers
go straight into an `asyncio.sleep` inside a `while True`, so a 0 is not "purge
constantly" but a process spinning a whole CPU, one per worker. A value below
the floor, or one that isn't a number, is corrected at startup and recorded in
`maintenance.ANOMALIAS` so the config audit reports it instead of applying the
correction silently. `tests/config/test_maintenance.py` fails if a loop goes
back to writing its own interval.

The split that decides where a number lives: **what gets swept is config, how
often the broom passes is code.** Log retention is set by the admin because it
decides which data is lost; the 24 h sweep is not. The rate-limit purge interval
affects no quota at all — a window stops counting when it expires, not when its
row is deleted.

This file has to exist in **two places**: `all_iagenthub/CLAUDE.md` (the
working-folder root, which Claude Code loads and which is not a repo) and
`iAgents/CLAUDE.md` (the versioned copy). A pre-commit hook in `iAgents`
compares them byte for byte. It skips silently when the root copy is missing —
if you delete it, the two drift and nothing says so.

## Decisions already taken

The remediation backlog that used to live in `iagentshub/SANEAMIENTO.md` is
gone; git history holds what was done. These three are the only entries that
were still live, and each one costs something real to rediscover:

- **There is exactly one `hub.db`, at `iAgents/data/hub.db`.** This entry used
  to warn about a second copy under a separate orchestrator directory; that
  directory no longer exists here, so the ambiguity is gone. Still confirm with
  `find . -name hub.db` before deleting a database — the warning existed because
  the directory names suggested the opposite of the truth.
- **Sections a guest cannot use are hidden in the client, never opened in the
  backend.** The fix for "the guest sees a 403" is here, not a wider guard —
  see the allowlist rule above. This used to name `workflows`, dropped from
  `_visibleMainItems(role)` for `role == 'guest'`; workflows are the guest's
  now, so what is left hidden is what is genuinely not his. Checkout is the
  open one: it is reachable without a session at all, and whether to block or
  redirect is a product call.
- **The duplication across the three compose files is load-bearing.** Pulling
  `watchtower` + `docker-proxy` into a shared fragment with `include:` looks
  obvious until you notice `install.sh` and `install.ps1` `curl` **one file**
  and save it as `docker-compose.yml` — on install *and* on every update. A
  compose that references a fragment breaks everyone who already has it.
