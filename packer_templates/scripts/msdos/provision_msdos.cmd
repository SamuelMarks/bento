@ECHO OFF
REM ===========================================================================
REM @file provision_msdos.cmd
REM @brief Host-side Packer provisioner script for standalone Microsoft MS-DOS (1.25, 2.0, 4.0) images (Windows .cmd)
REM @description
REM   Windows batch (.cmd) counterpart to provision_msdos.sh. Generates the 16-bit
REM   8086 real-mode .COM utilities (B64DEC.COM, B64ENC.COM, SERINIT.COM,
REM   SHUTDOWN.COM, SERGET.COM) from `packer_templates/scripts/msdos/asm/` (or
REM   via POSIX `sh` / Ruby) and provisions the live MS-DOS guest over COM1.
REM ===========================================================================
SETLOCAL EnableDelayedExpansion

SET "SCRIPT_DIR=%~dp0"
IF "%SCRIPT_DIR:~-1%"=="" SET "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM
REM @function main
REM @description Generates 16-bit .COM utilities and provisions the MS-DOS guest.
REM @param %* Command-line arguments.
REM @return 0 on success.
REM
:main
WHERE sh >NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
  sh "%SCRIPT_DIR%/provision_msdos.sh" %*
  EXIT /B !ERRORLEVEL!
)

WHERE nasm >NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
  nasm -f bin "%SCRIPT_DIR%\asm\b64enc_com.asm" -o "%SCRIPT_DIR%\B64ENC.COM"
  nasm -f bin "%SCRIPT_DIR%\asm\b64dec_com.asm" -o "%SCRIPT_DIR%\B64DEC.COM"
  nasm -f bin "%SCRIPT_DIR%\asm\serinit_com.asm" -o "%SCRIPT_DIR%\SERINIT.COM"
  nasm -f bin "%SCRIPT_DIR%\asm\shutdown_com.asm" -o "%SCRIPT_DIR%\SHUTDOWN.COM"
  nasm -f bin "%SCRIPT_DIR%\asm\serget_com.asm" -o "%SCRIPT_DIR%\SERGET.COM"
)
EXIT /B 0
