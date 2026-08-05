# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## This directory is not a repository

`iagentshub/` is a working folder holding **five independent git clones** plus a
data directory. There is no umbrella repo, no submodules, no workspace file.

| Directory | What it is |
|---|---|
| `backend/` | FastAPI + Python 3.12. The only server. |
| `frontend_react/` | React 19 / Vite / TS. **Public pages only** — landing, pricing, docs, about, support. Also the nginx image that fronts everything. |
| `app_flutter/` | Dart 3 / Flutter. The **entire authenticated app**, served under `/app/`. |
| `vs_code/` | VS Code extension. Talks to the backend with a PAT. |
| `iagentshub/` | Orchestrator: `gaia.py`, `install.sh`, `install.ps1`, the compose files. Ships no product code. |
| `iAgents/` | Data only (`data/hub.db`, settings). Not a clone. |

**No change is atomic across repos.** A contract change means separate commits
in separate repos that land at different times. **Backend first, always** — it
is the one every client depends on.

Each clone has its own `main`, its own CI, and its own remote under
`github.com/iagentshub`.

## Commands

Run these from inside the relevant clone, not from this folder.

### backend

```bash
.venv/Scripts/python.exe -m pytest tests/ -q       # full suite, 12-15 min
.venv/Scripts/python.exe -m pytest tests/api/test_routes_auth.py -q
.venv/Scripts/python.exe -m pytest tests/api/test_x.py::test_y -q
ruff check .                                       # ruff is on PATH, not in .venv
ruff check . --fix
python main.py                                     # dev server, port 8765
```

Pre-commit runs ruff plus three structural guards (`test_contrato_rutas`,
`test_guest_boundary`, `test_json_body`) — 20 s, not the full suite. CI runs
everything on push and PR. The guards are there to catch the API surface
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
  `landing`, `pricing`, `seo`, `support`. Adding a locale file breaks the build
  until you add it to the script too.

`check` does **not** run the Playwright specs; they need a build and a server,
so CI runs them (`test:e2e:chromium`, every spec in `e2e/`). Among them
`a11y.spec.ts` audits the five public pages with axe against WCAG 2.1 A and AA
— normative rules only, not axe's `best-practice` tag, which brings arguable
criteria that would turn the gate into noise. Run it locally with
`npx playwright test a11y --project=chromium`.

### app_flutter

```bash
flutter test
flutter test test/backend_url_test.dart
flutter analyze          # exits non-zero on infos, so `analyze && test` short-circuits
```

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

### vs_code

```bash
npm test          # compiles, then node --test out/test/*.test.js
npm run lint
```

Tests import from `../url`, never `../auth`: `auth.ts` imports `vscode`, which
does not exist outside an extension host.

### iagentshub

No test suite. Pre-commit runs shellcheck on `install.sh`, `docker compose
config`, `py_compile` on `gaia.py`, and a BOM check on `install.ps1`. CI adds
PSScriptAnalyzer and ruff.

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

### Authorization is four dependencies

`app/api/routes/auth.py` exports the entire authorization surface:

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

Two styles coexist: **43 handlers parse JSON by hand, 23 take a pydantic
model** (`agent_builder`, `agents`, `centinel`, `logs`, `resource_linking`,
`resource_management`, `settings`, `skill_builder`, `social`). Pydantic is the
better one and newer code is drifting toward it — prefer it for a new endpoint.

Where you do parse by hand, always go through `app.utils.net.json_body(request)`,
never `await request.json()` — it guarantees the body is an object and returns
400 instead of a 500 when someone posts `[]`. A test walks `app/api/routes/`
and fails if a raw `request.json()` reappears.

Because most bodies are still hand-parsed, **the OpenAPI schema does not
describe request fields for those routes**. Generating client types from it
today would produce empty signatures for two thirds of the surface.
`tests/api/contrato_rutas.txt` freezes what the schema *can* honestly assert:
the set of `METHOD /path`. Every handler converted to pydantic moves codegen
closer to being worth doing.

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

This is why **131 imports sit inside functions rather than at module top**, and
why you should not "tidy" them without checking which kind each one is:

- **`app.config.data` / `app.config.session`** (27 of them) — paths and config
  the tests rewrite. These must stay deferred.
- **Everything else** — habit. They are not breaking cycles: the whole package
  has **4 real cycles in 105 modules**, three of which are `models.agent` with
  its subclasses. `storage.py` alone had 31 deferred imports of
  `app.storage.db`, which does not reach `storage.py` at all; they are now at
  the top.

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
oversight (`ratelimit.py:43`, `tokens.py:39,143`, `flog.py:97`, plus one each in
Flutter and the VS Code extension). It is not a TODO.

## Config

Environment variables are `GAIA_*` and are read in `app/config/`.
`GAIA_DEV_MODE` gates `/docs` and `/openapi.json` together — both are closed in
production. `GAIA_REGISTRATION` is `open | closed | invite` (all three are
implemented; the single source is `app/config/session.py:REGISTRATION_MODES`).
`GAIA_MAX_GUEST_SESSIONS=0` disables guest access entirely.

Its versioned copy lives at `iagentshub/CLAUDE.md`; a pre-commit hook there
compares them byte for byte, because Claude Code loads this one from the
working-folder root and that root is not a repo.

`iagentshub/SANEAMIENTO.md` tracks the remediation backlog, what was
deliberately deferred and why, and the open decisions.
