"""Resolve and verify the exact cross-repository revisions used in images."""

from __future__ import annotations

import argparse
import json
import os
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from pathlib import Path
from typing import Any

API_ROOT = "https://api.github.com"
ORGANIZATION = "iagentshub"
REPOSITORIES = ("backend_fastapi", "frontend_react", "app_flutter", "iAgents")


# Un repositorio privado no responde 403 al token que no lo alcanza: responde
# 404, indistinguible de uno que no existe. Al privatizar frontend_react la
# cadena entera murió aquí, y el mensaje pelado no decía de dónde venía: hubo
# que abrir el código para saber qué mirar.
_PISTAS = {
    401: " (token inválido o caducado)",
    403: " (el token no tiene permiso; un repositorio privado necesita lectura"
    " de contenido y de Actions)",
    404: " (repositorio o referencia inexistente — o privado y fuera del alcance"
    " del token: a quien no puede verlo, GitHub le responde 404, no 403)",
}


def _pista(codigo: int) -> str:
    return _PISTAS.get(codigo, "")


class GitHubAPI:
    def __init__(
        self,
        token: str = "",
        opener: Callable[..., Any] = urllib.request.urlopen,
    ) -> None:
        self._token = token
        self._opener = opener

    def get(self, path: str) -> dict[str, Any]:
        headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "iagentshub-verified-revisions",
        }
        if self._token:
            headers["Authorization"] = f"Bearer {self._token}"
        request = urllib.request.Request(f"{API_ROOT}{path}", headers=headers)
        try:
            with self._opener(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            raise RuntimeError(
                f"GitHub API devolvio HTTP {exc.code} para {path}{_pista(exc.code)}"
            ) from exc

    def main_sha(self, repository: str) -> str:
        payload = self.get(
            f"/repos/{ORGANIZATION}/{repository}/git/ref/heads/main"
        )
        return str(payload["object"]["sha"])

    def jobs(self, repository: str, sha: str) -> list[dict[str, Any]]:
        """Los jobs de Actions de un commit, por los workflow runs que lo tocaron."""
        runs = self.get(
            f"/repos/{ORGANIZATION}/{repository}/actions/runs"
            f"?head_sha={sha}&per_page=100"
        )
        found: list[dict[str, Any]] = []
        for run in runs.get("workflow_runs", []):
            payload = self.get(
                f"/repos/{ORGANIZATION}/{repository}/actions/runs/{run['id']}"
                f"/jobs?per_page=100"
            )
            found.extend(payload.get("jobs", []))
        return found

    # Esto leía /commits/{sha}/check-runs, que es la Checks API — y GitHub la
    # reservó a las GitHub Apps: el permiso «Checks» no se le puede dar a un PAT
    # fine-grained, así que con frontend_react privado no había credencial
    # acotada capaz de verificarlo. La API de Actions responde lo mismo para lo
    # que aquí importa —los cuatro checks exigidos son jobs de Actions— y su
    # permiso «Actions: read» sí es asignable. Cuesta una llamada más por
    # workflow run, y `verify` solo reconsulta lo que sigue pendiente.
    def check_state(self, repository: str, sha: str, check_name: str) -> str:
        jobs = [job for job in self.jobs(repository, sha) if job["name"] == check_name]
        if any(job.get("conclusion") == "success" for job in jobs):
            return "success"
        if not jobs or any(job.get("status") != "completed" for job in jobs):
            return "pending"
        return "failure"


def write_outputs(values: dict[str, str], output_path: str | None) -> None:
    if not output_path:
        return
    with Path(output_path).open("a", encoding="utf-8") as output:
        output.writelines(f"{key}={value}\n" for key, value in values.items())


def resolve(api: GitHubAPI) -> dict[str, str]:
    values = {
        "backend_sha": api.main_sha("backend_fastapi"),
        "frontend_sha": api.main_sha("frontend_react"),
        "app_sha": api.main_sha("app_flutter"),
        "orchestrator_sha": api.main_sha("iAgents"),
    }
    for name, sha in values.items():
        print(f"{name}={sha}")
    return values


def verify(
    api: GitHubAPI,
    requirements: list[tuple[str, str, str]],
    *,
    timeout_seconds: float,
    poll_seconds: float,
) -> None:
    pending = list(requirements)
    deadline = time.monotonic() + timeout_seconds
    while pending:
        next_pending: list[tuple[str, str, str]] = []
        for repository, sha, check_name in pending:
            state = api.check_state(repository, sha, check_name)
            print(f"{repository}@{sha[:7]} check={check_name} state={state}")
            if state == "failure":
                raise RuntimeError(
                    f"{repository}@{sha[:7]} no supero el check {check_name}"
                )
            if state == "pending":
                next_pending.append((repository, sha, check_name))
        pending = next_pending
        if not pending:
            return
        if time.monotonic() >= deadline:
            unresolved = ", ".join(
                f"{repo}@{sha[:7]}:{check}" for repo, sha, check in pending
            )
            raise TimeoutError(f"Checks sin completar: {unresolved}")
        time.sleep(poll_seconds)


def requirement(value: str) -> tuple[str, str, str]:
    parts = value.split(":", 2)
    if len(parts) != 3 or parts[0] not in REPOSITORIES or not parts[1] or not parts[2]:
        raise argparse.ArgumentTypeError("usa REPO:SHA:CHECK")
    return parts[0], parts[1], parts[2]


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("resolve")
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("--require", action="append", type=requirement, required=True)
    verify_parser.add_argument("--timeout-seconds", type=float, default=1800)
    verify_parser.add_argument("--poll-seconds", type=float, default=15)
    args = parser.parse_args()

    api = GitHubAPI(os.getenv("GH_TOKEN", ""))
    if args.command == "resolve":
        write_outputs(resolve(api), os.getenv("GITHUB_OUTPUT"))
    else:
        verify(
            api,
            args.require,
            timeout_seconds=args.timeout_seconds,
            poll_seconds=args.poll_seconds,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
