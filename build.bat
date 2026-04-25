@echo off
setlocal enabledelayedexpansion

echo ============================================
echo Glimpse Build Script
echo ============================================

:: Change to script directory
cd /d "%~dp0"

call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 (
    echo ERROR: Failed to set RAD Studio environment
    exit /b 1
)

:: ============================================
:: Compile WLX icon resources
:: ============================================
REM Delphi 12's cgrc 1.2.3 cannot find rc.exe via PATH; Delphi 11.3's cgrc
REM 1.2.2 ships rc.exe co-located, so we use that. Adjust the path if
REM Delphi 11.3 is not installed.
set "CGRC=C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\cgrc.exe"
REM In-block echo cannot expand %CGRC% because the (x86) parens would
REM prematurely close the IF block.
if not exist "%CGRC%" (
    echo ERROR: cgrc.exe not found. Edit build.bat to point CGRC at a Delphi
    echo        installation whose bin folder has both cgrc.exe and rc.exe.
    exit /b 1
)
"%CGRC%" -c65001 wlx\icons.rc -fowlx\icons.res
if errorlevel 1 (
    echo ERROR: Failed to compile wlx\icons.rc
    exit /b 1
)

:: ============================================
:: WLX Plugin (Win64 Debug)
:: ============================================
echo.
echo [1/2] Building WLX plugin (Win64 Debug)...

msbuild wlx\Glimpse.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:m /nologo
if errorlevel 1 (
    echo ERROR: WLX build failed
    exit /b 1
)

echo WLX build successful.

:: ============================================
:: WCX Plugin (Win64 Debug)
:: ============================================
echo.
echo [2/2] Building WCX plugin (Win64 Debug)...

msbuild wcx\Glimpse.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:m /nologo
if errorlevel 1 (
    echo ERROR: WCX build failed
    exit /b 1
)

echo WCX build successful.

echo.
echo ============================================
echo All builds successful.
echo ============================================

endlocal
