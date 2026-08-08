"""Contrato del entrypoint modular de gaia.py."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

from gaia_cli import cli, common

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


def test_cli_enruta_status_local_sin_docker(monkeypatch):
    calls = []
    monkeypatch.setattr(sys, "argv", ["gaia.py", "status", "--local"])
    monkeypatch.setattr(cli, "cmd_local_status", lambda: calls.append("local"))

    cli.main()

    assert calls == ["local"]


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
