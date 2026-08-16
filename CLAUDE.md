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
| `frontend_react/` | React 19 / Vite / TS. **Public pages only** — landing, pricing, docs, about, support. Also the nginx image that fronts everything. |
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
python3.11 rtests.py                               # full suite, ~4 min (1954 tests)
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

Three tests here assert facts about the tree rather than behaviour, so they
fail on files you may not think you touched:

- `a11y_iconos_test.dart` — every icon-only button needs an accessible name,
  from `tooltip:` or a wrapping `Tooltip`/`Semantics`. A screen reader
  announces an unnamed one as "button" and nothing else.
- `branding_config_test.dart` — the product is **"iAgents Hub"**, never
  "iAgentsHub". Note the *native* app name is plain "iAgents" and that is
  deliberate; the test only chases the concatenation.
- `backend_url_test.dart` — shares its case table with `vs_code/src/test/
  url.test.ts`. Change one, change both.
- `deferred_routes_test.dart` — admin, Centinel, metadata, workflows and
  checkout are imported `deferred as` in `lib/app/router/internal_router.dart`
  and mounted through `DeferredPage`, which keeps 777 KB out of the initial web
  bundle. **Only the router may import those five files.** A plain `import`
  anywhere else pulls their code back into the main bundle and nothing visible
  breaks — this test is what notices. A heavy new screen goes in deferred too.

CI runs one more gate that `flutter test` cannot: `tool/check_web_bundle_size.sh`
after `flutter build web --release`. It fails if `main.dart.js` crosses the budget
written in the script, or if the build produced no deferred parts at all.

### vs_code

```bash
npm test          # compiles, then node --test out/test/*.test.js
npm run lint
```

Tests import from `../url`, never `../auth`: `auth.ts` imports `vscode`, which
does not exist outside an extension host.

### iAgents

```bash
python3.11 rtests.py          # 26 tests, ~2 s
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

The two directions cross exactly once: **the legal pages**. Privacy and terms
are React (`/privacy`, `/terms`, plus `/en/…`), but Flutter's register screen
has to link to them and gate the submit button on a checkbox — publishing the
documents and never collecting acceptance leaves the contract without proof of
consent. Flutter reaches them with `resolvePublicSiteUri`, not GoRouter: they
live at the origin root, outside `/app/`, so it is browser navigation. Note
the backend still stores neither the date nor the version accepted, so today
consent is required but cannot be evidenced after the fact.

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
`require_auth` and is therefore closed to guests.** Only add `require_session`
when the guest demo genuinely needs it — the guest allowlist is derived
deliberately, not by convenience, and `tests/api/test_guest_boundary.py`
asserts both sides of the line.

`require_auth` used to alias the `guest` rank, which left ~140 private
endpoints open to guest sessions. Do not widen it back.

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

### Rate limiting

`RateLimiter` is a FastAPI dependency with a per-process sliding window.
uvicorn runs `GAIA_WORKERS` processes, so the constructor divides `calls` by
`app.config.server.WORKERS`. State is in memory and is lost on restart.

Every instance registers itself in `ratelimit.INSTANCES`; the test fixture
clears that list rather than naming limiters one by one.

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
  backend.** `_visibleMainItems(role)` drops `workflows` from the Flutter
  navigation catalogue for `role == 'guest'`. The fix for "the guest sees a
  403" is always here, not a wider guard — see the allowlist rule above.
  Checkout is the open one: it is reachable without a session at all, and
  whether to block or redirect is a product call.
- **The duplication across the three compose files is load-bearing.** Pulling
  `watchtower` + `docker-proxy` into a shared fragment with `include:` looks
  obvious until you notice `install.sh` and `install.ps1` `curl` **one file**
  and save it as `docker-compose.yml` — on install *and* on every update. A
  compose that references a fragment breaks everyone who already has it.
