# install.ps1 — Instalación y actualización de iAgents Hub (Windows)
#
# Un único comando para instalar el frontend React en Docker o sin Docker.
#
#   irm https://raw.githubusercontent.com/iagentshub/iAgents/main/install.ps1 | iex
#
# Para saltarte los prompts (reinstalación no interactiva):
#   $env:IAGENTSHUB_MODE     = "docker"    # o "local"
#   irm .../install.ps1 | iex
#
# Docker:     requiere Docker Desktop. No clona repositorios (usa imágenes de Docker Hub).
# Sin Docker: instala Python 3.11+, git y Node.js LTS vía winget,
#             clona los repos como hermanos y arranca con gaia.py --local (SQLite).

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Colores ───────────────────────────────────────────────────────────────────
function Write-Info    { param($m) Write-Host "[iagentshub] $m" -ForegroundColor Cyan }
function Write-Success { param($m) Write-Host "[iagentshub] $m" -ForegroundColor Green }
function Write-Warn    { param($m) Write-Host "[iagentshub] $m" -ForegroundColor Yellow }
function Write-Fail    { param($m) Write-Error "[iagentshub] $m" }
function Write-Step    { param($m) Write-Host "`n── $m ──────────────────────────────────────" -ForegroundColor White }

# ── Ayuda ─────────────────────────────────────────────────────────────────────
if (($args -contains '-h') -or ($args -contains '--help') -or ($args -contains '/?') -or ($args -contains 'help')) {
    Write-Host @"
Uso: install.ps1

Instala o actualiza iAgents Hub con el frontend React. Pregunta interactivamente:
  1) Modo: Docker (recomendado) o sin Docker (Python/Node directos, SQLite)

Variables de entorno (para saltarte los prompts):
  `$env:IAGENTSHUB_MODE     = "docker"|"local"    Modo de instalacion
  `$env:IAGENTSHUB_DIR      = "<ruta>"            Directorio de instalacion (default: `$env:USERPROFILE\iagentshub)

Ejemplos:
  irm https://raw.githubusercontent.com/iagentshub/iAgents/main/install.ps1 | iex
  `$env:IAGENTSHUB_MODE = "docker"; irm .../install.ps1 | iex

Requisitos:
  Docker:     requiere Docker Desktop (no clona repositorios, usa imagenes de Docker Hub).
  Sin Docker: instala Python 3.11+, git y Node.js LTS vía winget.
"@
    exit 0
}

$RepoUrl            = "https://github.com/iagentshub/iAgents.git"
$BackendRepoUrl     = "https://github.com/iagentshub/backend_fastapi.git"
$FrontendReactUrl   = "https://github.com/iagentshub/frontend_react.git"
$GithubRaw   = "https://raw.githubusercontent.com/iagentshub/iAgents/main"
$ComposeUrl  = "$GithubRaw/docker-compose.hub.yml"
$InstallDir  = if ($env:IAGENTSHUB_DIR) { $env:IAGENTSHUB_DIR } else { "$env:USERPROFILE\iagentshub" }

function New-RandomHex {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    [BitConverter]::ToString($bytes).Replace('-', '').ToLower()
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor White
Write-Host "║           iAgents Hub                   ║" -ForegroundColor White
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor White
Write-Host ""

# ── Modo de instalación ───────────────────────────────────────────────────────
Write-Step "Modo de instalacion"
Write-Host "  1) Docker      - recomendado, aislado, incluye PostgreSQL opcional"
Write-Host "  2) Sin Docker  - Python + Node.js directos, SQLite"
$InstallMode = $env:IAGENTSHUB_MODE
if (-not $InstallMode) {
    $ans = Read-Host "  Elige [1-2] (default 1)"
    $InstallMode = if ($ans -eq "2") { "local" } else { "docker" }
}
if ($InstallMode -notin @("docker", "local")) {
    Write-Fail "IAGENTSHUB_MODE debe ser 'docker' o 'local' (valor: $InstallMode)"
}
Write-Success "Modo: $InstallMode"

# ═══════════════════════════════════════════════════════════════════════════
# Rama Docker
# ═══════════════════════════════════════════════════════════════════════════
function Install-Docker {
    Write-Step "Comprobando Docker"
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Fail "Docker no esta instalado. Instala Docker Desktop: https://docs.docker.com/get-docker/"
    }
    docker info *>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Docker no esta en ejecucion. Arranca Docker Desktop e intentalo de nuevo."
    }
    Write-Success "Docker disponible."

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Set-Location $InstallDir
    $ComposeFile = "$InstallDir\docker-compose.yml"

    $FirstInstall = -not (Test-Path "$InstallDir\.env")
    if ($FirstInstall) { Write-Info "Primera instalacion en $InstallDir" }
    else { Write-Info "Actualizacion detectada en $InstallDir" }

    Write-Info "Sincronizando docker-compose.yml desde GitHub..."
    Invoke-WebRequest -Uri $ComposeUrl -OutFile $ComposeFile
    Write-Success "docker-compose.yml actualizado."

    if ($FirstInstall) {
        Write-Step "Configurando variables de entorno"
        Write-Host ""
        $FrontendUrl = Read-Host "  Dominio publico (ej: https://miapp.com) [http://localhost:8007]"
        if (-not $FrontendUrl) { $FrontendUrl = "http://localhost:8007" }
        $AdminEmail = Read-Host "  Email del administrador [admin@localhost.com]"
        if (-not $AdminEmail) { $AdminEmail = "admin@localhost.com" }
        $Port = Read-Host "  Puerto del frontend [8007]"
        if (-not $Port) { $Port = "8007" }

        $AgentsSecret = New-RandomHex
        $DbPassword = New-RandomHex

        $EnvContent = @"
# iAgents Hub -- configuracion generada el $(Get-Date -Format 'yyyy-MM-dd')
# Para cambiar la configuracion edita este fichero y ejecuta:
#   cd $InstallDir && docker compose up -d

PORT=$Port
GAIA_PORT=8765
GAIA_FRONTEND_URL=$FrontendUrl

# Secreto JWT -- generado automaticamente
GAIA_AGENTS_SECRET=$AgentsSecret

GAIA_ADMIN_EMAIL=$AdminEmail
# Descomenta para resetear la contrasena del admin en el proximo arranque:
# GAIA_ADMIN_RESET=true

# open | invite | closed
GAIA_REGISTRATION=closed
GAIA_EMAIL_VERIFY=false

# -- SMTP --
GAIA_SMTP_HOST=
GAIA_SMTP_PORT=587
GAIA_SMTP_TLS=starttls
GAIA_SMTP_USER=
GAIA_SMTP_PASS=
GAIA_SMTP_FROM=
GAIA_WEBMAIL_URL=
GAIA_RESET_EXPIRE_HOURS=1

GAIA_MAX_GUEST_SESSIONS=0

# -- Base de datos -- vacio = SQLite en /data/hub.db
DATABASE_URL=
GAIA_DB_PASSWORD=$DbPassword

# -- Stripe (opcional) --
STRIPE_SECRET_KEY=
STRIPE_PUBLISHABLE_KEY=
STRIPE_WEBHOOK_SECRET=

# -- Docker Hub --
DOCKER_HUB_USER=iagenthub
# Imagen React estable
IMAGE_TAG=latest

# -- Actualizacion automatica --
# Segundos entre comprobaciones de Watchtower (default 3600 = 1h). 0 la desactiva
# (ejecuta luego: docker compose stop watchtower).
WATCHTOWER_INTERVAL=3600

GAIA_TRUSTED_PROXIES=127.0.0.1
"@
        $EnvContent | Out-File -FilePath "$InstallDir\.env" -Encoding utf8
        Write-Success ".env creado."
    } else {
        Write-Warn ".env existente conservado. Edita $InstallDir\.env para cambiar la configuracion."
        $EnvPath = "$InstallDir\.env"
        $Lines = @(Get-Content $EnvPath)
        $FoundImageTag = $false
        $Lines = $Lines | ForEach-Object {
            if ($_ -match '^IMAGE_TAG=') {
                $FoundImageTag = $true
                'IMAGE_TAG=latest'
            } else { $_ }
        }
        if (-not $FoundImageTag) { $Lines += 'IMAGE_TAG=latest' }
        $Lines | Out-File -FilePath $EnvPath -Encoding utf8
        Write-Info "IMAGE_TAG=latest aplicado para usar React."
    }

    Write-Host ""
    if (-not $FirstInstall) {
        Write-Info "Descargando imagenes actualizadas..."
        docker compose -f $ComposeFile down
    } else {
        Write-Info "Descargando imagenes de Docker Hub..."
    }
    docker compose -f $ComposeFile pull
    docker compose -f $ComposeFile up -d

    Write-Info "Esperando que el backend arranque..."
    $AdminPass = ""
    for ($i = 0; $i -lt 40; $i++) {
        docker compose -f $ComposeFile exec -T iagentshub sh -c "test -f /data/.admin_pass" *>$null
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Seconds 3
    }
    $AdminPass = (docker compose -f $ComposeFile exec -T iagentshub sh -c "cat /data/.admin_pass" 2>$null) -join ""
    $AdminPass = $AdminPass.Trim()

    $PortFinal = $Port
    $AdminEmailFinal = $AdminEmail
    $FrontendUrlFinal = $FrontendUrl
    if (-not $FirstInstall) {
        Get-Content "$InstallDir\.env" | ForEach-Object {
            if ($_ -match "^PORT=") { $PortFinal = $_.Split("=", 2)[1].Trim() }
            if ($_ -match "^GAIA_ADMIN_EMAIL=") { $AdminEmailFinal = $_.Split("=", 2)[1].Trim() }
            if ($_ -match "^GAIA_FRONTEND_URL=") { $FrontendUrlFinal = $_.Split("=", 2)[1].Trim() }
        }
    }

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Green
    if ($FirstInstall) { Write-Host "║       Instalacion completada             ║" -ForegroundColor Green }
    else { Write-Host "║       Actualizacion completada           ║" -ForegroundColor Green }
    Write-Host "╠══════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "  URL         > $FrontendUrlFinal" -ForegroundColor Cyan
    Write-Host "  Frontend    > React" -ForegroundColor Cyan
    Write-Host "  Admin       > $AdminEmailFinal" -ForegroundColor Cyan
    if ($AdminPass) {
        Write-Host "  Contrasena  > $AdminPass" -ForegroundColor Green
    } else {
        Write-Host "  Contrasena  > ver: docker logs (grep -i pass)" -ForegroundColor Yellow
    }
    Write-Host "  Directorio  > $InstallDir"
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Logs:       cd $InstallDir && docker compose logs -f" -ForegroundColor Cyan
    Write-Host "  Parar:      cd $InstallDir && docker compose down" -ForegroundColor Cyan
    Write-Host "  Actualizar: automatico cada hora (Watchtower) - manual: irm $GithubRaw/install.ps1 | iex" -ForegroundColor Cyan
    Write-Host "  Desactivar auto-actualizacion: cd $InstallDir && docker compose stop watchtower" -ForegroundColor Cyan
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════
# Rama sin Docker
# ═══════════════════════════════════════════════════════════════════════════
function Install-Local {
    $EnvFile = "$InstallDir\iAgents\.env"
    $FirstInstall = -not (Test-Path $EnvFile)

    # ── 1. winget ─────────────────────────────────────────────────────────
    Write-Step "Comprobando winget"
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warn "winget no encontrado. Instala 'App Installer' desde Microsoft Store."
        Write-Fail "winget es necesario para la instalacion automatica."
    }
    Write-Success "winget disponible."

    # ── 2. Python >= 3.11 ─────────────────────────────────────────────────
    Write-Step "Comprobando Python 3.11+"
    $PythonExe = $null
    foreach ($candidate in @("python3.13", "python3.12", "python3.11", "python3", "python")) {
        $found = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($found) {
            $ver = & $candidate -c "import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)" 2>$null
            if ($LASTEXITCODE -eq 0) { $PythonExe = $candidate; break }
        }
    }
    if (-not $PythonExe) {
        Write-Info "Instalando Python 3.11 via winget..."
        winget install --id Python.Python.3.11 --silent --accept-package-agreements --accept-source-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
        $PythonExe = "python"
        Write-Success "Python instalado."
    } else {
        Write-Success "Python encontrado: $(& $PythonExe --version 2>&1)"
    }

    # ── 3. Git ────────────────────────────────────────────────────────────
    Write-Step "Comprobando git"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Info "Instalando git via winget..."
        winget install --id Git.Git --silent --accept-package-agreements --accept-source-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Success "git instalado."
    } else {
        Write-Success "git ya instalado: $(git --version)"
    }

    # ── 4. Node.js ─────────────────────────────────────────────────────────
    Write-Step "Comprobando Node.js"
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Info "Instalando Node.js LTS via winget..."
        winget install --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Success "Node.js instalado."
    } else {
        Write-Success "Node.js encontrado: $(node --version)"
    }

    # ── 5. Clonar o actualizar repositorios ────────────────────────────────
    # iAgents, backend_fastapi y frontend_react deben quedar como hermanos
    # dentro de InstallDir; gaia.py resuelve esas rutas de forma relativa.
    Write-Step "Repositorios"
    if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }

    function Sync-Repo {
        param($Url, $Dir, $Name)
        if (Test-Path "$Dir\.git") {
            Write-Info "Actualizando $Name..."
            git -C $Dir pull --ff-only
        } else {
            Write-Info "Clonando $Name..."
            git clone $Url $Dir
        }
    }

    Sync-Repo $RepoUrl        "$InstallDir\iAgents"              "iagentshub"
    Sync-Repo $BackendRepoUrl "$InstallDir\backend_fastapi"       "backend"
    Sync-Repo $FrontendReactUrl "$InstallDir\frontend_react"       "frontend React"
    Write-Success "Repositorios listos."

    # ── 6. Configurar .env ──────────────────────────────────────────────────
    if ($FirstInstall) {
        Write-Step "Configuracion inicial"
        Write-Host ""
        $AdminEmail = Read-Host "  Email del administrador [admin@localhost.com]"
        if (-not $AdminEmail) { $AdminEmail = "admin@localhost.com" }
        $Port = Read-Host "  Puerto [8007]"
        if (-not $Port) { $Port = "8007" }

        $Secret = & $PythonExe -c "import secrets; print(secrets.token_hex(32))"
        $DataDir = "$InstallDir\iAgents\data"

        $EnvDir = Split-Path $EnvFile
        if (-not (Test-Path $EnvDir)) { New-Item -ItemType Directory -Path $EnvDir -Force | Out-Null }

        $EnvContent = @"
# iAgents Hub -- configuracion generada el $(Get-Date -Format 'yyyy-MM-dd')
# Edita este fichero y ejecuta: python gaia.py start --local

PORT=$Port
GAIA_PORT=8765
GAIA_FRONTEND_URL=http://localhost:$Port

# Secreto JWT -- generado automaticamente
GAIA_AGENTS_SECRET=$Secret

GAIA_ADMIN_EMAIL=$AdminEmail
# Descomenta para resetear la contrasena del admin en el proximo arranque:
# GAIA_ADMIN_RESET=true

# open | invite | closed
GAIA_REGISTRATION=closed
GAIA_EMAIL_VERIFY=false

# SMTP (opcional)
GAIA_SMTP_HOST=
GAIA_SMTP_PORT=587
GAIA_SMTP_TLS=starttls
GAIA_SMTP_USER=
GAIA_SMTP_PASS=
GAIA_SMTP_FROM=
GAIA_RESET_EXPIRE_HOURS=1

GAIA_MAX_GUEST_SESSIONS=200
GAIA_DATA_DIR=$DataDir

# SQLite por defecto -- para PostgreSQL: postgresql://user:pass@host:5432/db
DATABASE_URL=
"@
        $EnvContent | Out-File -FilePath $EnvFile -Encoding utf8
        Write-Success ".env creado."
    } else {
        Write-Warn ".env existente conservado ($EnvFile)."
    }

    # ── 7. Arrancar ─────────────────────────────────────────────────────────
    Write-Step "Arrancando iAgents Hub"
    Set-Location "$InstallDir\iAgents"
    & $PythonExe gaia.py start --local

    # ── Resumen ──────────────────────────────────────────────────────────────
    $AdminPassFile = "$InstallDir\iAgents\data\.admin_pass"
    $AdminPass = ""
    for ($i = 0; $i -lt 15; $i++) {
        if (Test-Path $AdminPassFile) {
            $AdminPass = (Get-Content $AdminPassFile -Raw).Trim()
            break
        }
        Start-Sleep -Seconds 2
    }

    $PortFinal = "8007"
    $AdminEmailFinal = "admin@localhost.com"
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match "^PORT=") { $PortFinal = $_.Split("=", 2)[1].Trim() }
        if ($_ -match "^GAIA_ADMIN_EMAIL=") { $AdminEmailFinal = $_.Split("=", 2)[1].Trim() }
    }

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Green
    if ($FirstInstall) { Write-Host "║       Instalacion completada             ║" -ForegroundColor Green }
    else { Write-Host "║       Actualizacion completada           ║" -ForegroundColor Green }
    Write-Host "╠══════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "  URL         > http://localhost:$PortFinal" -ForegroundColor Cyan
    Write-Host "  Frontend    > React" -ForegroundColor Cyan
    Write-Host "  Admin       > $AdminEmailFinal" -ForegroundColor Cyan
    if ($AdminPass) {
        Write-Host "  Contrasena  > $AdminPass" -ForegroundColor Green
    } else {
        Write-Host "  Contrasena  > ver: $AdminPassFile" -ForegroundColor Yellow
    }
    Write-Host "  Directorio  > $InstallDir"
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Parar:      cd $InstallDir\iAgents && python gaia.py stop --local" -ForegroundColor Cyan
    Write-Host "  Logs:       cd $InstallDir\iAgents && python gaia.py logs --local" -ForegroundColor Cyan
    Write-Host "  Arrancar:   cd $InstallDir\iAgents && python gaia.py start --local" -ForegroundColor Cyan
    Write-Host "  Actualizar: irm $GithubRaw/install.ps1 | iex" -ForegroundColor Cyan
    Write-Host ""
}

# ── Main ────────────────────────────────────────────────────────────────────
if ($InstallMode -eq "docker") {
    Install-Docker
} else {
    Install-Local
}
