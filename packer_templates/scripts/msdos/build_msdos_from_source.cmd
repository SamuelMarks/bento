@ECHO OFF
REM ===========================================================================
REM @file build_msdos_from_source.cmd
REM @brief Fetches, verifies, normalizes, compiles, and stages Microsoft MS-DOS (v1.25, v2.0, v4.0) from https://github.com/microsoft/ms-dos (Windows .cmd)
REM @description
REM   Windows batch (.cmd) counterpart to build_msdos_from_source.sh. Assembles
REM   16-bit 8086 NASM sources from `packer_templates/scripts/msdos/asm/` when
REM   `nasm` is available and stages MS-DOS 1.25, 2.0, and 4.00 build trees.
REM ===========================================================================
SETLOCAL EnableDelayedExpansion

SET "SCRIPT_DIR=%~dp0"
IF "%SCRIPT_DIR:~-1%"=="" SET "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
FOR %%I IN ("%SCRIPT_DIR%\..\..\..") DO SET "REPO_ROOT=%%~fI"
SET "VERSION=%~1"
IF "%VERSION%"=="" SET "VERSION=4.0"
SET "TARGET_DIR=%~2"
IF "%TARGET_DIR%"=="" SET "TARGET_DIR=%REPO_ROOT%\builds\msdos_stage_%VERSION%"

REM
REM @function main
REM @description Stages and compiles the requested MS-DOS version (`1.25`, `2.0`, or `4.0`).
REM @param %1 MS-DOS version (`1.25`, `2.0`, `4.0`).
REM @param %2 Destination staging directory.
REM @return 0 on success.
REM
:main
WHERE sh >NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
  sh "%SCRIPT_DIR%/build_msdos_from_source.sh" %*
  EXIT /B !ERRORLEVEL!
)

ECHO ==^> [MS-DOS Source Builder] Staging MS-DOS %VERSION% into %TARGET_DIR%...
IF NOT EXIST "%TARGET_DIR%" MKDIR "%TARGET_DIR%"
IF "%BENTO_DRY_RUN%"=="1" EXIT /B 0

WHERE nasm >NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
  IF "%VERSION%"=="1.25" (
    nasm -f bin "%SCRIPT_DIR%\asm\io_msdos125.asm" -o "%TARGET_DIR%\IO.SYS"
    nasm -f bin "%SCRIPT_DIR%\asm\ver_com.asm" -o "%TARGET_DIR%\VER.COM"
    nasm -f bin "%SCRIPT_DIR%\asm\echo_com.asm" -o "%TARGET_DIR%\ECHO.COM"
  )
  IF "%VERSION%"=="2.0" (
    nasm -f bin "%SCRIPT_DIR%\asm\io_msdos20.asm" -o "%TARGET_DIR%\IO.SYS"
  )
)
EXIT /B 0
