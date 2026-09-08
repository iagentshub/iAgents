from __future__ import annotations

import json
import re
import urllib.error
from pathlib import Path

import pytest

from scripts.verified_revisions import CHECKS, GitHubAPI, resolve, revision, verify


class Response:
    def __init__(self, payload):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return None

    def read(self):
        return json.dumps(self.payload).encode()


def runs_y_jobs(*jobs):
    """Los dos payloads que consume un check_state: el run del SHA y sus jobs."""
    return [{"workflow_runs": [{"id": 7}]}, {"jobs": list(jobs)}]


def job(nombre, conclusion="success", status="completed"):
    return {"name": nombre, "status": status, "conclusion": conclusion}


def repo_resuelto(sha, *jobs):
    """Lo que consume resolve() por repositorio: el HEAD de main y su check."""
    return [{"object": {"sha": sha}}, *runs_y_jobs(*jobs)]


def commit(sha, fecha):
    return {"sha": sha, "commit": {"committer": {"date": fecha}}}


def opener_for(payloads):
    remaining = iter(payloads)

    def open_request(_request, timeout):
        assert timeout == 30
        return Response(next(remaining))

    return open_request


def test_resolve_fija_los_cuatro_shas_de_main():
    api = GitHubAPI(
        opener=opener_for(
            repo_resuelto("b" * 40, job("test"))
            + repo_resuelto("f" * 40, job("verify"))
            + repo_resuelto("a" * 40, job("validate"))
            + repo_resuelto("i" * 40, job("validate"))
        )
    )

    assert resolve(api) == {
        "backend_sha": "b" * 40,
        "frontend_sha": "f" * 40,
        "app_sha": "a" * 40,
        "orchestrator_sha": "i" * 40,
    }


def test_verify_espera_hasta_que_el_check_termine(monkeypatch):
    api = GitHubAPI(
        opener=opener_for(
            runs_y_jobs({"name": "test", "status": "in_progress", "conclusion": None})
            + runs_y_jobs({"name": "test", "status": "completed", "conclusion": "success"})
        )
    )
    monkeypatch.setattr("scripts.verified_revisions.time.sleep", lambda _seconds: None)

    verify(api, [("backend_fastapi", "a" * 40, "test")], timeout_seconds=5, poll_seconds=0)


def test_verify_rechaza_un_check_rojo():
    api = GitHubAPI(
        opener=opener_for(
            runs_y_jobs({"name": "verify", "status": "completed", "conclusion": "failure"})
        )
    )

    with pytest.raises(RuntimeError, match="no supero"):
        verify(
            api,
            [("frontend_react", "a" * 40, "verify")],
            timeout_seconds=0,
            poll_seconds=0,
        )


def test_verify_no_confunde_checks_de_otro_nombre():
    api = GitHubAPI(
        opener=opener_for(
            runs_y_jobs({"name": "publish", "status": "completed", "conclusion": "success"})
        )
    )

    with pytest.raises(TimeoutError, match="Checks sin completar"):
        verify(
            api,
            [("app_flutter", "a" * 40, "validate")],
            timeout_seconds=0,
            poll_seconds=0,
        )


def test_el_404_de_un_repo_privado_explica_que_mirar():
    """Un 404 puede ser «no existe» o «el token no lo alcanza»: hay que decirlo."""

    def open_request(request, timeout):
        assert timeout == 30
        raise urllib.error.HTTPError(request.full_url, 404, "Not Found", {}, None)

    api = GitHubAPI(opener=open_request)

    with pytest.raises(RuntimeError, match="privado y fuera del alcance"):
        api.main_sha("frontend_react")


def test_los_jobs_salen_de_todos_los_runs_del_commit():
    """Un mismo SHA dispara varios workflows; el job exigido puede estar en cualquiera."""
    api = GitHubAPI(
        opener=opener_for(
            [
                {"workflow_runs": [{"id": 1}, {"id": 2}]},
                {"jobs": [{"name": "publish", "status": "completed", "conclusion": "success"}]},
                {"jobs": [{"name": "verify", "status": "completed", "conclusion": "success"}]},
            ]
        )
    )

    assert api.check_state("frontend_react", "a" * 40, "verify") == "success"


def test_no_se_pide_la_checks_api_que_un_pat_no_puede_leer():
    """El permiso «Checks» no existe para un PAT fine-grained: nadie puede volver ahí."""
    pedidas: list[str] = []

    def open_request(request, timeout):
        assert timeout == 30
        pedidas.append(request.full_url)
        return Response({"workflow_runs": []})

    GitHubAPI(opener=open_request).check_state("frontend_react", "a" * 40, "verify")

    assert pedidas and not any("check-runs" in url for url in pedidas)


def test_un_check_pendiente_no_hace_retroceder():
    """El aviso de cada repo llega con su CI en curso: retroceder ahí lo anula."""
    api = GitHubAPI(
        opener=opener_for(
            repo_resuelto("b" * 40, job("test", conclusion=None, status="in_progress"))
        )
    )

    assert revision(api, "backend_fastapi") == "b" * 40


def test_un_check_rojo_retrocede_al_ultimo_verde():
    """Un test caducado en un repo no puede congelar la imagen de los otros tres."""
    api = GitHubAPI(
        opener=opener_for(
            # HEAD de main, en rojo.
            [{"object": {"sha": "b" * 40}}]
            + runs_y_jobs(job("test", conclusion="failure"))
            # La lista de commits, y el anterior en verde.
            + [
                [
                    commit("b" * 40, "2026-08-31T12:00:00Z"),
                    commit("c" * 40, "2026-08-31T09:00:00Z"),
                ]
            ]
            + runs_y_jobs(job("test", conclusion="failure"))
            + runs_y_jobs(job("test", conclusion="success"))
        )
    )

    assert revision(api, "backend_fastapi") == "c" * 40


def test_no_se_publica_un_verde_mas_viejo_que_el_tope():
    """Cambiar «la imagen se congela» por «publica algo de anteayer» es peor."""
    api = GitHubAPI(
        opener=opener_for(
            [{"object": {"sha": "b" * 40}}]
            + runs_y_jobs(job("test", conclusion="failure"))
            + [
                [
                    commit("b" * 40, "2026-08-31T12:00:00Z"),
                    commit("c" * 40, "2026-08-25T09:00:00Z"),
                ]
            ]
            + runs_y_jobs(job("test", conclusion="failure"))
            + runs_y_jobs(job("test", conclusion="success"))
        )
    )

    with pytest.raises(RuntimeError, match="por detras"):
        revision(api, "backend_fastapi")


def test_los_checks_se_declaran_una_sola_vez():
    """CHECKS y el --require del workflow tienen que decir lo mismo."""
    workflow = (
        Path(__file__).parent.parent
        / ".github"
        / "workflows"
        / "docker-publish.yml"
    ).read_text(encoding="utf-8")

    declarados = dict(re.findall(r'--require "(\w+):\$\w+:(\w+)"', workflow))

    assert declarados == CHECKS


def test_los_jobs_recorren_todas_las_paginas_de_runs():
    """El mismo SHA acumula runs de docker-publish cada hora: el `validate` que
    importa se cae de la primera página a los cuatro días y el check parecía
    pendiente para siempre."""
    pedidas: list[str] = []
    pagina_1 = {"workflow_runs": [{"id": n, "status": "completed"} for n in range(100)]}
    pagina_2 = {"workflow_runs": [{"id": 100, "status": "completed"}]}
    jobs_publish = {"jobs": [job("preflight")]}
    jobs_validate = {"jobs": [job("validate")]}

    def open_request(request, timeout):
        assert timeout == 30
        pedidas.append(request.full_url)
        if "/actions/runs?" in request.full_url:
            return Response(pagina_2 if "page=2" in request.full_url else pagina_1)
        if "/runs/100/jobs" in request.full_url:
            return Response(jobs_validate)
        return Response(jobs_publish)

    api = GitHubAPI(opener=open_request)

    assert api.check_state("iAgents", "a" * 40, "validate") == "success"
    assert any("page=2" in url for url in pedidas)
    assert not any("page=3" in url for url in pedidas)


def test_verify_no_reconsulta_los_jobs_de_runs_terminados(monkeypatch):
    """Sondear cada 15 s los jobs de cien runs ya cerrados agotó el límite de
    la API (403) a mitad de espera. Un run completado no cambia: se pide una vez."""
    pedidas: list[str] = []
    runs = {
        "workflow_runs": [
            {"id": 1, "status": "completed"},
            {"id": 2, "status": "in_progress"},
        ]
    }
    estado_run_2 = iter(
        [
            {"jobs": [job("validate", conclusion=None, status="in_progress")]},
            {"jobs": [job("validate")]},
        ]
    )

    def open_request(request, timeout):
        assert timeout == 30
        pedidas.append(request.full_url)
        if "/actions/runs?" in request.full_url:
            return Response(runs)
        if "/runs/1/jobs" in request.full_url:
            return Response({"jobs": [job("preflight")]})
        return Response(next(estado_run_2))

    monkeypatch.setattr("scripts.verified_revisions.time.sleep", lambda _seconds: None)
    api = GitHubAPI(opener=open_request)

    verify(api, [("iAgents", "a" * 40, "validate")], timeout_seconds=5, poll_seconds=0)

    assert sum("/runs/1/jobs" in url for url in pedidas) == 1
    assert sum("/runs/2/jobs" in url for url in pedidas) == 2


def test_un_5xx_de_github_se_reintenta(monkeypatch):
    """Un 502 aislado a los 25 minutos de espera tiraba la publicación entera."""
    intentos = {"n": 0}

    def open_request(request, timeout):
        assert timeout == 30
        intentos["n"] += 1
        if intentos["n"] == 1:
            raise urllib.error.HTTPError(request.full_url, 502, "Bad Gateway", {}, None)
        return Response({"object": {"sha": "b" * 40}})

    monkeypatch.setattr("scripts.verified_revisions.time.sleep", lambda _seconds: None)

    assert GitHubAPI(opener=open_request).main_sha("backend_fastapi") == "b" * 40
    assert intentos["n"] == 2


def test_el_403_por_limite_de_peticiones_lo_dice():
    """Un 403 por cuota agotada no es un problema de permisos del token."""

    def open_request(request, timeout):
        assert timeout == 30
        raise urllib.error.HTTPError(
            request.full_url, 403, "Forbidden", {"X-RateLimit-Remaining": "0"}, None
        )

    with pytest.raises(RuntimeError, match="limite de peticiones"):
        GitHubAPI(opener=open_request).main_sha("iAgents")
