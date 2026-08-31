"""Guard del aviso que cada repo empaquetado manda a iAgents.

Los tres repos que entran en `ghcr.io/iagentshub/app` disparan un
`repository_dispatch` en cuanto su CI pasa en main, para que la imagen no
espere al cron —que GitHub atrasa de 3 a 7 h pese a estar declarado horario—.

El paso estaba escrito como `if [ -z "$GH_TOKEN" ] || ! gh api …; then
echo "::warning::…"`, y ahí caben tres averías distintas con la misma salida:
un secreto que nadie configuró, uno caducado y uno sin permisos. Las tres
daban un aviso amarillo dentro de un job verde, y nadie mira los warnings de
un job que pasó: el de app_flutter llevaba meses respondiendo 403 en cada push
sin que constara en ninguna parte, y la imagen dependía del cron sin saberlo.

Sin secreto se sigue avisando y punto —es una instalación que no participa—,
pero un token que está y no vale es una avería de la cadena de entrega y tiene
que poner el job en rojo el mismo día.

Los repositorios hermanos se resuelven como en test_backend.py: variable de
entorno, o directorio hermano. Si no están, se salta.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest
import yaml

from scripts.verified_revisions import CHECKS

REPO_ROOT = Path(__file__).parent.parent

REPOS_HERMANOS = {
    "backend_fastapi": "BACKEND_DIR",
    "app_flutter": "APP_FLUTTER_DIR",
    "frontend_react": "FRONTEND_REACT_DIR",
}


def _repo_dir(nombre: str) -> Path:
    env = os.environ.get(REPOS_HERMANOS[nombre])
    return Path(env) if env else REPO_ROOT.parent / nombre


def _pasos_de_aviso(raiz: Path) -> list[dict]:
    """Los pasos «Avisar a iAgents» de todos los workflows del repo."""
    workflows = raiz / ".github" / "workflows"
    if not workflows.is_dir():
        return []
    pasos = []
    for fichero in sorted(workflows.glob("*.yml")):
        definicion = yaml.safe_load(fichero.read_text(encoding="utf-8")) or {}
        for job in (definicion.get("jobs") or {}).values():
            for paso in job.get("steps") or []:
                if "Avisar a iAgents" in str(paso.get("name", "")):
                    pasos.append(paso)
    return pasos


@pytest.mark.parametrize("repo", sorted(REPOS_HERMANOS))
def test_el_aviso_falla_si_el_token_esta_configurado_y_no_vale(repo):
    raiz = _repo_dir(repo)
    if not raiz.is_dir():
        pytest.skip(f"{repo} no esta clonado junto a este repositorio")

    pasos = _pasos_de_aviso(raiz)
    if not pasos:
        pytest.skip(f"{repo} ya no avisa a iAgents")

    for paso in pasos:
        guion = paso.get("run", "")
        assert "::warning::" in guion, (
            f"{repo}: sin el secreto el aviso debe anotar y seguir, no fallar"
        )
        assert "::error::" in guion and "exit 1" in guion, (
            f"{repo}: un token que esta y no vale tiene que poner el job en rojo; "
            "hoy pasa por el mismo warning que no tenerlo"
        )


@pytest.mark.parametrize("repo", sorted(REPOS_HERMANOS))
def test_el_aviso_no_confunde_la_ausencia_del_secreto_con_su_fallo(repo):
    """Las dos ramas tienen que estar separadas, no encadenadas con `||`."""
    raiz = _repo_dir(repo)
    if not raiz.is_dir():
        pytest.skip(f"{repo} no esta clonado junto a este repositorio")

    pasos = _pasos_de_aviso(raiz)
    if not pasos:
        pytest.skip(f"{repo} ya no avisa a iAgents")

    for paso in pasos:
        guion = " ".join(paso.get("run", "").split())
        assert '[ -z "$GH_TOKEN" ] || ! gh api' not in guion, (
            f"{repo}: ese `||` es justo lo que hace indistinguibles «no hay "
            "token» y «el token no vale»"
        )


def test_un_fallo_desatendido_deja_senal_fuera_de_actions():
    """Doce horas sin imagen tienen que producir algo que alguien vea."""
    workflow = yaml.safe_load(
        (REPO_ROOT / ".github" / "workflows" / "docker-publish.yml").read_text(
            encoding="utf-8"
        )
    )

    señal = workflow["jobs"].get("senal-de-la-cadena")
    assert señal, (
        "sin este job, un cron o un aviso en rojo solo se ve entrando en la "
        "pestaña Actions, que es como se estuvieron 12 h sin publicar imagen"
    )

    condicion = señal["if"]
    for evento in ("schedule", "repository_dispatch"):
        assert evento in condicion, (
            f"{evento} es desatendido: si falla, nadie lo mira"
        )

    assert señal.get("permissions", {}).get("issues") == "write"

    guion = "\n".join(paso.get("run", "") for paso in señal["steps"])
    assert "gh issue create" in guion and "gh issue comment" in guion, (
        "la issue tiene que reutilizarse: tres schedules fallidos seguidos son "
        "tres issues del mismo problema, y ese ruido se ignora igual que el "
        "warning que este trabajo vino a quitar"
    )
    assert "gh issue close" in guion, (
        "una issue que sigue abierta despues de arreglarse es el mismo ruido "
        "por el otro lado"
    )


@pytest.mark.parametrize("repo", sorted(REPOS_HERMANOS))
def test_el_aviso_no_vive_en_el_job_que_el_preflight_exige(repo):
    """Que el aviso falle no puede tumbar el veredicto sobre el código.

    En app_flutter el aviso era un paso de `validate`, que es el check que el
    preflight exige en verde para meter ese commit en la imagen. Al hacer que
    el aviso falle, un token caducado tumbaba `validate` y el preflight se
    quedaba retrocediendo al commit anterior de Flutter mientras durase — una
    avería de la cadena de entrega respondiendo por una pregunta que no es la
    suya. Son dos preguntas distintas y necesitan dos jobs.
    """
    raiz = _repo_dir(repo)
    if not raiz.is_dir():
        pytest.skip(f"{repo} no esta clonado junto a este repositorio")

    exigido = CHECKS[repo]
    workflows = raiz / ".github" / "workflows"
    if not workflows.is_dir():
        pytest.skip(f"{repo} no tiene workflows")

    for fichero in sorted(workflows.glob("*.yml")):
        definicion = yaml.safe_load(fichero.read_text(encoding="utf-8")) or {}
        for nombre, job in (definicion.get("jobs") or {}).items():
            avisa = any(
                "Avisar a iAgents" in str(paso.get("name", ""))
                for paso in job.get("steps") or []
            )
            assert not (avisa and nombre == exigido), (
                f"{repo}: el aviso vive en «{nombre}», que es el check que el "
                f"preflight exige en verde. Un token caducado pondria en rojo "
                f"el veredicto sobre el codigo y la imagen retrocederia sola"
            )
