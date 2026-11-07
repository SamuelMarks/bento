@ECHO OFF
REM ===========================================================================
REM @file provision_freedos.cmd
REM @brief Host-side Packer provisioner script for standalone FreeDOS images (Windows .cmd)
REM @description
REM   Windows batch (.cmd) counterpart to provision_freedos.sh. Generates the 16-bit
REM   8086 real-mode .COM utilities (B64DEC.COM, B64ENC.COM, SERINIT.COM, SERGET.COM)
REM   and provisions the FreeDOS guest over COM1.
REM ===========================================================================
SETLOCAL EnableDelayedExpansion

SET "SCRIPT_DIR=%~dp0"
IF "%SCRIPT_DIR:~-1%"=="" SET "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
FOR %%I IN ("%SCRIPT_DIR%\..\msdos\asm") DO SET "ASM_DIR=%%~fI"

REM
REM @function main
REM @description Generates 16-bit .COM utilities for FreeDOS and provisions the guest.
REM @param %* Command-line arguments.
REM @return 0 on success.
REM
:main
WHERE sh >NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
  sh "%SCRIPT_DIR%/provision_freedos.sh" %*
  EXIT /B !ERRORLEVEL!
)

WHERE nasm >NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
  nasm -f bin "%ASM_DIR%\b64enc_com.asm" -o "%SCRIPT_DIR%\B64ENC.COM"
  nasm -f bin "%ASM_DIR%\b64dec_com.asm" -o "%SCRIPT_DIR%\B64DEC.COM"
  nasm -f bin "%ASM_DIR%\serinit_com.asm" -o "%SCRIPT_DIR%\SERINIT.COM"
  nasm -f bin "%ASM_DIR%\serget_com.asm" -o "%SCRIPT_DIR%\SERGET.COM"
)
EXIT /B 0
