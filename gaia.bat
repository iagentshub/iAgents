@echo off
:: gaia.bat — gestión de iAgents Hub
:: Uso: gaia.bat <comando> [--dev] [--hub] [--local]
::
::   start    Arranca los servicios
::   stop     Detiene los servicios
::   logs     Muestra los logs en tiempo real
::   update   Actualiza a la última versión y reinicia  (solo Docker)
::   status   Estado de los servicios
::   push     Construye las imágenes y las sube a Docker Hub
::
:: Flags:
::   --dev    Docker con repos locales (../backend, ../frontend) — hot reload
::   --hub    Docker con imágenes pre-construidas de Docker Hub  — despliegue rápido
::   --local  Sin Docker: uvicorn + proxy Python (SQLite, sin PostgreSQL)

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "LOCAL=0"
set "DEV=0"
set "HUB=0"

:: ── Parseo de flags ────────────────────────────────────────────────────────
set "CMD_ARG="
for %%A in (%*) do (
  if /i "%%A"=="--local" (
    set "LOCAL=1"
  ) else if /i "%%A"=="--dev" (
    set "DEV=1"
  ) else if /i "%%A"=="--hub" (
    set "HUB=1"
  ) else (
    if not defined CMD_ARG set "CMD_ARG=%%A"
  )
)
if "%CMD_ARG%"=="" set "CMD_ARG=%~1"

:: Verificar combinaciones incompatibles
if "!DEV!"=="1" if "!LOCAL!"=="1" (
  echo [gaia] ERROR: --dev y --local son incompatibles.
  exit /b 1
)
if "!DEV!"=="1" if "!HUB!"=="1" (
  echo [gaia] ERROR: --dev y --hub son incompatibles.
  exit /b 1
)
if "!LOCAL!"=="1" if "!HUB!"=="1" (
  echo [gaia] ERROR: --local y --hub son incompatibles.
  exit /b 1
)

:: Seleccionar compose según el modo
if "!DEV!"=="1" (
  set "COMPOSE=docker compose -f docker-compose.yml -f docker-compose.dev.yml"
) else if "!HUB!"=="1" (
  set "COMPOSE=docker compose -f docker-compose.hub.yml"
) else (
  set "COMPOSE=docker compose"
)

:: ── Rutas modo local ───────────────────────────────────────────────────────
set "LOCAL_DIR=%SCRIPT_DIR%.gaia-local"
set "BACKEND_PID_FILE=%LOCAL_DIR%\backend.pid"
set "FRONTEND_PID_FILE=%LOCAL_DIR%\frontend.pid"
set "BACKEND_LOG=%LOCAL_DIR%\backend.out.log"
set "BACKEND_ERR=%LOCAL_DIR%\backend.err.log"
set "FRONTEND_LOG=%LOCAL_DIR%\frontend.out.log"
set "FRONTEND_ERR=%LOCAL_DIR%\frontend.err.log"
set "VENV_DIR=%SCRIPT_DIR%.venv"
set "PYTHON=%VENV_DIR%\Scripts\python.exe"
set "PIP=%VENV_DIR%\Scripts\pip.exe"
set "DATA_DIR=%SCRIPT_DIR%data"
set "BACKEND_DIR=%SCRIPT_DIR%..\backend\"

:: ── main ───────────────────────────────────────────────────────────────────
if "!LOCAL!"=="1" (
  if "!CMD_ARG!"==""       goto local_usage
  if "!CMD_ARG!"=="start"  goto local_start
  if "!CMD_ARG!"=="stop"   goto local_stop
  if "!CMD_ARG!"=="logs"   goto local_logs
  if "!CMD_ARG!"=="status" goto local_status
  goto local_usage
) else (
  if "%CMD_ARG%"==""       goto usage
  if "%CMD_ARG%"=="start"  goto cmd_start
  if "%CMD_ARG%"=="stop"   goto cmd_stop
  if "%CMD_ARG%"=="logs"   goto cmd_logs
  if "%CMD_ARG%"=="update" goto cmd_update
  if "%CMD_ARG%"=="status" goto cmd_status
  if "%CMD_ARG%"=="push"   goto cmd_push
  goto usage
)

:: ══════════════════════════════════════════════════════════════════════════════
:: MODO LOCAL (sin Docker)
:: ══════════════════════════════════════════════════════════════════════════════

:local_start
  call :check_python || exit /b 1

  :: Comprobar si ya hay servicios corriendo
  set "_RUNNING=0"
  if exist "!BACKEND_PID_FILE!" (
    set /p _BPID=<"!BACKEND_PID_FILE!"
    tasklist /FI "PID eq !_BPID!" 2>nul | find /i "python" >nul 2>&1 && set "_RUNNING=1"
  )
  if exist "!FRONTEND_PID_FILE!" (
    set /p _FPID=<"!FRONTEND_PID_FILE!"
    tasklist /FI "PID eq !_FPID!" 2>nul | find /i "python" >nul 2>&1 && set "_RUNNING=1"
  )
  if "!_RUNNING!"=="1" (
    echo [gaia] AVISO: Los servicios locales ya estan en ejecucion.
    goto local_status
  )

  if not exist "!LOCAL_DIR!" mkdir "!LOCAL_DIR!"

  call :ensure_venv    || exit /b 1
  call :init_local_data

  :: Leer configuracion desde .env (con valores por defecto)
  set "PORT=8007"
  set "GAIA_PORT=8765"
  set "GAIA_ADMIN_EMAIL=admin@localhost"
  set "GAIA_ADMIN_RESET="
  set "GAIA_AGENTS_SECRET="
  set "GAIA_REGISTRATION=open"
  set "GAIA_CORS_ORIGINS="

  if exist "%SCRIPT_DIR%.env" (
    for /f "usebackq tokens=1,* delims==" %%K in ("%SCRIPT_DIR%.env") do (
      if "%%K"=="PORT"               set "PORT=%%L"
      if "%%K"=="GAIA_PORT"          set "GAIA_PORT=%%L"
      if "%%K"=="GAIA_ADMIN_EMAIL"   set "GAIA_ADMIN_EMAIL=%%L"
      if "%%K"=="GAIA_ADMIN_RESET"   set "GAIA_ADMIN_RESET=%%L"
      if "%%K"=="GAIA_AGENTS_SECRET" set "GAIA_AGENTS_SECRET=%%L"
      if "%%K"=="GAIA_REGISTRATION"  set "GAIA_REGISTRATION=%%L"
      if "%%K"=="GAIA_CORS_ORIGINS"  set "GAIA_CORS_ORIGINS=%%L"
    )
  )
  :: En modo local, evitar puertos privilegiados (< 1024)
  if !PORT! LSS 1024 (
    echo [gaia] AVISO: PORT=!PORT! puede requerir privilegios. Usando 8007 para modo local.
    echo [gaia] AVISO: Añade PORT=8007 en .env para evitar este aviso.
    set "PORT=8007"
  )
  if "!GAIA_CORS_ORIGINS!"=="" set "GAIA_CORS_ORIGINS=http://localhost:!PORT!"

  :: Preparar variables de entorno para el backend
  set "GAIA_DATA_DIR=!DATA_DIR!"
  set "GAIA_HOST=127.0.0.1"
  set "GAIA_RELOAD=false"
  set "GAIA_EMAIL_VERIFY=false"
  set "GAIA_SMTP_HOST="
  set "DATABASE_URL="

  :: ── Arrancar backend usando PowerShell (captura PID) ─────────────────────
  echo [gaia] Arrancando backend en puerto !GAIA_PORT! ...

  :: Escribir script PowerShell temporal para el backend
  (
    echo $env:GAIA_DATA_DIR    = '!DATA_DIR!'
    echo $env:GAIA_HOST        = '127.0.0.1'
    echo $env:GAIA_PORT        = '!GAIA_PORT!'
    echo $env:GAIA_RELOAD      = 'false'
    echo $env:GAIA_REGISTRATION= '!GAIA_REGISTRATION!'
    echo $env:GAIA_ADMIN_EMAIL = '!GAIA_ADMIN_EMAIL!'
    echo $env:GAIA_ADMIN_RESET = '!GAIA_ADMIN_RESET!'
    echo $env:GAIA_AGENTS_SECRET='!GAIA_AGENTS_SECRET!'
    echo $env:GAIA_CORS_ORIGINS= '!GAIA_CORS_ORIGINS!'
    echo $env:GAIA_EMAIL_VERIFY= 'false'
    echo $env:GAIA_SMTP_HOST   = ''
    echo $env:DATABASE_URL     = ''
    echo $p = Start-Process -FilePath '!PYTHON!' -ArgumentList 'main.py' -WorkingDirectory '!BACKEND_DIR!' -RedirectStandardOutput '!BACKEND_LOG!' -RedirectStandardError '!BACKEND_ERR!' -NoNewWindow -PassThru
    echo $p.Id ^| Set-Content '!BACKEND_PID_FILE!'
  ) > "!LOCAL_DIR!\start_backend.ps1"

  powershell -NoProfile -ExecutionPolicy Bypass -File "!LOCAL_DIR!\start_backend.ps1"
  del "!LOCAL_DIR!\start_backend.ps1" >nul 2>&1

  :: ── Arrancar frontend proxy usando PowerShell ────────────────────────────
  echo [gaia] Arrancando frontend proxy en puerto !PORT! ...

  (
    echo $env:PORT      = '!PORT!'
    echo $env:GAIA_PORT = '!GAIA_PORT!'
    echo $p = Start-Process -FilePath '!PYTHON!' -ArgumentList '"!SCRIPT_DIR!local_proxy.py"' -RedirectStandardOutput '!FRONTEND_LOG!' -RedirectStandardError '!FRONTEND_ERR!' -NoNewWindow -PassThru
    echo $p.Id ^| Set-Content '!FRONTEND_PID_FILE!'
  ) > "!LOCAL_DIR!\start_frontend.ps1"

  powershell -NoProfile -ExecutionPolicy Bypass -File "!LOCAL_DIR!\start_frontend.ps1"
  del "!LOCAL_DIR!\start_frontend.ps1" >nul 2>&1

  echo.
  echo [gaia] Servicios locales arrancados.
  echo.
  echo   +------------------------------------------+
  echo   ^|       Modo local (sin Docker)            ^|
  echo   +------------------------------------------+
  echo   ^|  Frontend   -^> http://localhost:!PORT!
  echo   ^|  Backend    -^> http://localhost:!GAIA_PORT!
  echo   ^|  Admin      -^> !GAIA_ADMIN_EMAIL!
  if exist "!DATA_DIR!\.admin_pass" (
    set /p _APASS=<"!DATA_DIR!\.admin_pass"
    echo   ^|  Contrasena -^> !_APASS!
  ) else (
    echo   ^|  Contrasena -^> (ver logs: gaia.bat logs --local)
  )
  echo   ^|  Base datos -^> SQLite en .\data\hub.db
  echo   +------------------------------------------+
  echo.
  echo [gaia] Logs -^> gaia.bat logs --local   Detener -^> gaia.bat stop --local
  goto end

:local_stop
  set "_STOPPED=0"
  call :kill_pid "!BACKEND_PID_FILE!"  && (echo [gaia] Backend detenido.  & set "_STOPPED=1")
  call :kill_pid "!FRONTEND_PID_FILE!" && (echo [gaia] Frontend detenido. & set "_STOPPED=1")
  if "!_STOPPED!"=="1" (
    echo [gaia] Servicios locales detenidos.
  ) else (
    echo [gaia] No habia servicios locales en ejecucion.
  )
  goto end

:local_status
  echo.
  call :show_pid_status "backend"  "!BACKEND_PID_FILE!"
  call :show_pid_status "frontend" "!FRONTEND_PID_FILE!"
  echo.
  goto end

:local_logs
  if not exist "!LOCAL_DIR!" mkdir "!LOCAL_DIR!"
  if not exist "!BACKEND_LOG!"  type nul > "!BACKEND_LOG!"
  if not exist "!BACKEND_ERR!"  type nul > "!BACKEND_ERR!"
  if not exist "!FRONTEND_LOG!" type nul > "!FRONTEND_LOG!"
  if not exist "!FRONTEND_ERR!" type nul > "!FRONTEND_ERR!"
  echo [gaia] Mostrando logs (Ctrl+C para salir)...
  powershell -NoProfile -Command "Get-Content -Wait -Path '!BACKEND_LOG!','!BACKEND_ERR!','!FRONTEND_LOG!','!FRONTEND_ERR!'"
  goto end

:local_usage
  echo.
  echo Uso: gaia.bat ^<comando^> --local
  echo.
  echo   start    Arranca backend (uvicorn) y frontend (proxy Python) sin Docker
  echo   stop     Detiene los servicios locales
  echo   logs     Muestra los logs en tiempo real
  echo   status   Estado de los procesos locales
  echo.
  echo   Base de datos: SQLite en .\data\hub.db  (con persistencia)
  echo   Sin PostgreSQL ni contenedores Docker.
  echo.
  exit /b 1

:: ══════════════════════════════════════════════════════════════════════════════
:: MODO DOCKER
:: ══════════════════════════════════════════════════════════════════════════════

:cmd_start
  call :check_docker || exit /b 1
  call :ensure_env   || exit /b 0
  cd /d "%SCRIPT_DIR%"
  if "!DEV!"=="1" echo [gaia] Modo desarrollo -- usando repos locales
  if "!HUB!"=="1" echo [gaia] Modo Hub -- usando imagenes de Docker Hub
  if "!HUB!"=="1" (
    echo [gaia] Descargando imagenes actualizadas...
    !COMPOSE! pull
    !COMPOSE! rm -f data-init 2>nul
    !COMPOSE! up -d
  ) else (
    echo [gaia] Construyendo e iniciando servicios...
    !COMPOSE! rm -f data-init 2>nul
    !COMPOSE! up -d --build
  )
  call :get_port
  echo.
  echo [gaia] iAgents Hub en marcha -^> http://localhost:!PORT!
  call :show_admin_info
  goto end

:cmd_stop
  call :check_docker || exit /b 1
  cd /d "%SCRIPT_DIR%"
  echo [gaia] Deteniendo servicios...
  !COMPOSE! down
  echo [gaia] Servicios detenidos.
  goto end

:cmd_logs
  call :check_docker || exit /b 1
  cd /d "%SCRIPT_DIR%"
  echo [gaia] Mostrando logs (Ctrl+C para salir)...
  !COMPOSE! logs -f --tail=100
  goto end

:cmd_update
  call :check_docker || exit /b 1
  call :ensure_env   || exit /b 0
  cd /d "%SCRIPT_DIR%"
  if "!DEV!"=="1" echo [gaia] Modo desarrollo -- usando repos locales
  if "!HUB!"=="1" echo [gaia] Modo Hub -- descargando imagenes actualizadas de Docker Hub
  echo [gaia] Actualizando a la ultima version...
  !COMPOSE! rm -f data-init 2>nul
  !COMPOSE! down
  if "!HUB!"=="1" (
    !COMPOSE! pull
    !COMPOSE! up -d
  ) else (
    !COMPOSE! up -d --build
  )
  call :get_port
  echo.
  echo [gaia] Actualizacion completada -^> http://localhost:!PORT!
  call :show_admin_info
  goto end

:cmd_status
  call :check_docker || exit /b 1
  cd /d "%SCRIPT_DIR%"
  !COMPOSE! ps
  goto end

:cmd_push
  call :check_docker || exit /b 1
  call :ensure_env   || exit /b 0
  cd /d "%SCRIPT_DIR%"

  :: Leer DOCKER_HUB_USER e IMAGE_TAG del .env
  set "HUB_USER=iagenthub"
  set "IMG_TAG=latest"
  if exist ".env" (
    for /f "usebackq tokens=1,* delims==" %%K in (".env") do (
      if "%%K"=="DOCKER_HUB_USER" set "HUB_USER=%%L"
      if "%%K"=="IMAGE_TAG"       set "IMG_TAG=%%L"
    )
  )
  set "UNIFIED_IMG=!HUB_USER!/iagentshub:!IMG_TAG!"
  set "BE_PATH=%SCRIPT_DIR%..\backend"
  set "FE_PATH=%SCRIPT_DIR%..\frontend"

  :: Preparar contexto de build en directorio temporal
  set "TMPDIR=%TEMP%\iagentshub_build_%RANDOM%"
  mkdir "!TMPDIR!" || (echo [gaia] ERROR: No se pudo crear directorio temporal. & exit /b 1)

  echo [gaia] Preparando contexto de build...
  xcopy /E /I /Q "!BE_PATH!" "!TMPDIR!\backend\" >nul
  if !errorlevel! neq 0 (echo [gaia] ERROR: Fallo al copiar backend. & rd /s /q "!TMPDIR!" & exit /b 1)
  xcopy /E /I /Q "!FE_PATH!" "!TMPDIR!\frontend\" >nul
  if !errorlevel! neq 0 (echo [gaia] ERROR: Fallo al copiar frontend. & rd /s /q "!TMPDIR!" & exit /b 1)
  copy "%SCRIPT_DIR%Dockerfile.unified"    "!TMPDIR!\Dockerfile"         >nul
  copy "%SCRIPT_DIR%supervisord.conf"      "!TMPDIR!\supervisord.conf"   >nul
  copy "%SCRIPT_DIR%entrypoint-unified.sh" "!TMPDIR!\entrypoint-unified.sh" >nul

  :: Usar buildx para imagen multi-plataforma (amd64 + arm64)
  docker buildx inspect multiarch >nul 2>&1
  if !errorlevel! neq 0 (
    echo [gaia] Creando builder multi-plataforma...
    docker buildx create --name multiarch --driver docker-container --use
    docker buildx inspect --bootstrap
  ) else (
    docker buildx use multiarch
  )

  echo [gaia] Construyendo imagen multi-plataforma (linux/amd64, linux/arm64) -^> !UNIFIED_IMG!
  echo [gaia] Esto tarda unos minutos la primera vez...
  docker buildx build --platform linux/amd64,linux/arm64 --push -t "!UNIFIED_IMG!" "!TMPDIR!"
  set "_BUILD_ERR=!errorlevel!"
  rd /s /q "!TMPDIR!" >nul 2>&1
  if !_BUILD_ERR! neq 0 (
    echo [gaia] ERROR: Fallo al construir la imagen multi-plataforma.
    exit /b 1
  )

  echo.
  echo [gaia] Imagen publicada en Docker Hub:
  echo   * !UNIFIED_IMG!
  echo [gaia] Para desplegar: gaia.bat start --hub  ^(en cualquier servidor con Docker^)
  echo [gaia] Instalacion directa: curl -fsSL https://raw.githubusercontent.com/iagentshub/iagentshub/main/install.sh ^| bash
  goto end

:: ══════════════════════════════════════════════════════════════════════════════
:: HELPERS COMPARTIDOS
:: ══════════════════════════════════════════════════════════════════════════════

:check_docker
  where docker >nul 2>&1 || (
    echo [gaia] ERROR: Docker no esta instalado. Descargalo en https://docs.docker.com/get-docker/
    exit /b 1
  )
  docker info >nul 2>&1 || (
    echo [gaia] ERROR: Docker no esta en ejecucion. Arrancalo e intentalo de nuevo.
    exit /b 1
  )
  exit /b 0

:check_python
  where python >nul 2>&1 || (
    echo [gaia] ERROR: Python no esta instalado. Descargalo en https://python.org
    exit /b 1
  )
  python -c "import sys; sys.exit(0 if sys.version_info>=(3,8) else 1)" >nul 2>&1 || (
    echo [gaia] ERROR: Se requiere Python 3.8 o superior.
    exit /b 1
  )
  exit /b 0

:ensure_env
  cd /d "%SCRIPT_DIR%"

  :: Generar valores aleatorios via PowerShell (disponible en Windows 10/11)
  for /f "usebackq delims=" %%R in (`powershell -NoProfile -Command "$b=New-Object byte[] 32;[System.Security.Cryptography.RandomNumberGenerator]::Fill($b);[BitConverter]::ToString($b).Replace('-','').ToLower()"`) do set "_RAND_AGENTS=%%R"
  for /f "usebackq delims=" %%R in (`powershell -NoProfile -Command "$b=New-Object byte[] 32;[System.Security.Cryptography.RandomNumberGenerator]::Fill($b);[BitConverter]::ToString($b).Replace('-','').ToLower()"`) do set "_RAND_DB=%%R"

  if not exist ".env" (
    copy ".env.example" ".env" >nul
    powershell -NoProfile -Command "(Get-Content '.env') -replace '^GAIA_AGENTS_SECRET=.*', 'GAIA_AGENTS_SECRET=!_RAND_AGENTS!' | Set-Content '.env'"
    powershell -NoProfile -Command "(Get-Content '.env') -replace '^GAIA_DB_PASSWORD=.*', 'GAIA_DB_PASSWORD=!_RAND_DB!' | Set-Content '.env'"
    echo [gaia] AVISO: Se ha creado .env con secrets aleatorios.
    echo [gaia] AVISO: Revisa GAIA_FRONTEND_URL y GAIA_ADMIN_EMAIL si vas a desplegar en produccion.
    echo.
    exit /b 0
  )

  :: .env ya existe: actualizar GAIA_DB_PASSWORD si esta vacio o es debil
  set "_CUR_PASS="
  for /f "usebackq tokens=1,* delims==" %%K in (".env") do (
    if "%%K"=="GAIA_DB_PASSWORD" set "_CUR_PASS=%%L"
  )
  set "_NEED_PW_UPDATE=0"
  if "!_CUR_PASS!"=="" set "_NEED_PW_UPDATE=1"
  if /i "!_CUR_PASS!"=="changeme" set "_NEED_PW_UPDATE=1"
  if "!_NEED_PW_UPDATE!"=="1" (
    powershell -NoProfile -Command "(Get-Content '.env') -replace '^GAIA_DB_PASSWORD=.*', 'GAIA_DB_PASSWORD=!_RAND_DB!' | Set-Content '.env'"
    echo [gaia] GAIA_DB_PASSWORD actualizado con valor aleatorio en .env
  )
  exit /b 0

:ensure_venv
  if not exist "!BACKEND_DIR!requirements.txt" (
    echo [gaia] ERROR: No se encontro requirements.txt en ..\backend\
    exit /b 1
  )
  if not exist "!VENV_DIR!" (
    echo [gaia] Creando entorno virtual en .venv\ ...
    python -m venv "!VENV_DIR!"
  )
  echo [gaia] Verificando dependencias Python...
  "!PIP!" install -q --upgrade pip
  "!PIP!" install -q -r "!BACKEND_DIR!requirements.txt"
  exit /b 0

:init_local_data
  :: Solo garantizar que data\ existe; toda la informacion esta en hub.db.
  if not exist "!DATA_DIR!" mkdir "!DATA_DIR!"

  if not exist "!DATA_DIR!\settings.json" (
    for /f %%S in ('python -c "import secrets; print(secrets.token_hex(32))"') do set "_SECRET=%%S"
    echo {"jwt_secret": "!_SECRET!"} > "!DATA_DIR!\settings.json"
    echo [gaia] settings.json creado con secret aleatorio.
  )

  echo [gaia] Directorio de datos listo: .\data\
  exit /b 0

:kill_pid
  set "_PF=%~1"
  if not exist "!_PF!" exit /b 1
  set /p _PID=<"!_PF!"
  taskkill /PID !_PID! /T /F >nul 2>&1
  del "!_PF!" >nul 2>&1
  exit /b 0

:show_pid_status
  set "_SVC=%~1"
  set "_PF=%~2"
  if exist "!_PF!" (
    set /p _PID=<"!_PF!"
    tasklist /FI "PID eq !_PID!" 2>nul | find /i "python" >nul 2>&1
    if !errorlevel! equ 0 (
      echo   [RUNNING] !_SVC! (PID !_PID!)
    ) else (
      echo   [STOPPED] !_SVC! (PID !_PID! obsoleto)
      del "!_PF!" >nul 2>&1
    )
  ) else (
    echo   [STOPPED] !_SVC! - no iniciado
  )
  exit /b 0

:get_port
  set "PORT=80"
  for /f "usebackq tokens=2 delims==" %%A in (`findstr /b "PORT=" ".env" 2^>nul`) do set "PORT=%%A"
  exit /b 0

:show_admin_info
  set "SAI_EMAIL="
  set "SAI_PASS="
  set "SAI_TRIES=0"
  :_sai_wait
  !COMPOSE! exec -T backend sh -c "exit 0" >nul 2>&1
  if !errorlevel! equ 0 goto _sai_get
  if !SAI_TRIES! geq 30 goto _sai_print
  timeout /t 1 /nobreak >nul
  set /a SAI_TRIES+=1
  goto _sai_wait

  :_sai_get
  for /f "usebackq delims=" %%E in (`!COMPOSE! exec -T backend sh -c "echo $GAIA_ADMIN_EMAIL" 2^>nul`) do (
    if not defined SAI_EMAIL set "SAI_EMAIL=%%E"
  )
  for /f "usebackq delims=" %%P in (`!COMPOSE! exec -T backend sh -c "cat $GAIA_DATA_DIR/.admin_pass 2>/dev/null" 2^>nul`) do set "SAI_PASS=%%P"

  :_sai_print
  call :get_port
  echo.
  echo   +------------------------------------------+
  echo   ^|      Acceso de administrador             ^|
  echo   +------------------------------------------+
  echo   ^|  Frontend   -^> http://localhost:!PORT!
  echo   ^|  Backend    -^> http://localhost:!GAIA_PORT!
  if defined SAI_EMAIL (
    echo   ^|  Email      : !SAI_EMAIL!
  ) else (
    echo   ^|  Email      : (no disponible)
  )
  if defined SAI_PASS (
    echo   ^|  Contrasena : !SAI_PASS!
  ) else (
    echo   ^|  Contrasena : (sin cambios)
  )
  echo   +------------------------------------------+
  echo.
  exit /b 0

:usage
  echo.
  echo Uso: gaia.bat ^<comando^> [--dev] [--hub] [--local]
  echo.
  echo   start    Arranca los servicios
  echo   stop     Detiene los servicios
  echo   logs     Muestra los logs en tiempo real
  echo   update   Actualiza a la ultima version y reinicia
  echo   status   Estado de los contenedores
  echo   push     Construye imagenes y las sube a Docker Hub
  echo.
  echo Flags:
  echo   --dev    Usa repos locales (../backend, ../frontend) con hot reload
  echo   --hub    Usa imagenes pre-construidas de Docker Hub (despliegue rapido)
  echo   --local  Sin Docker: uvicorn + proxy Python (SQLite, sin PostgreSQL)
  echo.
  echo Flujo recomendado para despliegues rapidos (--hub):
  echo   1. En tu PC:      gaia.bat push              (construye y sube imagenes)
  echo   2. En el servidor: gaia.bat start --hub      (descarga y arranca)
  echo   3. Para actualizar: gaia.bat update --hub    (pull + reinicio)
  echo.
  exit /b 1

:end
endlocal
