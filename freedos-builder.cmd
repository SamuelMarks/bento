@ECHO OFF
REM ===========================================================================
REM @file freedos-builder.cmd
REM @brief Standalone FreeDOS 1.3 Automated Builder, Runner, Syncer & Vagrant Box Packaging Tool for Bento (Windows .cmd)
REM @description
REM   Windows batch (.cmd) counterpart to freedos-builder.sh. Supports downloading
REM   and verifying FreeDOS 1.3 LiteUSB, injecting the Bento serial/telnet agent
REM   (SERINIT.COM, SERGET.COM, B64ENC.COM, B64DEC.COM, RUNCMD.BAT), booting via
REM   QEMU, syncing D: FAT16 images, and packaging `bento/freedos` Vagrant boxes.
REM ===========================================================================
SETLOCAL EnableDelayedExpansion

SET "SCRIPT_DIR=%~dp0"
IF "%SCRIPT_DIR:~-1%"=="" SET "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
IF "%FREEDOS_SERIAL_PORT%"=="" SET "FREEDOS_SERIAL_PORT=2323"
IF "%FREEDOS_SERIAL_HOST%"=="" SET "FREEDOS_SERIAL_HOST=127.0.0.1"

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
  sh "%SCRIPT_DIR%/freedos-builder.sh" %*
  EXIT /B !ERRORLEVEL!
)

ECHO ==^> [FreeDOS] Running native Windows command handler: %*
IF "%BENTO_DRY_RUN%"=="1" EXIT /B 0
CALL "%SCRIPT_DIR%\packer_templates\scripts\freedos\provision_freedos.cmd"
EXIT /B %ERRORLEVEL%

REM
REM @function usage
REM @description Prints CLI usage help for freedos-builder.cmd.
REM @return 0
REM
:usage
ECHO Usage: freedos-builder.cmd [command] [options]
ECHO Commands: all, fetch, build, box, up, ssh, exec, sync, down, snapshot, status, clean, help
EXIT /B 0
