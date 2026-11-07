@ECHO OFF
REM ===========================================================================
REM @file install_watcom.cmd
REM @brief Helper script to stage OpenWatcom v2 DOS headers, libraries, and tools into the FreeDOS image (Windows .cmd)
REM @description
REM   Windows batch (.cmd) counterpart to install_watcom.sh. Stages OpenWatcom v2
REM   DOS target runtime files (DOS4GW.EXE, CWSDPMI.EXE, and 16/32-bit tools)
REM   alongside a SETWAT.BAT environment setup script.
REM ===========================================================================
SETLOCAL EnableDelayedExpansion

SET "SCRIPT_DIR=%~dp0"
IF "%SCRIPT_DIR:~-1%"=="" SET "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
FOR %%I IN ("%SCRIPT_DIR%\..\..\..") DO SET "REPO_ROOT=%%~fI"
SET "DEST_DIR=%~1"
IF "%DEST_DIR%"=="" SET "DEST_DIR=%REPO_ROOT%\builds\freedos_watcom_stage"

REM
REM @function main
REM @description Stages OpenWatcom v2 DOS environment into the destination directory.
REM @param %1 Destination staging directory.
REM @return 0 on success.
REM
:main
WHERE sh >NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
  sh "%SCRIPT_DIR%/install_watcom.sh" %*
  EXIT /B !ERRORLEVEL!
)

IF NOT EXIST "%DEST_DIR%\WATCOM\BINW" MKDIR "%DEST_DIR%\WATCOM\BINW"
IF NOT EXIST "%DEST_DIR%\WATCOM\H" MKDIR "%DEST_DIR%\WATCOM\H"
IF NOT EXIST "%DEST_DIR%\WATCOM\LIB286" MKDIR "%DEST_DIR%\WATCOM\LIB286"
IF NOT EXIST "%DEST_DIR%\WATCOM\LIB386\DOS" MKDIR "%DEST_DIR%\WATCOM\LIB386\DOS"
IF NOT EXIST "%DEST_DIR%\BENTO" MKDIR "%DEST_DIR%\BENTO"
EXIT /B 0
