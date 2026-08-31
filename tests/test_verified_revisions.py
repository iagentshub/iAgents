from __future__ import annotations

import json
import urllib.error

import pytest

from scripts.verified_revisions import GitHubAPI, resolve, verify


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


def opener_for(payloads):
    remaining = iter(payloads)

    def open_request(_request, timeout):
        assert timeout == 30
        return Response(next(remaining))

    return open_request


def test_resolve_fija_los_cuatro_shas_de_main():
    api = GitHubAPI(
        opener=opener_for(
            [{"object": {"sha": value}} for value in ("b" * 40, "f" * 40, "a" * 40, "i" * 40)]
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
