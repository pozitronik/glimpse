@echo off
rem Companion launcher for the Glimpse WCX plugin settings dialog.
rem Calls ConfigurePacker via rundll32; auto-picks the bitness that matches
rem whichever Glimpse.wcx{64} variant lives next to this batch.
rem
rem Both bitnesses share the same Glimpse.ini next to the DLL, so configuring
rem via either path produces identical results.

rem `start ""` spawns rundll32 detached and returns immediately; the batch
rem then exits and the host cmd.exe closes, so users do not see a console
rem window sitting around for the lifetime of the modal settings dialog.
rem The empty "" is start's title argument, required when the first quoted
rem token is the program path.

setlocal

set "BAT_DIR=%~dp0"

rem Pick the 64-bit DLL only when the host OS can actually load it. The
rem wcx64 file may sit alongside wcx on a 32-bit Windows host because the
rem user extracted the full release archive there - presence of the file
rem is not proof the OS can run it. %SystemRoot%\SysWOW64 exists only on
rem 64-bit Windows, so its presence is the reliable test. Checking
rem PROCESSOR_ARCHITECTURE is fragile - a 32-bit cmd.exe on x64 reports x86.
if exist "%BAT_DIR%Glimpse.wcx64" (
  if exist "%SystemRoot%\SysWOW64" (
    start "" rundll32.exe "%BAT_DIR%Glimpse.wcx64",ConfigurePacker
    exit /b 0
  )
)

if exist "%BAT_DIR%Glimpse.wcx" (
  rem rundll32 must match the DLL's bitness. SysWOW64 holds the 32-bit
  rem rundll32 on x64 Windows; on a 32-bit Windows host it does not exist
  rem and the plain rundll32.exe is already 32-bit.
  if exist "%SystemRoot%\SysWOW64\rundll32.exe" (
    start "" "%SystemRoot%\SysWOW64\rundll32.exe" "%BAT_DIR%Glimpse.wcx",ConfigurePacker
  ) else (
    start "" rundll32.exe "%BAT_DIR%Glimpse.wcx",ConfigurePacker
  )
  exit /b 0
)

echo ERROR: Neither Glimpse.wcx64 nor Glimpse.wcx found next to %~nx0.
echo Place this batch in the same folder as the WCX plugin DLL.
pause
exit /b 1
