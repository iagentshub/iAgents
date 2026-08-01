<div align="center">
  <a href="index.md">← Índice</a> &nbsp;·&nbsp;
  <a href="../en/ci.md">🇬🇧 Read in English</a>
</div>

<br>

# Calidad de configuración

El repositorio tiene dos capas de verificación automática que detectan errores en la configuración antes de que lleguen a la rama principal.

---

## Antes del commit

Un hook local revisa los ficheros de configuración en el momento de hacer commit. Si alguna verificación falla, el commit se cancela hasta que se corrija.

Verifica tres cosas:

- **Instalador** — analiza `install.sh` en busca de errores comunes de shell scripting.
- **Script de gestión** — comprueba que `gaia.py` compila sin errores de sintaxis.
- **Configuración de servicios** — valida que `docker-compose.yml` tiene una sintaxis correcta y que todos los servicios están bien definidos.

Para activarlo, ejecuta una vez tras clonar el repositorio:

```bash
pip install pre-commit
pre-commit install
```

A partir de ese momento se ejecuta automáticamente en cada `git commit`.

---

## En GitHub (push y pull requests)

Cada vez que se sube código a la rama principal o se abre una pull request, GitHub ejecuta las mismas verificaciones en un entorno limpio. Esto actúa como red de seguridad para cambios que lleguen sin el hook local instalado.

Un pull request no puede fusionarse si las verificaciones fallan.

## Publicación de imágenes

Los pushes a `main` generan imágenes multi-plataforma (`amd64` y `arm64`) y
las publican en GitHub Container Registry. La imagen unificada es
`ghcr.io/iagentshub/app:latest`; también se conserva un tag React inmutable por
compilación. Los cambios en iAgents, backend, React o Flutter reconstruyen esa
imagen desde el código actual de los cuatro repositorios.

El paquete `iagentshub/app` debe configurarse como público en GitHub y conceder
acceso de escritura de Actions a los cuatro repositorios para que los
instaladores puedan descargarlo sin credenciales y todos los workflows puedan
publicarlo.
