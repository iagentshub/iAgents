"""Contrato del entrypoint modular de gaia.py."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

from gaia_cli import cli, common
from gaia_cli import compose as compose_mod

REPO_ROOT = Path(__file__).parent.parent


def test_gaia_es_un_wrapper_pequeno_y_los_dominios_estan_separados():
    entrypoint = (REPO_ROOT / "gaia.py").read_text(encoding="utf-8")
    assert len(entrypoint.splitlines()) <= 12
    assert "from gaia_cli.cli import main" in entrypoint
    for module in (
        "console",
        "common",
        "local_process",
        "compose",
        "build_push",
        "validation",
        "cli",
    ):
        assert (REPO_ROOT / "gaia_cli" / f"{module}.py").is_file()


@pytest.mark.parametrize(
    ("args", "expected"),
    [
        (["--help"], "Flujo recomendado"),
        (["--help", "--local"], "Base de datos: SQLite"),
    ],
)
def test_entrypoint_conserva_la_ayuda_publica(args, expected):
    result = subprocess.run(
        [sys.executable, "gaia.py", *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    assert expected in result.stdout
    assert result.stderr == ""


def test_help_documenta_validate_sin_flags_y_el_env_protegido():
    result = subprocess.run(
        [sys.executable, "gaia.py", "--help"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "validate Valida los cinco Compose" in result.stdout
    assert "no admite flags" in result.stdout
    assert "iAgents/.env (0600)" in result.stdout


def test_cli_enruta_status_local_sin_docker(monkeypatch):
    calls = []
    monkeypatch.setattr(sys, "argv", ["gaia.py", "status", "--local"])
    monkeypatch.setattr(cli, "cmd_local_status", lambda: calls.append("local"))

    cli.main()

    assert calls == ["local"]


def test_start_sin_docker_instalado_hace_fallback_a_sqlite(monkeypatch, capsys):
    calls = []
    monkeypatch.setattr(sys, "argv", ["gaia.py", "start"])
    monkeypatch.setattr(cli.shutil, "which", lambda _: None)
    monkeypatch.setattr(cli, "cmd_local_start", lambda: calls.append("local"))

    cli.main()

    assert calls == ["local"]
    assert "modo local con SQLite" in capsys.readouterr().out


def test_start_con_docker_instalado_mantiene_compose(monkeypatch):
    calls = []
    monkeypatch.setattr(sys, "argv", ["gaia.py", "start"])
    monkeypatch.setattr(cli.shutil, "which", lambda _: "/usr/bin/docker")
    monkeypatch.setattr(cli.os, "chdir", lambda _: None)
    monkeypatch.setattr(
        cli,
        "cmd_start",
        lambda compose, dev, hub: calls.append((compose, dev, hub)),
    )

    cli.main()

    assert calls == [(["docker", "compose"], False, False)]


def test_cli_enruta_validate_por_gaia(monkeypatch):
    calls = []
    monkeypatch.setattr(sys, "argv", ["gaia.py", "validate"])
    monkeypatch.setattr(cli.os, "chdir", lambda _: None)
    monkeypatch.setattr(cli, "cmd_validate", lambda: calls.append("validate"))

    cli.main()

    assert calls == ["validate"]


@pytest.mark.parametrize("flag", ["--dev", "--hub", "--local"])
def test_cli_rechaza_flags_en_validate(monkeypatch, capsys, flag):
    monkeypatch.setattr(sys, "argv", ["gaia.py", "validate", flag])

    with pytest.raises(SystemExit, match="1"):
        cli.main()

    assert "validate no admite" in capsys.readouterr().err


@pytest.mark.parametrize(
    ("flag", "expected_compose", "dev", "hub"),
    [
        (None, ["docker", "compose"], False, False),
        (
            "--dev",
            [
                "docker",
                "compose",
                "-f",
                "docker-compose.yml",
                "-f",
                "docker-compose.dev.yml",
            ],
            True,
            False,
        ),
        ("--hub", ["docker", "compose", "-f", "docker-compose.hub.yml"], False, True),
    ],
)
def test_cli_conserva_la_seleccion_de_compose(
    monkeypatch, flag, expected_compose, dev, hub
):
    calls = []
    args = ["gaia.py", "start"] + ([flag] if flag else [])
    monkeypatch.setattr(sys, "argv", args)
    monkeypatch.setattr(cli.shutil, "which", lambda _: "/usr/bin/docker")
    monkeypatch.setattr(cli.os, "chdir", lambda _: None)
    monkeypatch.setattr(
        cli,
        "cmd_start",
        lambda compose, is_dev, is_hub: calls.append((compose, is_dev, is_hub)),
    )

    cli.main()

    assert calls == [(expected_compose, dev, hub)]


def test_cli_rechaza_flags_incompatibles(monkeypatch, capsys):
    monkeypatch.setattr(sys, "argv", ["gaia.py", "status", "--dev", "--local"])

    with pytest.raises(SystemExit, match="1"):
        cli.main()

    assert "--dev y --local son incompatibles" in capsys.readouterr().err


def test_rutas_compartidas_siguen_apuntando_a_la_raiz_del_repo():
    assert common.IAGENTS_DIR == REPO_ROOT.resolve()
    assert common.SCRIPT_DIR == REPO_ROOT.resolve()


def test_modo_local_propaga_el_tamano_del_pool_sqlite():
    source = (REPO_ROOT / "gaia_cli" / "local_process.py").read_text(encoding="utf-8")
    assert 'read_env_var(ENV_FILE, "GAIA_SQLITE_POOL_SIZE", "")' in source
    assert "if sqlite_pool_size:" in source
    assert 'backend_env["GAIA_SQLITE_POOL_SIZE"] = sqlite_pool_size' in source


# ── Secretos que compose exige sin valor por defecto ──────────────────────────


def test_env_antiguo_recibe_el_token_de_watchtower(monkeypatch, tmp_path):
    # docker-compose.hub.yml declara la variable como requerida: sin esto,
    # `gaia.py start --hub` moría con un traceback de compose en cualquier
    # instalación anterior a que la variable existiera.
    env = tmp_path / ".env"
    env.write_text("PORT=8007\nGAIA_DB_PASSWORD=yaesta\n", encoding="utf-8")
    monkeypatch.setattr(common, "ENV_FILE", env)

    common.ensure_env()

    token = common.read_env_var(env, "WATCHTOWER_HTTP_API_TOKEN")
    assert len(token) == 64
    assert "GAIA_DB_PASSWORD=yaesta" in env.read_text(encoding="utf-8")


def test_no_se_pisa_un_token_ya_generado(monkeypatch, tmp_path):
    env = tmp_path / ".env"
    env.write_text("WATCHTOWER_HTTP_API_TOKEN=" + "a" * 64 + "\n", encoding="utf-8")
    monkeypatch.setattr(common, "ENV_FILE", env)

    common.ensure_env()

    assert common.read_env_var(env, "WATCHTOWER_HTTP_API_TOKEN") == "a" * 64


def test_password_regenerada_sincroniza_la_url_del_postgresql_interno(
    monkeypatch, tmp_path
):
    env = tmp_path / ".env"
    env.write_text(
        "DATABASE_URL=postgresql://gaia:changeme@postgres:5432/iagentshub\n"
        "GAIA_DB_PASSWORD=changeme\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(common, "ENV_FILE", env)

    common.ensure_env()

    password = common.read_env_var(env, "GAIA_DB_PASSWORD")
    assert password != "changeme"
    assert common.read_env_var(env, "DATABASE_URL") == (
        f"postgresql://gaia:{password}@postgres:5432/iagentshub"
    )


def test_password_regenerada_no_reescribe_una_base_externa(monkeypatch, tmp_path):
    env = tmp_path / ".env"
    external_url = "postgresql://cliente:secreto@db.example.com:5432/produccion"
    env.write_text(
        f"DATABASE_URL={external_url}\nGAIA_DB_PASSWORD=changeme\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(common, "ENV_FILE", env)

    common.ensure_env()

    assert common.read_env_var(env, "GAIA_DB_PASSWORD") != "changeme"
    assert common.read_env_var(env, "DATABASE_URL") == external_url


@pytest.mark.parametrize("command", ["cmd_stop", "cmd_logs", "cmd_status"])
def test_comandos_docker_preparan_env_antes_de_compose(monkeypatch, command):
    llamadas = []
    monkeypatch.setattr(compose_mod, "check_docker", lambda: llamadas.append("docker"))
    monkeypatch.setattr(compose_mod, "ensure_env", lambda: llamadas.append("env"))
    monkeypatch.setattr(
        compose_mod.subprocess,
        "run",
        lambda *args, **kwargs: llamadas.append("compose"),
    )

    getattr(compose_mod, command)(["docker", "compose"])

    assert llamadas[:3] == ["docker", "env", "compose"]


@pytest.mark.skipif(common.os.name == "nt", reason="Windows gestiona permisos con ACL")
def test_ensure_env_deja_los_secretos_solo_para_el_propietario(monkeypatch, tmp_path):
    env = tmp_path / ".env"
    env.write_text("GAIA_DB_PASSWORD=" + "a" * 64 + "\n", encoding="utf-8")
    env.chmod(0o644)
    monkeypatch.setattr(common, "ENV_FILE", env)

    common.ensure_env()

    assert env.stat().st_mode & 0o777 == 0o600


def test_env_sin_salto_final_no_pega_dos_variables(monkeypatch, tmp_path):
    # Un .env editado a mano puede no acabar en \n; sin cuidar el salto,
    # compose leería «PORT=8007WATCHTOWER_HTTP_API_TOKEN=…» como un solo valor.
    env = tmp_path / ".env"
    env.write_text("PORT=8007", encoding="utf-8")
    monkeypatch.setattr(common, "ENV_FILE", env)

    common.ensure_env()

    assert common.read_env_var(env, "PORT") == "8007"
    assert len(common.read_env_var(env, "WATCHTOWER_HTTP_API_TOKEN")) == 64


def test_el_ejemplo_declara_el_token_sin_valor():
    # Con valor sería el mismo secreto en todas las instalaciones; sin la
    # línea, un .env recién creado vuelve a romper `--hub`.
    lineas = (REPO_ROOT / ".env.example").read_text(encoding="utf-8").splitlines()
    assert "WATCHTOWER_HTTP_API_TOKEN=" in lineas


def test_env_nuevo_configura_postgresql_por_defecto(monkeypatch, tmp_path):
    env_example = tmp_path / ".env.example"
    env_example.write_text(
        "GAIA_AGENTS_SECRET=\n"
        "DATABASE_URL=\n"
        "GAIA_DB_PASSWORD=\n"
        "WATCHTOWER_HTTP_API_TOKEN=\n",
        encoding="utf-8",
    )
    env = tmp_path / ".env"
    monkeypatch.setattr(common, "IAGENTS_DIR", tmp_path)
    monkeypatch.setattr(common, "ENV_FILE", env)

    common.ensure_env()

    password = common.read_env_var(env, "GAIA_DB_PASSWORD")
    assert len(password) == 64
    assert common.read_env_var(env, "DATABASE_URL") == (
        f"postgresql://gaia:{password}@postgres:5432/iagentshub"
    )


# ── Un modo para el otro: los dos publican el mismo puerto ────────────────────


@pytest.mark.parametrize(
    ("hub", "esperado"),
    [
        (True, compose_mod.COMPOSE_DEV),
        (False, compose_mod.COMPOSE_HUB),
    ],
)
def test_arrancar_un_modo_baja_el_contrario(monkeypatch, hub, esperado):
    ejecutados = []

    class _Resultado:
        stdout = "abc123\n"  # el otro stack tiene contenedores vivos

    def _fake_run(args, **kwargs):
        ejecutados.append(args)
        return _Resultado()

    monkeypatch.setattr(compose_mod.subprocess, "run", _fake_run)

    compose_mod._stop_other_mode(hub, {})

    assert ejecutados == [
        ["docker", "compose", *esperado, "ps", "-q"],
        ["docker", "compose", *esperado, "down", "--remove-orphans"],
    ]


def test_no_se_baja_nada_si_el_otro_modo_no_corre(monkeypatch):
    ejecutados = []

    class _Vacio:
        stdout = ""

    def _fake_run(args, **kwargs):
        ejecutados.append(args)
        return _Vacio()

    monkeypatch.setattr(compose_mod.subprocess, "run", _fake_run)

    compose_mod._stop_other_mode(True, {})

    assert ejecutados == [["docker", "compose", *compose_mod.COMPOSE_DEV, "ps", "-q"]]
