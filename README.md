<div align="center">
  <a href="docs/en/index.md">🇬🇧 English</a> &nbsp;·&nbsp;
  <a href="docs/es/index.md">🇪🇸 Español</a>
</div>

<br>

<h1 align="center">iAgentsHub</h1>

<p align="center">AI agents platform. One command deploys the full stack.</p>

---

## Quick deploy

**Linux / macOS**

```bash
git clone https://github.com/iagentshub/iagentshub.git
cd iagentshub
cp .env.example .env
# Edit .env — set GAIA_AGENTS_SECRET
./gaia.sh start
```

**Windows**

```bat
git clone https://github.com/iagentshub/iagentshub.git
cd iagentshub
copy .env.example .env
:: Edit .env — set GAIA_AGENTS_SECRET
gaia.bat start
```

Open `http://localhost`.

---

## Local mode (no Docker)

Si no tienes Docker instalado, también puedes arrancar la plataforma directamente en tu máquina sin contenedores usando la opción `--local` del script de arranque (`gaia.sh` en Linux/macOS o `gaia.bat` en Windows).

```bash
./gaia.sh start --local
```

---

| | |
|---|---|
| 🇪🇸 Español | [docs/es/index.md](docs/es/index.md) |
| 🇬🇧 English | [docs/en/index.md](docs/en/index.md) |

---

[MIT](LICENSE)
