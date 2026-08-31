"""Resolve and verify the exact cross-repository revisions used in images."""

from __future__ import annotations

import argparse
import json
import os
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from datetime import datetime
from pathlib import Path
from typing import Any

API_ROOT = "https://api.github.com"
ORGANIZATION = "iagentshub"
REPOSITORIES = ("backend_fastapi", "frontend_react", "app_flutter", "iAgents")

# El job que cada repositorio tiene que tener en verde. Vive aquí y no en el
# YAML porque `resolve` lo necesita para retroceder, y dos copias divergen:
# test_checks_declarados_una_sola_vez compara esta tabla con el workflow.
CHECKS = {
    "backend_fastapi": "test",
    "frontend_react": "verify",
    "app_flutter": "validate",
    "iAgents": "validate",
}

# Cuánto se tolera publicar por detrás de main cuando el CI de un repo está
# roto. Sin tope, un repositorio con el CI averiado varios días seguiría
# publicando su versión antigua sin que nadie lo note: se cambiaría un fallo
# ruidoso —la imagen se congela— por uno callado, que es peor.
MAX_COMMITS_ATRAS = 20
MAX_HORAS_ATRAS = 24


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


    def commits_de_main(self, repository: str) -> list[dict[str, Any]]:
        return list(
            self.get(
                f"/repos/{ORGANIZATION}/{repository}/commits"
                f"?sha=main&per_page={MAX_COMMITS_ATRAS}"
            )
        )

    def ultimo_verde(self, repository: str, check_name: str) -> tuple[str, int, float]:
        """El commit de main más reciente cuyo job está en verde.

        Devuelve (sha, commits_atras, horas_atras). El HEAD es commits_atras=0.
        """
        commits = self.commits_de_main(repository)
        if not commits:
            raise RuntimeError(f"{repository}: main no devolvio commits")
        cabeza = _fecha(commits[0])
        for posicion, commit in enumerate(commits):
            sha = str(commit["sha"])
            if self.check_state(repository, sha, check_name) != "success":
                continue
            horas = (cabeza - _fecha(commit)).total_seconds() / 3600
            return sha, posicion, horas
        raise RuntimeError(
            f"{repository}: ninguno de los ultimos {len(commits)} commits de main "
            f"supero el check {check_name}"
        )


def _fecha(commit: dict[str, Any]) -> datetime:
    marca = commit["commit"]["committer"]["date"]
    return datetime.fromisoformat(marca.replace("Z", "+00:00"))


def write_outputs(values: dict[str, str], output_path: str | None) -> None:
    if not output_path:
        return
    with Path(output_path).open("a", encoding="utf-8") as output:
        output.writelines(f"{key}={value}\n" for key, value in values.items())


def revision(api: GitHubAPI, repository: str) -> str:
    """El commit de `repository` que entra en la imagen.

    Normalmente el HEAD de main. Cuando su check está en rojo, el último verde:
    `verify` exige los cuatro en verde, así que un test caducado en cualquiera
    de ellos congelaba la imagen entera —incluidos los cambios ya validados de
    los otros tres—. Pasó el 30/08: un test con una fecha fija salió de su
    ventana de 90 días, y entre ese push y el arreglo no se publicó nada
    durante casi doce horas.

    Un check `pending` NO retrocede, y esa distinción es el punto entero: el
    aviso de cada repo llega con su CI todavía en curso, así que tomar «el
    último verde» a secas publicaría el commit anterior en cada push y dejaría
    el aviso sin efecto. Retroceder es el remedio ante un rojo, no la política.
    """
    sha = api.main_sha(repository)
    check = CHECKS[repository]
    if api.check_state(repository, sha, check) != "failure":
        return sha

    verde, atras, horas = api.ultimo_verde(repository, check)
    if horas > MAX_HORAS_ATRAS:
        raise RuntimeError(
            f"{repository}: el ultimo commit de main con {check} en verde es "
            f"{verde[:7]}, {horas:.0f} h por detras (tope {MAX_HORAS_ATRAS} h). "
            "Publicar una version tan vieja en silencio es peor que no publicar"
        )
    print(
        f"::warning::{repository}: main@{sha[:7]} tiene {check} en rojo; "
        f"se publica {verde[:7]}, {atras} commits y {horas:.1f} h por detras"
    )
    return verde


def resolve(api: GitHubAPI) -> dict[str, str]:
    values = {
        "backend_sha": revision(api, "backend_fastapi"),
        "frontend_sha": revision(api, "frontend_react"),
        "app_sha": revision(api, "app_flutter"),
        "orchestrator_sha": revision(api, "iAgents"),
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
