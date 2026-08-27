from __future__ import annotations

import json

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
            [
                {"check_runs": [{"name": "test", "status": "in_progress", "conclusion": None}]},
                {"check_runs": [{"name": "test", "status": "completed", "conclusion": "success"}]},
            ]
        )
    )
    monkeypatch.setattr("scripts.verified_revisions.time.sleep", lambda _seconds: None)

    verify(api, [("backend_fastapi", "a" * 40, "test")], timeout_seconds=5, poll_seconds=0)


def test_verify_rechaza_un_check_rojo():
    api = GitHubAPI(
        opener=opener_for(
            [{"check_runs": [{"name": "verify", "status": "completed", "conclusion": "failure"}]}]
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
            [{"check_runs": [{"name": "publish", "status": "completed", "conclusion": "success"}]}]
        )
    )

    with pytest.raises(TimeoutError, match="Checks sin completar"):
        verify(
            api,
            [("app_flutter", "a" * 40, "validate")],
            timeout_seconds=0,
            poll_seconds=0,
        )
