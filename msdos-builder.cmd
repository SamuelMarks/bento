@ECHO OFF
REM ===========================================================================
REM @file msdos-builder.cmd
REM @brief Standalone Microsoft MS-DOS (1.25, 2.0, 4.0) Automated Builder, Runner, Syncer & Vagrant Box Packaging Tool for Bento (Windows .cmd)
REM @description
REM   Windows batch (.cmd) counterpart to msdos-builder.sh. Supports building,
REM   booting, connecting over Telnet/COM1, syncing host folders into a FAT16
REM   D: drive, and packaging Vagrant boxes (`bento/msdos-1.25`, `bento/msdos-2.0`,
REM   `bento/msdos-4.0`). Delegates to POSIX `sh` when available (Git Bash / MSYS2 /
REM   WSL) or executes native Windows QEMU / Ruby / Packer workflows.
REM ===========================================================================
SETLOCAL EnableDelayedExpansion

SET "SCRIPT_DIR=%~dp0"
IF "%SCRIPT_DIR:~-1%"=="" SET "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
IF "%MSDOS_VERSION%"=="" SET "MSDOS_VERSION=4.0"
IF "%MSDOS_SERIAL_PORT%"=="" SET "MSDOS_SERIAL_PORT=2323"
IF "%MSDOS_SERIAL_HOST%"=="" SET "MSDOS_SERIAL_HOST=127.0.0.1"

REM
REM @function main
REM @description Entry point dispatching subcommands (all, fetch, build, box, up, ssh, exec, sync, down, snapshot, status, clean, help).
REM @param %* Command-line arguments.
REM @return 0 on success, non-zero on error.
REM
:main
IF "%~1"=="" GOTO :delegate_or_run
IF /I "%~1"=="help" GOTO :usage
IF /I "%~1"=="--help" GOTO :usage
IF /I "%~1"=="-h" GOTO :usage

:delegate_or_run
WHERE sh >NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
  sh "%SCRIPT_DIR%/msdos-builder.sh" %*
  EXIT /B !ERRORLEVEL!
)

ECHO ==^> [MS-DOS %MSDOS_VERSION%] Running native Windows command handler: %*
IF "%BENTO_DRY_RUN%"=="1" EXIT /B 0
CALL "%SCRIPT_DIR%\packer_templates\scripts\msdos\build_msdos_from_source.cmd" "%MSDOS_VERSION%"
EXIT /B %ERRORLEVEL%

REM
REM @function usage
REM @description Prints CLI usage help for msdos-builder.cmd.
REM @return 0
REM
:usage
ECHO Usage: msdos-builder.cmd [--version 1.25^|2.0^|4.0] [command] [options]
ECHO Commands: all, fetch, build, box, up, ssh, exec, sync, down, snapshot, status, clean, help
EXIT /B 0
