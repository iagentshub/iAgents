"""Regresiones del validador estructural de Docker Compose."""

from __future__ import annotations

from pathlib import Path

import pytest

from gaia_cli import common, validation


class _Resultado:
    def __init__(self, returncode=0, stderr=""):
        self.returncode = returncode
        self.stderr = stderr
        self.stdout = ""


def test_docker_ausente_falla_con_mensaje_controlado(monkeypatch, capsys):
    monkeypatch.setattr(common.shutil, "which", lambda _: None)

    with pytest.raises(SystemExit, match="1"):
        common.check_docker_cli()

    assert "Docker no está instalado" in capsys.readouterr().err


def test_gaia_prepara_env_y_valida_los_cinco_composes(monkeypatch, tmp_path):
    llamadas = []
    docker_comprobado = []

    def preparar_env():
        (tmp_path / ".env").write_text(
            "GAIA_DB_PASSWORD=" + "a" * 64 + "\n", encoding="utf-8"
        )

    def ejecutar(args, **kwargs):
        assert (tmp_path / ".env").is_file()
        llamadas.append((args, kwargs))
        return _Resultado()

    monkeypatch.setattr(validation, "IAGENTS_DIR", tmp_path)
    monkeypatch.setattr(
        validation, "check_docker_cli", lambda: docker_comprobado.append(True)
    )
    monkeypatch.setattr(validation, "ensure_env", preparar_env)
    monkeypatch.setattr(validation.subprocess, "run", ejecutar)

    validation.cmd_validate()

    assert len(llamadas) == 5
    assert docker_comprobado == [True]
    assert all(args[:2] == ["docker", "compose"] for args, _ in llamadas)
    assert all(kwargs["cwd"] == tmp_path for _, kwargs in llamadas)
    assert all(kwargs["check"] is False for _, kwargs in llamadas)


def test_gaia_falla_si_un_compose_no_valida(monkeypatch, tmp_path):
    resultados = iter([_Resultado(), _Resultado(1, "config inválida")])
    monkeypatch.setattr(validation, "IAGENTS_DIR", tmp_path)
    monkeypatch.setattr(validation, "check_docker_cli", lambda: None)
    monkeypatch.setattr(validation, "ensure_env", lambda: None)
    monkeypatch.setattr(
        validation.subprocess, "run", lambda *args, **kwargs: next(resultados)
    )
    monkeypatch.setattr(validation, "_COMPOSES", validation._COMPOSES[:2])

    with pytest.raises(SystemExit, match="1"):
        validation.cmd_validate()


def test_ci_y_wrapper_entran_por_gaia():
    root = Path(__file__).parent.parent
    workflow = (root / ".github/workflows/validate.yml").read_text(encoding="utf-8")
    wrapper = (root / "scripts/validar-composes.sh").read_text(encoding="utf-8")

    assert "run: python3 gaia.py validate" in workflow
    assert "exec python3 gaia.py validate" in wrapper
