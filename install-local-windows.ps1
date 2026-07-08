# install-local-windows.ps1 — Instala iAgents Hub en Windows SIN Docker
#
# Uso (PowerShell como Administrador):
#   irm https://raw.githubusercontent.com/iagentshub/iagentshub/main/install-local-windows.ps1 | iex
#
# Requisitos: Windows 10/11 con PowerShell 5.1+ y winget disponible.
# Base de datos: SQLite (sin configuracion adicional).
# Para PostgreSQL o produccion real usa el instalador Docker (install.sh en WSL2).

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Colores ───────────────────────────────────────────────────────────────────
function Write-Info    { param($m) Write-Host "[iagentshub] $m" -ForegroundColor Cyan }
function Write-Success { param($m) Write-Host "[iagentshub] $m" -ForegroundColor Green }
function Write-Warn    { param($m) Write-Host "[iagentshub] $m" -ForegroundColor Yellow }
function Write-Fail    { param($m) Write-Error "[iagentshub] $m" }
function Write-Step    { param($m) Write-Host "`n── $m ──────────────────────────────────────" -ForegroundColor White }

$RepoUrl         = "https://github.com/iagentshub/iagentshub.git"
$BackendRepoUrl  = "https://github.com/iagentshub/backend.git"
$FrontendRepoUrl = "https://github.com/iagentshub/frontend.git"
$GithubRaw  = "https://raw.githubusercontent.com/iagentshub/iagentshub/main"
$InstallDir = if ($env:IAGENTSHUB_DIR) { $env:IAGENTSHUB_DIR } else { "$env:USERPROFILE\iagentshub" }
$EnvFile    = "$InstallDir\iagentshub\.env"

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor White
Write-Host "║   iAgents Hub · Instalacion Windows     ║" -ForegroundColor White
Write-Host "║   Sin Docker · SQLite                    ║" -ForegroundColor White
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor White
Write-Host ""

$FirstInstall = -not (Test-Path $EnvFile)

# ── 1. winget ─────────────────────────────────────────────────────────────────
Write-Step "Comprobando winget"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warn "winget no encontrado. Instala 'App Installer' desde Microsoft Store."
    Write-Warn "O instala Python y git manualmente desde https://python.org y https://git-scm.com"
    Write-Fail "winget es necesario para la instalacion automatica."
}
Write-Success "winget disponible."

# ── 2. Python >= 3.11 ─────────────────────────────────────────────────────────
Write-Step "Comprobando Python 3.11+"
$PythonExe = $null

# Buscar Python existente >= 3.11
foreach ($candidate in @("python3.13","python3.12","python3.11","python3","python")) {
    $found = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($found) {
        $ver = & $candidate -c "import sys; print(sys.version_info >= (3,11))" 2>$null
        if ($ver -eq "True") {
            $PythonExe = $candidate
            break
        }
    }
}

if (-not $PythonExe) {
    Write-Info "Instalando Python 3.11 via winget..."
    winget install --id Python.Python.3.11 --silent --accept-package-agreements --accept-source-agreements
    # Refrescar PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    $PythonExe = "python"
    Write-Success "Python instalado."
} else {
    $pyVer = & $PythonExe --version 2>&1
    Write-Success "Python encontrado: $pyVer"
}

# ── 3. Git ────────────────────────────────────────────────────────────────────
Write-Step "Comprobando git"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Info "Instalando git via winget..."
    winget install --id Git.Git --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Success "git instalado."
} else {
    Write-Success "git ya instalado: $(git --version)"
}

# ── 4. Clonar o actualizar repositorios ────────────────────────────────────────
# iagentshub/backend/frontend son repos separados que deben quedar como
# hermanos dentro de InstallDir — gaia.bat (dentro de iagentshub\) resuelve
# ..\backend y ..\frontend de forma relativa, y espera este layout exacto.
Write-Step "Repositorios"
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

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

Sync-Repo $RepoUrl         "$InstallDir\iagentshub" "iagentshub"
Sync-Repo $BackendRepoUrl  "$InstallDir\backend"    "backend"
Sync-Repo $FrontendRepoUrl "$InstallDir\frontend"   "frontend"
Write-Success "Repositorios listos."

# El entorno virtual y las dependencias de Python los gestiona gaia.bat por su
# cuenta (ensure_venv, en $InstallDir\iagentshub\.venv) al arrancar en el
# paso 7 — no lo dupliques aqui.

# ── 6. Configurar .env ────────────────────────────────────────────────────────
if ($FirstInstall) {
    Write-Step "Configuracion inicial"
    Write-Host ""

    $AdminEmail = Read-Host "  Email del administrador [admin@localhost]"
    if (-not $AdminEmail) { $AdminEmail = "admin@localhost" }

    $Port = Read-Host "  Puerto [8007]"
    if (-not $Port) { $Port = "8007" }

    $Secret = & $PythonExe -c "import secrets; print(secrets.token_hex(32))"
    $DataDir = "$InstallDir\iagentshub\data"

    $EnvDir = Split-Path $EnvFile
    if (-not (Test-Path $EnvDir)) { New-Item -ItemType Directory -Path $EnvDir -Force | Out-Null }

    $EnvContent = @"
# iAgents Hub -- configuracion generada el $(Get-Date -Format 'yyyy-MM-dd')
# Edita este fichero y ejecuta: .\gaia.bat start --local

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

# ── 7. Arrancar ───────────────────────────────────────────────────────────────
Write-Step "Arrancando iAgents Hub"
Set-Location "$InstallDir\iagentshub"
& cmd /c "gaia.bat start --local"

# ── Leer contrasena admin ─────────────────────────────────────────────────────
$AdminPassFile = "$InstallDir\iagentshub\data\.admin_pass"
$AdminPass = ""
for ($i = 0; $i -lt 15; $i++) {
    if (Test-Path $AdminPassFile) {
        $AdminPass = Get-Content $AdminPassFile -Raw
        $AdminPass = $AdminPass.Trim()
        break
    }
    Start-Sleep -Seconds 2
}

# Leer puerto del .env
$PortFinal = "8007"
Get-Content $EnvFile | Where-Object { $_ -match "^PORT=" } | ForEach-Object {
    $PortFinal = $_.Split("=")[1].Trim()
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Green
if ($FirstInstall) {
    Write-Host "║       Instalacion completada             ║" -ForegroundColor Green
} else {
    Write-Host "║       Actualizacion completada           ║" -ForegroundColor Green
}
Write-Host "╠══════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "  URL         > http://localhost:$PortFinal" -ForegroundColor Cyan
Write-Host "  Admin       > $AdminEmail" -ForegroundColor Cyan
if ($AdminPass) {
    Write-Host "  Contrasena  > $AdminPass" -ForegroundColor Green
} else {
    Write-Host "  Contrasena  > ver: $AdminPassFile" -ForegroundColor Yellow
}
Write-Host "  Directorio  > $InstallDir"
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Parar:      cd $InstallDir\iagentshub && gaia.bat stop --local" -ForegroundColor Cyan
Write-Host "  Logs:       cd $InstallDir\iagentshub && gaia.bat logs --local" -ForegroundColor Cyan
Write-Host "  Arrancar:   cd $InstallDir\iagentshub && gaia.bat start --local" -ForegroundColor Cyan
Write-Host "  Actualizar: irm $GithubRaw/install-local-windows.ps1 | iex" -ForegroundColor Cyan
Write-Host ""
