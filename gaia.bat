@echo off
:: gaia.bat — gestión de iAgents Hub con Docker
:: Uso: gaia.bat <comando>
::
::   start    Arranca los servicios (crea .env si no existe)
::   stop     Detiene los servicios
::   logs     Muestra los logs en tiempo real
::   update   Reconstruye con la última versión del código
::   status   Estado de los contenedores

setlocal enabledelayedexpansion

set "COMPOSE=docker compose"
set "SCRIPT_DIR=%~dp0"

:: ── main ─────────────────────────────────────────────────────────────────────
if "%~1"==""       goto usage
if "%~1"=="start"  goto cmd_start
if "%~1"=="stop"   goto cmd_stop
if "%~1"=="logs"   goto cmd_logs
if "%~1"=="update" goto cmd_update
if "%~1"=="status" goto cmd_status
goto usage

:: ── helpers ───────────────────────────────────────────────────────────────────
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

:ensure_env
  cd /d "%SCRIPT_DIR%"
  if not exist ".env" (
    copy ".env.example" ".env" >nul
    echo [gaia] AVISO: Se ha creado .env a partir de .env.example.
    echo [gaia] AVISO: Edita el fichero .env y cambia las contrasenas antes de continuar.
    echo.
    set /p "RESP=[gaia] Has editado .env y quieres continuar? [s/N] "
    if /i not "!RESP!"=="s" (
      echo [gaia] Operacion cancelada.
      exit /b 0
    )
  )
  exit /b 0

:get_port
  set "PORT=80"
  for /f "tokens=2 delims==" %%A in ('findstr /b "PORT=" ".env" 2^>nul') do set "PORT=%%A"
  exit /b 0

:: ── comandos ──────────────────────────────────────────────────────────────────
:cmd_start
  call :check_docker || exit /b 1
  call :ensure_env   || exit /b 0
  cd /d "%SCRIPT_DIR%"
  echo [gaia] Construyendo e iniciando servicios...
  %COMPOSE% up -d --build
  call :get_port
  echo.
  echo [gaia] iAgents Hub en marcha -^> http://localhost:%PORT%
  goto end

:cmd_stop
  call :check_docker || exit /b 1
  cd /d "%SCRIPT_DIR%"
  echo [gaia] Deteniendo servicios...
  %COMPOSE% down
  echo [gaia] Servicios detenidos.
  goto end

:cmd_logs
  call :check_docker || exit /b 1
  cd /d "%SCRIPT_DIR%"
  echo [gaia] Mostrando logs (Ctrl+C para salir)...
  %COMPOSE% logs -f --tail=100
  goto end

:cmd_update
  call :check_docker || exit /b 1
  call :ensure_env   || exit /b 0
  cd /d "%SCRIPT_DIR%"
  echo [gaia] Actualizando a la ultima version...
  %COMPOSE% down
  %COMPOSE% up -d --build
  call :get_port
  echo.
  echo [gaia] Actualizacion completada -^> http://localhost:%PORT%
  goto end

:cmd_status
  call :check_docker || exit /b 1
  cd /d "%SCRIPT_DIR%"
  %COMPOSE% ps
  goto end

:usage
  echo.
  echo Uso: gaia.bat ^<comando^>
  echo.
  echo   start    Arranca los servicios
  echo   stop     Detiene los servicios
  echo   logs     Muestra los logs en tiempo real
  echo   update   Actualiza a la ultima version y reinicia
  echo   status   Estado de los contenedores
  echo.
  exit /b 1

:end
endlocal
