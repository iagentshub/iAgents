<div align="center">
  <a href="index.md">← Index</a> &nbsp;·&nbsp;
  <a href="../es/ci.md">🇪🇸 Ver en Español</a>
</div>

<br>

# Configuration Quality

The repository has two layers of automated verification that catch configuration errors before they reach the main branch.

---

## Before committing

A local hook reviews configuration files at commit time. If any check fails, the commit is cancelled until the issue is fixed.

It checks three things:

- **Installer** — analyses `install.sh` for common shell scripting errors.
- **Management script** — checks that `gaia.py` compiles without syntax errors.
- **Service configuration** — validates that `docker-compose.yml` has correct syntax and all services are properly defined.

To activate it, run once after cloning the repository:

```bash
pip install pre-commit
pre-commit install
```

From that point on it runs automatically on every `git commit`.

---

## On GitHub (push and pull requests)

Every time code is pushed to the main branch or a pull request is opened, GitHub runs the same checks in a clean environment. This acts as a safety net for changes that arrive without the local hook installed.

A pull request cannot be merged if the checks fail.
