@ECHO OFF
REM ===========================================================================
REM Bento MS-DOS Command Wrapper (RUNCMD.BAT)
REM Usage: RUNCMD.BAT <REQ_ID> <COMMAND> [ARGS...]
REM Executes the target command or batch file and prints deterministic framing
REM markers with the resulting exit status (via IF ERRORLEVEL 1 for MS-DOS
REM 2.0 / 4.00 where %ERRORLEVEL% is not a built-in dynamic env variable).
REM ===========================================================================

SET BENTO_REQ=%1
SHIFT
ECHO ===START_%BENTO_REQ%===
%1 %2 %3 %4 %5 %6 %7 %8 %9
IF ERRORLEVEL 1 ECHO ===EXIT_%BENTO_REQ%:1===
IF NOT ERRORLEVEL 1 ECHO ===EXIT_%BENTO_REQ%:0===
SET BENTO_REQ=
